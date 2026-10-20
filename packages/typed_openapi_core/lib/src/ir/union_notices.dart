import '../diagnostics/message_text.dart';
import '../model/schema.dart';
import 'declaration_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'mapping_scope.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';
import 'union_state.dart';

/// Reports what a union's schema says that its variants do not keep: parts
/// ignored, duplicate variants, variants that cannot be told apart, and
/// discriminator mappings that select nothing.
final class UnionNotices {
  /// Reports for the client of [_context].
  const UnionNotices(this._context, this._queries);

  final IrContext _context;
  final SchemaQueries _queries;

  /// Reports the `allOf` parts and the properties of the union at [site],
  /// which are ignored: a union is generated from its branches only. The
  /// discriminator property is what the union reads from every branch.
  void partsIgnored(UnionSite site) {
    if (site.isSubtypes) return;
    final schema = site.schema;
    final kind = site.kind.name;
    if (schema.allOf.isNotEmpty) {
      _context.report(
        .compositionPartsIgnored,
        'The allOf parts of this schema are ignored: it is generated as the '
        'union of its $kind branches.',
        schema.location.child('allOf'),
        fix: 'Put the shared parts into every branch at the source.',
      );
    }
    final hasOthers = schema.properties.keys.any(
      (name) => name != schema.discriminator?.propertyName,
    );
    if (hasOthers) {
      _context.report(
        .compositionPartsIgnored,
        'The properties of this schema are ignored: it is generated as the '
        'union of its $kind branches.',
        schema.location.child('properties'),
        fix: 'Put the shared properties into every branch at the source.',
      );
    }
  }

  /// Reports the [branch] of a union, dropped as a duplicate of an earlier
  /// variant: the same schema when [sameSchema], else the same Dart type.
  void variantDuplicate(
    Schema branch,
    UnionKind kind, {
    required bool sameSchema,
  }) {
    final what = sameSchema
        ? 'is the same schema as'
        : 'has the same Dart type as';
    _context.report(
      .unionVariantDuplicate,
      'This variant $what an earlier variant of the ${kind.name}; it is '
      'dropped, since a value could not be told apart between them.',
      branch.location,
      fix: 'Remove the duplicate variant at the source.',
    );
  }

  /// Reports the [branch] of a union with a discriminator, which is not an
  /// object and has the same JSON [kind] as an earlier variant: a value of
  /// that type is decoded as the earlier one.
  void jsonTypeShadowed(Schema branch, UnionKind kind, JsonKind jsonKind) {
    _context.report(
      .unionJsonTypeShadowed,
      'This variant is a ${jsonKind.name}, as an earlier variant of the '
      '${kind.name} is; a value that is not an object has no discriminator '
      'property, so such a value is decoded as the earlier variant and this '
      'one is never produced.',
      branch.location,
      fix:
          'Remove the variant at the source, or give the earlier variant a '
          'type that does not take every ${jsonKind.name}.',
    );
  }

  /// Reports the branches of [schema] that add no value to another branch
  /// (TOA455), unless a custom type replaces [schema]. [collapsed] says the
  /// union is left with one branch, which is then its type.
  void subsumedBranches(
    SchemaObject schema,
    MappingScope scope, {
    required bool collapsed,
  }) {
    if (scope.replacing) return;
    for (final MapEntry(key: branch, value: kind)
        in SchemaShapes.subsumedBranches(schema, refs: _queries.refs).entries) {
      final values = SchemaShapes.enumValues(branch)!;
      final shown = [
        for (final value in values.take(3)) _valueText(value),
        if (values.length > 3) '...',
      ].join(', ');
      _context.report(
        .unionBranchSubsumed,
        'The enum [$shown] branch adds no value to the ${kind.name} branch; '
        '${collapsed ? 'the schema is generated as the ${kind.name} branch '
                  'alone.' : 'it is dropped from the union.'}',
        branch.location,
        fix:
            'Remove the enum branch at the source, or leave it for the '
            'documentation.',
      );
    }
  }

  /// [value] of an enum as it is written in a Dart list, for a message.
  static String _valueText(Object? value) {
    if (value is! String) return MessageText.neutralise('$value');
    final escaped = value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    return "'${MessageText.neutralise(escaped)}'";
  }

  /// Reports the discriminator of [schema], which is generated as a model
  /// because it is no union and no schema extends it: it picks nothing.
  void discriminatorWithoutSubtypes(SchemaObject schema) {
    final discriminator = schema.discriminator;
    if (discriminator == null || discriminator.propertyName == null) return;
    _context.report(
      .discriminatorWithoutSubtypes,
      'This discriminator is on a schema that is not a oneOf or anyOf '
      'union and that no schema extends with allOf, so it picks '
      'nothing; the schema is generated as a model.',
      discriminator.location,
      fix:
          'Extend the schema with allOf in its subtypes, or list them '
          'in a oneOf.',
    );
  }

  /// Reports the branches of the union at [site] that share a JSON type
  /// ([shared]): the branches at [conflicted] are one variant of any JSON
  /// value.
  void sharedJsonType(
    UnionSite site,
    Set<int> conflicted,
    List<JsonKind> shared,
  ) {
    final names = [
      for (final (i, branch) in site.branches.indexed)
        if (conflicted.contains(i)) _branchName(branch, i),
    ];
    final types = ([
      ...shared,
    ]..sort((a, b) => a.index - b.index)).map((k) => k.name).join(', ');
    final schema = site.schema;
    _context.report(
      .unionUndiscriminated,
      'Variants ${names.join(', ')} of this ${site.kind.name} share the JSON '
      'type $types, so a value of it cannot be told apart; such a value '
      'is kept as JsonValue in one variant.',
      schema.location,
      fix:
          'Add a discriminator at the source, or generate a union that '
          'tries the variants with union: structural (an override of the '
          'schema, or the config key for every such union).',
      override: _context.schemaOverride(schema.location, {
        'union': 'structural',
      }),
    );
  }

  /// How a diagnostic names the branch [index] of a union: the schema it
  /// refers to, or its position.
  String _branchName(Schema branch, int index) =>
      branch is SchemaObject && branch.ref != null
      ? switch (_queries.resolved(branch)) {
          final target? => DeclarationNames.referenceName(target.location),
          null => '#$index',
        }
      : '#$index';

  /// Reports the discriminator [value], which maps to the base schema of a
  /// union of its subtypes.
  void mappingToBase(Discriminator discriminator, String value) {
    _context.report(
      .discriminatorMappingNotVariant,
      'Discriminator value ${MessageText.quote(value)} maps to the base '
      'schema itself, which is generated as the union of its subtypes; a value with '
      'it is decoded as unknown, with its JSON kept.',
      discriminator.location.child('mapping').child(value),
      fix: 'Map the value to a schema that extends the base.',
    );
  }

  /// Reports the discriminator [value], which maps to a schema that is not
  /// a variant.
  void mappingNotVariant(Discriminator discriminator, String value) {
    _context.report(
      .discriminatorMappingNotVariant,
      'Discriminator value ${MessageText.quote(value)} maps to a schema that '
      'is not a variant of this union; it is ignored.',
      discriminator.location.child('mapping').child(value),
      fix: "Map the value to one of the union's variants.",
    );
  }

  /// Reports the inline [variant], which no discriminator value selects.
  void valueMissing(Schema variant) {
    _context.report(
      .discriminatorValueMissing,
      'This variant is written inline, so no discriminator value '
      'selects it.',
      variant.location,
      fix: r'Make the variant a component schema and $ref it.',
    );
  }

  /// Reports that the constant [value] of the discriminator property of
  /// [variant], not its component name [key], selects it.
  void valueDerived(String value, String key, Schema variant) {
    final quotedValue = MessageText.quote(value);
    final quotedKey = MessageText.quote(key);
    _context.report(
      .discriminatorValueDerived,
      'The mapping does not name this variant, and its discriminator '
      'property is always $quotedValue, so $quotedValue selects it, not '
      'the component name $quotedKey.',
      variant.location,
      fix:
          'Add $quotedValue to the mapping to say so, or map the name '
          '$quotedKey if the payloads carry it.',
    );
  }

  /// Reports the discriminator [value] that also selects the earlier
  /// variant, so [variant] is never picked by it.
  void valueDuplicate(String value, Schema variant) {
    _context.report(
      .discriminatorValueDuplicate,
      'Discriminator value ${MessageText.quote(value)} also selects an '
      'earlier variant; the earlier one decodes it, so this variant is never '
      'picked by that value.',
      variant.location,
      fix:
          'Give each variant its own discriminator value, in the '
          'mapping or in the const of the property.',
    );
  }

  /// Reports the default mapping [ref] of [discriminator], which names no
  /// variant.
  void defaultNotVariant(Discriminator discriminator, String ref) {
    _context.report(
      .discriminatorMappingNotVariant,
      'The default mapping ${MessageText.quote(ref)} is not a variant of '
      'this union; it is ignored.',
      discriminator.location.child('defaultMapping'),
      fix: "Map the default to one of the union's variants.",
    );
  }
}
