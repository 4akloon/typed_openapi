import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';

/// An array without `items` in an OpenAPI 3.0 document (C-5), which 3.0
/// requires; its elements are read as any JSON value.
final class ArrayWithoutItems extends NormalizerRule {
  /// Creates the rule.
  const ArrayWithoutItems();

  @override
  String get name => 'array-without-items';

  @override
  List<DiagnosticCode> get codes => const [.arrayWithoutItems];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    if (context.version != .v30) return;
    for (final schema in context.nodes<SchemaObject>()) {
      if (!schema.types.contains(SchemaType.array) || schema.items != null) {
        continue;
      }
      // A format on the array is FormatOnArray's finding.
      if (schema.format != null || _hasItemsKey(context, schema)) continue;
      yield context.finding(
        .arrayWithoutItems,
        'This array has no "items", which OpenAPI 3.0 requires; its elements '
        'are read as any JSON value.',
        schema.location,
        fix:
            'Add "items" with the element schema at the source, or override '
            '"items" of this schema.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, give the element type: @ApiProperty({ type: [Item] }).',
    _ => null,
  };

  /// Whether [schema] writes an `items` key, even one the parser rejected.
  static bool _hasItemsKey(RuleContext context, SchemaObject schema) =>
      context.rawObject(schema.location)?.containsKey('items') ?? false;
}

/// An array whose `items` is an array again and carries a boolean
/// `required` (C-49): the NestJS `type: [X]` plus `isArray: true` pattern,
/// which reads as a list of lists.
final class DoubleArray extends NormalizerRule {
  /// Creates the rule.
  const DoubleArray();

  @override
  String get name => 'double-array';

  @override
  List<DiagnosticCode> get codes => const [.doubleArray];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final items = schema.items;
      if (!schema.types.contains(SchemaType.array) ||
          items is! SchemaObject ||
          !items.types.contains(SchemaType.array)) {
        continue;
      }
      final raw = context.rawObject(items.location);
      if (raw == null || raw['required'] is! bool) continue;
      yield context.finding(
        .doubleArray,
        'The items of this array are arrays too and say "required: '
        '${raw['required']}", the shape a decorator gives a list declared '
        'twice; clients read a list of lists.',
        items.location,
        fix:
            'If the field is a flat list, declare it once at the source; '
            'until then, override "items" of this schema with the inner '
            '"items".',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, write @ApiProperty({ type: [Item] }) without '
          '`isArray: true`.',
    _ => null,
  };
}

/// `format` on an array without `items` (C-50): the format belongs to the
/// elements.
final class FormatOnArray extends NormalizerRule {
  /// Creates the rule.
  const FormatOnArray();

  @override
  String get name => 'format-on-array';

  @override
  List<DiagnosticCode> get codes => const [.formatOnArray];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final format = schema.format;
      if (format == null ||
          !schema.types.contains(SchemaType.array) ||
          schema.items != null ||
          ArrayWithoutItems._hasItemsKey(context, schema)) {
        continue;
      }
      yield context.finding(
        .formatOnArray,
        '"format: $format" is on the array, which has no "items", not on its '
        'elements.',
        schema.location.child('format'),
        fix:
            'Move it into the elements at the source; until then, override '
            '"items" of this schema with {type: string, format: $format}.',
      );
    }
  }
}

/// `type: object` with `format: binary` (C-51): a file is
/// `type: string, format: binary`.
final class BinaryObject extends NormalizerRule {
  /// Creates the rule.
  const BinaryObject();

  @override
  String get name => 'binary-object';

  @override
  List<DiagnosticCode> get codes => const [.binaryObject];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.format != 'binary' ||
          !schema.types.contains(SchemaType.object)) {
        continue;
      }
      yield context.finding(
        .binaryObject,
        '"type: object" with "format: binary" does not describe a file; a '
        'file is "type: string, format: binary".',
        schema.location.child('type'),
        fix:
            'Write "type: string" at the source; until then, override "type" '
            'of this schema with string.',
      );
    }
  }
}

/// `type: object` next to `oneOf`/`anyOf` whose branches are all of other
/// types (C-22): no value matches both.
final class ContradictoryObjectType extends NormalizerRule {
  /// Creates the rule.
  const ContradictoryObjectType();

  @override
  String get name => 'contradictory-object-type';

  @override
  List<DiagnosticCode> get codes => const [.contradictoryObjectType];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final branches = [...schema.oneOf, ...schema.anyOf];
      if (branches.isEmpty || !schema.types.contains(SchemaType.object)) {
        continue;
      }
      final types = <SchemaType>{};
      var known = true;
      for (final branch in branches) {
        final resolved = context.model.resolveSchema(branch);
        if (resolved is! SchemaObject || resolved.types.isEmpty) {
          known = false;
          break;
        }
        types.addAll(resolved.types);
      }
      if (!known || types.contains(SchemaType.object)) continue;
      final names = (types.map((t) => t.wire).toList()..sort()).join(', ');
      yield context.finding(
        .contradictoryObjectType,
        '"type: object" is next to "oneOf"/"anyOf" whose branches are all '
        '$names; no value matches both.',
        schema.location.child('type'),
        fix:
            'Remove "type: object" at the source; until then, override "type" '
            'of this schema.',
      );
    }
  }
}

/// An `example` whose JSON type the schema does not allow (C-60). A list for
/// an object schema, or a structure against a scalar, is a warning: clients
/// built from the schema fail on such values. A scalar of another type
/// (`example: "1.5"` for a number) is info: the decoder is unaffected and
/// only the documentation is off.
final class ExampleTypeMismatch extends NormalizerRule {
  /// Creates the rule.
  const ExampleTypeMismatch();

  @override
  String get name => 'example-type-mismatch';

  @override
  List<DiagnosticCode> get codes => const [
    .exampleTypeMismatch,
    .exampleScalarType,
  ];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final example = schema.example;
      if (example == null) continue;
      final (value,) = example;
      if (value == null) continue;
      final types = _effectiveTypes(context, schema, {});
      if (types.isEmpty || types.any((t) => t.accepts(value))) continue;
      final names = types.map((t) => t.wire).join(' or ');
      final structural =
          value is List<Object?> ||
          value is Map<String, Object?> ||
          types.any((t) => t == .array || t == .object);
      yield structural
          ? context.finding(
              .exampleTypeMismatch,
              'The example is ${ObjectReader.describe(value)}, but the schema '
              'is $names; clients built from the schema fail on such values.',
              schema.location.child('example'),
              fix:
                  'Fix the schema or the example at the source; if the '
                  'example is right, override "type" of this schema.',
            )
          : context.finding(
              .exampleScalarType,
              'The example is ${ObjectReader.describe(value)}, but the schema '
              'is $names; the documentation shows a value of another type.',
              schema.location.child('example'),
              fix: 'Write the example as a $names at the source.',
            );
    }
  }

  /// The types [schema] allows: its own, or those of the only schema it
  /// refers to (`$ref`, or `allOf` with one member); `object` for a schema
  /// with properties and no type.
  static List<SchemaType> _effectiveTypes(
    RuleContext context,
    SchemaObject schema,
    Set<SchemaObject> seen,
  ) {
    if (!seen.add(schema)) return const [];
    if (schema.types.isNotEmpty) return schema.types;
    if (schema.properties.isNotEmpty) return const [.object];
    final target = schema.ref != null
        ? context.model.resolveSchema(schema)
        : schema.allOf.length == 1
        ? context.model.resolveSchema(schema.allOf.single)
        : null;
    if (target is! SchemaObject) return const [];
    return _effectiveTypes(context, target, seen);
  }
}
