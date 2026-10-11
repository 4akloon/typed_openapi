import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  test('report uses the default severity unless overridden', () {
    final bag = DiagnosticBag()
      ..report(.duplicateKey, 'dup')
      ..report(.duplicateKey, 'dup', severity: .error);
    expect(bag.all.map((d) => d.severity), [Severity.warning, Severity.error]);
    expect(bag.hasErrors, isTrue);
  });

  test('all is a snapshot that cannot be modified', () {
    final bag = DiagnosticBag()..report(.parseError, 'x');
    expect(() => bag.all.clear(), throwsUnsupportedError);
    expect(bag.all, hasLength(1));
  });

  test('sorted returns report order and count tallies a severity', () {
    final bag = DiagnosticBag()
      ..report(.parseError, 'x', file: 'b.json')
      ..report(.duplicateKey, 'y', file: 'a.json');
    expect(bag.sorted.map((d) => d.file), ['a.json', 'b.json']);
    expect(bag.all.map((d) => d.file), ['b.json', 'a.json']);
    expect(bag.count(Severity.error), 1);
    expect(bag.count(Severity.warning), 1);
    expect(bag.count(Severity.info), 0);
  });
}
