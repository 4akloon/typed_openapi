import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../model/spec_node.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// `required: true` on a property schema (OpenAPI 2 style, C-1, C-49)
/// moves the property's name into the `required` list of the object schema;
/// `required: false` is removed.
///
/// The fix is unambiguous: OpenAPI 3 has exactly one way to say a property
/// is required.
final class BoolRequiredToArray extends NormalizerRule {
  /// Creates the rule.
  const BoolRequiredToArray();

  @override
  String get name => 'bool-required-to-array';

  @override
  List<DiagnosticCode> get codes => const [.boolRequired];

  @override
  Iterable<Finding> check(RuleContext context) {
    final flags = <(SchemaObject, String, SchemaObject, bool)>[];
    final added = <SpecLocation, List<String>>{};
    for (final schema in context.nodes<SchemaObject>()) {
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        if (property is! SchemaObject) continue;
        final flag = _flagOf(context, property);
        if (flag == null) continue;
        flags.add((schema, name, property, flag));
        if (flag) (added[schema.location] ??= []).add(name);
      }
    }
    final flagged = {
      for (final (_, _, property, _) in flags) property.location,
    };
    final findings = <Finding>[];
    final listed = <SpecLocation>{};
    for (final (schema, name, property, flag) in flags) {
      final at = property.location.child('required');
      // A parent whose "required" is something else than a list cannot take
      // the name; its own TOA111 stays and has to be fixed first.
      final blocked = flag && _cannotTake(context, schema, flagged);
      final destination = blocked
          ? 'which has to become a list before the name can be put there'
          : 'so the name is moved there';
      findings.add(
        context.finding(
          .boolRequired,
          flag
              ? 'Property "$name" says "required: true", the OpenAPI 2 way; '
                    'OpenAPI 3 lists required properties in the "required" '
                    'array of the object, $destination.'
              : 'Property "$name" says "required: false", the OpenAPI 2 way; '
                    'a property missing from "required" is optional, so the '
                    'flag is removed.',
          at,
          fix: blocked
              ? 'Make "required" of the object schema a list, then add '
                    '"$name" to it and remove "required" from the property.'
              : flag
              ? 'Add "$name" to "required" of the object schema and remove '
                    '"required" from the property.'
              : 'Remove "required: false" from the property.',
          edits: [
            // A property that is also an object with required properties
            // gets its "required" replaced by that list below instead.
            if (!blocked && !added.containsKey(property.location))
              SpecEdit.remove(at),
            if (flag && !blocked && listed.add(schema.location))
              _listEdit(context, schema, added[schema.location]!),
          ],
        ),
      );
    }
    return findings;
  }

  /// Whether `required` of [schema] is neither missing, nor a list, nor the
  /// flag of a property in [flagged] that this rule replaces by a list.
  static bool _cannotTake(
    RuleContext context,
    SchemaObject schema,
    Set<SpecLocation> flagged,
  ) => switch (context.rawAt(schema.location.child('required'))) {
    null || (final List<Object?> _,) => false,
    (final bool _,) => !flagged.contains(schema.location),
    _ => true,
  };

  /// `required` of [property] when it is a boolean.
  static bool? _flagOf(RuleContext context, SchemaObject property) =>
      switch (context.rawAt(property.location)) {
        (final Map<String, Object?> raw,) => switch (raw['required']) {
          final bool flag => flag,
          _ => null,
        },
        _ => null,
      };

  /// The edit that makes `required` of [schema] list [names] after the
  /// names it already lists.
  static SpecEdit _listEdit(
    RuleContext context,
    SchemaObject schema,
    List<String> names,
  ) {
    final at = schema.location.child('required');
    final existing = switch (context.rawAt(at)) {
      (final List<Object?> list,) => list,
      _ => const <Object?>[],
    };
    final list = [
      ...existing,
      for (final name in names)
        if (!existing.contains(name)) name,
    ];
    return switch (context.rawAt(at)) {
      null => SpecEdit.add(at, list),
      _ => SpecEdit.replace(at, list),
    };
  }
}
