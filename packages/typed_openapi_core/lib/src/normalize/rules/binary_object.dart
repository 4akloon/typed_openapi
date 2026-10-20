import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';

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
        fix: context.withOverride(
          'Write "type: string" at the source; until then, override "type" '
          'of this schema with string.',
          schema.location,
          {'type': 'string'},
        ),
      );
    }
  }
}
