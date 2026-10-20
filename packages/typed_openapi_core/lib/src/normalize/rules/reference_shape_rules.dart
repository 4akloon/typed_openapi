import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../../model/schema.dart';
import '../../resolve/ref_target.dart';
import '../normalizer_rule.dart';

/// The discriminator property is not `required` in some variants (C-42): a
/// payload without it cannot be told apart. Reported once per
/// discriminator, with the variants.
final class DiscriminatorPropertyRequired extends NormalizerRule {
  /// Creates the rule.
  const DiscriminatorPropertyRequired();

  @override
  String get name => 'discriminator-property-required';

  @override
  List<DiagnosticCode> get codes => const [.discriminatorNotRequired];

  /// How many variant names a message lists.
  static const _shown = 10;

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final discriminator = schema.discriminator;
      final property = discriminator?.propertyName;
      if (discriminator == null || property == null) continue;
      if (_required(context, schema, {}).contains(property)) continue;
      final names = <String>{
        for (final branch in [...schema.oneOf, ...schema.anyOf])
          if (context.model.resolveSchema(branch) case final SchemaObject v
              when !_required(context, v, {}).contains(property))
            _nameOf(v),
      }.toList()..sort();
      if (names.isEmpty) continue;
      final listed = names.take(_shown).join(', ');
      final more = names.length > _shown
          ? ' and ${names.length - _shown} more'
          : '';
      yield context.finding(
        .discriminatorNotRequired,
        'Discriminator property "$property" is not required in $listed'
        '$more; a payload without it cannot be told apart.',
        discriminator.location,
        fix: 'Add "$property" to "required" of each variant at the source.',
      );
    }
  }

  /// A variant's component name, or its pointer when it is inline.
  static String _nameOf(SchemaObject variant) {
    final tokens = variant.pointer.tokens;
    return tokens.length == 3 && tokens[1] == 'schemas'
        ? tokens.last
        : variant.pointer.value;
  }

  /// The names [schema] requires, its `allOf` members included.
  static Set<String> _required(
    RuleContext context,
    SchemaObject schema,
    Set<SchemaObject> seen,
  ) {
    if (!seen.add(schema)) return const {};
    return {
      ...schema.required,
      for (final member in schema.allOf)
        if (context.model.resolveSchema(member) case final SchemaObject m)
          ..._required(context, m, seen),
    };
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      'In ASP.NET, the document requires the discriminator in the base '
          'schema only (dotnet/aspnetcore#60469, open), and we found no '
          'setting that changes that; add it to "required" of the derived schemas with a schema '
          'transformer (Microsoft.AspNetCore.OpenApi: AddSchemaTransformer) '
          'or an ISchemaFilter (Swashbuckle), or accept this info.',
    _ => null,
  };
}

/// A `discriminator.mapping` value that points nowhere (C-4). M2 does not
/// resolve mapping values, so this rule does.
final class DiscriminatorMappingTarget extends NormalizerRule {
  /// Creates the rule.
  const DiscriminatorMappingTarget();

  @override
  String get name => 'discriminator-mapping-target';

  @override
  List<DiagnosticCode> get codes => const [.discriminatorMappingUnresolved];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final schemas = context.model.document.components?.schemas ?? const {};
    for (final discriminator in context.nodes<Discriminator>()) {
      for (final MapEntry(key: value, value: target)
          in discriminator.mapping.entries) {
        final isName = _isName(target, schemas);
        final reference = isName
            ? null
            : RefTarget.parse(target, discriminator.location.document);
        final exists = switch (reference) {
          null => schemas.containsKey(target),
          ResolvableRef(:final location) => context.rawAt(location) != null,
          BrokenRef() => false,
        };
        if (exists) continue;
        final remote = reference is BrokenRef && reference.code == .remoteRef;
        yield context.finding(
          .discriminatorMappingUnresolved,
          remote
              ? 'discriminator.mapping "$value" points to "$target", a '
                    'remote document; remote references are not read.'
              : 'discriminator.mapping "$value" points to "$target", which '
                    'does not exist.',
          discriminator.location.child('mapping').child(value),
          fix:
              'Point it at an existing schema at the source; until then, '
              'override the mapping of this discriminator.',
          backendFix: 'Point it at an existing schema at the source.',
        );
      }
    }
  }

  /// Whether [target] is a schema name rather than a reference: OpenAPI
  /// reads a value without `#`, `/` or `.` as a name in
  /// `components.schemas`. A value without `#` and `/` that is a key of
  /// [schemas] is that component too, dots included (`Ns.Cat`).
  static bool _isName(String target, Map<String, Object?> schemas) =>
      !target.contains(RegExp('[#/]')) &&
      (!target.contains('.') || schemas.containsKey(target));

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .fastapi =>
      'In FastAPI, give models unique names across the app; same-named '
          'models from different modules get renamed keys.',
    .springdoc =>
      'In springdoc, declare the mapping: @Schema(discriminatorProperty = '
          '"kind", discriminatorMapping = {@DiscriminatorMapping(value = '
          '"foo1", schema = Foo1.class)}).',
    _ => null,
  };
}

/// `*/*` as a media type (C-38): the client cannot pick a decoder.
final class WildcardMediaType extends NormalizerRule {
  /// Creates the rule.
  const WildcardMediaType();

  @override
  String get name => 'wildcard-media-type';

  @override
  List<DiagnosticCode> get codes => const [.wildcardMediaType];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final media in context.nodes<MediaType>()) {
      if (media.pointer.tokens.lastOrNull != '*/*') continue;
      yield context.finding(
        .wildcardMediaType,
        'The media type "*/*" does not say how the body is encoded, so the '
        'client cannot pick a decoder.',
        media.location,
        fix:
            'Declare the actual media type (usually application/json) at the '
            'source, or override the content type here.',
        backendFix:
            'Declare the actual media type (usually application/json) at the '
            'source.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .springdoc =>
      'In springdoc, set springdoc.default-produces-media-type='
          'application/json.',
    _ => null,
  };
}

/// A key in `components` with characters OpenAPI does not allow there
/// (C-32): only letters, digits, `.`, `-` and `_`.
final class ComponentKeyCharacters extends NormalizerRule {
  /// Creates the rule.
  const ComponentKeyCharacters();

  static final _key = RegExp(r'^[a-zA-Z0-9\.\-_]+$');

  @override
  String get name => 'component-key-characters';

  @override
  List<DiagnosticCode> get codes => const [.invalidComponentKey];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final components = context.model.document.components;
    if (components == null) return;
    for (final (section, keys) in [
      ('schemas', components.schemas.keys),
      ('responses', components.responses.keys),
      ('parameters', components.parameters.keys),
      ('examples', components.examples.keys),
      ('requestBodies', components.requestBodies.keys),
      ('headers', components.headers.keys),
      ('securitySchemes', components.securitySchemes.keys),
      ('pathItems', components.pathItems.keys),
      ('mediaTypes', components.mediaTypes.keys),
    ]) {
      for (final key in keys) {
        if (_key.hasMatch(key)) continue;
        yield context.finding(
          .invalidComponentKey,
          'The component name "$key" has characters OpenAPI does not allow '
          'in component keys (only letters, digits, ".", "-" and "_").',
          components.location.child(section).child(key),
          fix: 'Rename it at the source; type names are derived from it.',
        );
      }
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      "With Swashbuckle, set CustomSchemaIds(t => t.FullName!.Replace('+', "
          "'.')).",
    .springdoc => 'In springdoc, name the schema with @Schema(name = "...").',
    _ => null,
  };
}
