import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';

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
      const fix =
          'If the field is a flat list, declare it once at the source; '
          'until then, override "items" of this schema with the inner '
          '"items".';
      yield context.finding(
        .doubleArray,
        'The items of this array are arrays too and say "required: '
        '${raw['required']}", the shape a decorator gives a list declared '
        'twice; clients read a list of lists.',
        items.location,
        fix: switch (raw['items']) {
          final Map<String, Object?> inner => context.withOverride(
            fix,
            schema.location,
            {'items': inner},
          ),
          _ => fix,
        },
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
