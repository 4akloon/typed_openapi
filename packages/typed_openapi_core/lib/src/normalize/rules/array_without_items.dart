import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
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
      if (schema.format != null || hasItemsKey(context, schema)) continue;
      yield context.finding(
        .arrayWithoutItems,
        'This array has no "items", which OpenAPI 3.0 requires; its elements '
        'are read as any JSON value.',
        schema.location,
        fix:
            'Add "items" with the element schema at the source, or override '
            '"items" of this schema.',
        backendFix: 'Add "items" with the element schema at the source.',
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
  static bool hasItemsKey(RuleContext context, SchemaObject schema) =>
      context.rawObject(schema.location)?.containsKey('items') ?? false;
}
