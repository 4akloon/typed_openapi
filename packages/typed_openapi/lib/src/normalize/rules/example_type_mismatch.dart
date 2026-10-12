import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';

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
