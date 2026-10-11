import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  test('report uses the default severity unless overridden', () {
    final bag = DiagnosticBag()
      ..report(DiagnosticCode.duplicateKey, 'dup')
      ..report(DiagnosticCode.duplicateKey, 'dup', severity: Severity.error);
    expect(bag.all.map((d) => d.severity), [Severity.warning, Severity.error]);
    expect(bag.hasErrors, isTrue);
  });

  test('all is a snapshot that cannot be modified', () {
    final bag = DiagnosticBag()..report(DiagnosticCode.parseError, 'x');
    expect(() => bag.all.clear(), throwsUnsupportedError);
    expect(bag.all, hasLength(1));
  });
}
