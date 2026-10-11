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
    final findings = <Finding>[];
    final listed = <SpecLocation>{};
    for (final (schema, name, property, flag) in flags) {
      final at = property.location.child('required');
      findings.add(
        context.finding(
          .boolRequired,
          flag
              ? 'Property "$name" says "required: true", the OpenAPI 2 way; '
                    'OpenAPI 3 lists required properties in the "required" '
                    'array of the object, so the name is moved there.'
              : 'Property "$name" says "required: false", the OpenAPI 2 way; '
                    'a property missing from "required" is optional, so the '
                    'flag is removed.',
          at,
          fix: flag
              ? 'Add "$name" to "required" of the object schema and remove '
                    '"required" from the property.'
              : 'Remove "required: false" from the property.',
          edits: [
            // A property that is also an object with required properties
            // gets its "required" replaced by that list below instead.
            if (!added.containsKey(property.location)) SpecEdit.remove(at),
            if (flag && listed.add(schema.location))
              _listEdit(context, schema, added[schema.location]!),
          ],
        ),
      );
    }
    return findings;
  }

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
