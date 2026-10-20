import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_core/src/diagnostics/severity_levels.dart';

void main() {
  const warning = Diagnostic(
    code: DiagnosticCode.boolRequired,
    severity: Severity.warning,
    message: 'm',
    file: 'api.yaml',
    fix: 'f',
  );

  test('gives a code its configured level and keeps the rest', () {
    const levels = SeverityLevels({
      DiagnosticCode.boolRequired: Severity.error,
    });
    final raised = levels.apply(warning)!;
    expect(raised.severity, Severity.error);
    expect(
      (raised.code, raised.message, raised.file, raised.fix),
      (
        DiagnosticCode.boolRequired,
        'm',
        'api.yaml',
        'f',
      ),
    );
  });

  test('drops a code that is off', () {
    const levels = SeverityLevels({DiagnosticCode.boolRequired: null});
    expect(levels.apply(warning), isNull);
  });

  test('leaves codes the config does not name unchanged', () {
    const levels = SeverityLevels({DiagnosticCode.invalidValue: null});
    expect(levels.apply(warning), same(warning));
    expect(const SeverityLevels().apply(warning), same(warning));
  });

  test('every config code is fixed', () {
    expect(
      DiagnosticCode.fixedCodes.containsAll(DiagnosticCode.configCodes),
      isTrue,
    );
  });

  test('the baseline file codes are fixed, except stale entries', () {
    expect(
      DiagnosticCode.fixedCodes.containsAll([
        DiagnosticCode.baselineNotFound,
        DiagnosticCode.invalidBaseline,
        DiagnosticCode.baselineNotWritten,
      ]),
      isTrue,
    );
    expect(
      DiagnosticCode.fixedCodes.contains(DiagnosticCode.baselineEntryStale),
      isFalse,
    );
  });
}
