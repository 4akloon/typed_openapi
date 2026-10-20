import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    '{\n  "openapi": "2.0"\n}',
    url: Uri.parse('api.json'),
  );

  Diagnostic make({
    DiagnosticCode code = .parseError,
    String message = 'm',
    String? file = 'api.json',
    int? offset,
    String? pointer,
  }) {
    return Diagnostic(
      code: code,
      severity: .error,
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
        make(offset: 2, pointer: '#/z', code: .rootNotObject),
        make(offset: 5, pointer: '#/a', code: .duplicateKey),
        make(offset: 5, pointer: '#/b', code: .parseError),
        make(offset: 5, pointer: '#/b', code: .duplicateKey),
        make(
          offset: 5,
          pointer: '#/b',
          code: .duplicateKey,
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

  group('Diagnostic.forBackend', () {
    Diagnostic withFix(
      String? fix, {
      String? backendFix,
      List<(String, String)> hints = const [],
    }) => Diagnostic(
      code: .arrayWithoutItems,
      severity: .warning,
      message: 'm',
      file: 'api.json',
      pointer: JsonPointer.parse('#/a'),
      span: source.span(2, 3),
      fix: fix,
      backendFix: backendFix,
      hints: hints,
    );

    test('a backend fix replaces a fix that offers an override', () {
      final d = withFix(
        'Fix it at the source, or override "items".',
        backendFix: 'Fix it at the source.',
      );
      expect(d.fix, 'Fix it at the source, or override "items".');
      expect(d.forBackend().fix, 'Fix it at the source.');
    });

    test('a fix that mentions no override is its own backend fix', () {
      expect(withFix('Quote the key.').forBackend().fix, 'Quote the key.');
    });

    test('a fix that offers an override and has no backend fix is dropped', () {
      expect(
        withFix('Override "items" of this schema.').forBackend().fix,
        isNull,
      );
    });

    test('the hints stay, after the backend fix', () {
      final d = withFix(
        'Fix it, or override it.',
        backendFix: 'Fix it.',
        hints: [('nestjs', 'In NestJS, set X.')],
      );
      expect(d.forBackend().fix, 'Fix it. In NestJS, set X.');
      expect(d.fix, 'Fix it, or override it. In NestJS, set X.');
    });

    test('the other fields and the copies of the result are kept', () {
      final d = withFix('Quote the key.', backendFix: 'Quote it.');
      final backend = d.forBackend();
      expect(backend.span, d.span);
      expect(backend.pointer?.value, d.pointer?.value);
      expect(backend.withSeverity(.info).forBackend().severity, Severity.info);
    });
  });
}
