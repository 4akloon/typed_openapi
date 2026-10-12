import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';

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
        fix: context.withOverride(
          'Remove "type: object" at the source; until then, remove "type" of '
          'this schema with an override.',
          schema.location,
          {'type': null},
        ),
      );
    }
  }
}
