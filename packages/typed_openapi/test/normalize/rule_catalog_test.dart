import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

void main() {
  test('rule names are unique kebab-case, and each code has one rule', () {
    final names = Normalizer.rules.map((r) => r.name).toList();
    expect(names.toSet(), hasLength(names.length));
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
    final codes = [for (final rule in Normalizer.rules) ...rule.codes];
    expect(codes.toSet(), hasLength(codes.length));
  });

  test('every M3 rule code is in the catalog, in its range', () {
    final ids = {
      for (final rule in Normalizer.rules)
        for (final code in rule.codes) code.id,
    };
    expect(ids, {
      'TOA106',
      'TOA201',
      'TOA202',
      'TOA203',
      'TOA204',
      'TOA205',
      'TOA206',
      'TOA207',
      'TOA208',
      'TOA211',
      'TOA301',
      'TOA303',
      'TOA401',
      'TOA402',
      'TOA501',
      'TOA502',
      'TOA503',
      'TOA504',
      'TOA601',
    });
  });

  test('each framework preset has recipes, generic has none', () {
    String? hintFor(Preset preset) => [
      for (final rule in Normalizer.rules)
        for (final code in rule.codes) ?rule.hint(code, preset),
    ].firstOrNull;
    for (final preset in [
      Preset.nestjs,
      Preset.fastapi,
      Preset.springdoc,
      Preset.aspnet,
    ]) {
      expect(hintFor(preset), isNotNull, reason: preset.name);
    }
    expect(hintFor(Preset.generic), isNull);
  });

  test('a code a rule reports is never one the parser reports', () {
    const parser = {
      DiagnosticCode.unknownKey,
      DiagnosticCode.invalidValue,
      DiagnosticCode.missingRequiredField,
    };
    for (final rule in Normalizer.rules) {
      expect(rule.codes.toSet().intersection(parser), isEmpty);
    }
  });
}
