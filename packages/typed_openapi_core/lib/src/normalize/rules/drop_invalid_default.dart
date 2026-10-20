import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// A `default` whose JSON type is none of the schema's `type`s (C-28) is
/// ignored, as the parser ignores any value of the wrong type.
final class DropInvalidDefault extends NormalizerRule {
  /// Creates the rule.
  const DropInvalidDefault();

  @override
  String get name => 'drop-invalid-default';

  @override
  List<DiagnosticCode> get codes => const [.invalidDefault];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final value = schema.defaultValue;
      if (value == null || schema.types.isEmpty) continue;
      final (raw,) = value;
      if (raw == null && schema.nullable == true) continue;
      if (schema.types.any((type) => type.accepts(raw))) continue;
      final types = schema.types.map((t) => t.wire).join(' or ');
      final at = schema.location.child('default');
      yield context.finding(
        .invalidDefault,
        'The default, ${ObjectReader.describe(raw)}, is not of type $types; '
        'it is ignored.',
        at,
        fix: 'Change the default to a value of type $types, or remove it.',
        edits: [SpecEdit.remove(at)],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, check `default` in @ApiProperty; '
          '`excludeDynamicDefaults: true` in SwaggerModule.createDocument '
          'leaves out defaults computed at runtime.',
    _ => null,
  };
}
