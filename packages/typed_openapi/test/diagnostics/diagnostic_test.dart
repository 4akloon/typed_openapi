import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    '{\n  "openapi": "2.0"\n}',
    url: Uri.parse('api.json'),
  );

  Diagnostic make({
    DiagnosticCode code = DiagnosticCode.parseError,
    String message = 'm',
    String? file = 'api.json',
    int? offset,
    String? pointer,
  }) {
    return Diagnostic(
      code: code,
      severity: Severity.error,
      message: message,
      file: file,
      pointer: pointer == null ? null : JsonPointer.parse(pointer),
      span: offset == null ? null : source.span(offset, offset + 1),
    );
  }

  group('Diagnostic.compareTo', () {
    test('orders by file first', () {
      expect(make(file: 'a.json').compareTo(make(file: 'b.json')), isNegative);
      expect(make(file: null).compareTo(make(file: 'a.json')), isNegative);
    });

    test('in the same file orders by offset, then pointer, code, message', () {
      final ordered = [
        make(offset: 2, pointer: '#/z', code: DiagnosticCode.rootNotObject),
        make(offset: 5, pointer: '#/a', code: DiagnosticCode.duplicateKey),
        make(offset: 5, pointer: '#/b', code: DiagnosticCode.parseError),
        make(offset: 5, pointer: '#/b', code: DiagnosticCode.duplicateKey),
        make(
          offset: 5,
          pointer: '#/b',
          code: DiagnosticCode.duplicateKey,
          message: 'z',
        ),
      ];
      final shuffled = [
        ordered[3],
        ordered[0],
        ordered[4],
        ordered[2],
        ordered[1],
      ]..sort();
      expect(shuffled, ordered);
    });

    test(
      'a diagnostic without a position sorts before one with a position',
      () {
        expect(make().compareTo(make(offset: 0)), isNegative);
      },
    );
  });

  group('Diagnostic positions', () {
    test('line, column and location are 1-based', () {
      final d = make(offset: 15, pointer: '#/openapi');
      expect(d.line, 2);
      expect(d.column, 14);
      expect(d.location, 'api.json:2:14');
    });

    test('without a span there is only the file', () {
      final d = make();
      expect(d.line, isNull);
      expect(d.column, isNull);
      expect(d.location, 'api.json');
      expect(make(file: null).location, isNull);
    });
  });
}
