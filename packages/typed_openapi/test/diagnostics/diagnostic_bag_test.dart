import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  test('report uses the default severity unless overridden', () {
    final bag = DiagnosticBag()
      ..report(.duplicateKey, 'dup')
      ..report(.duplicateKey, 'dup', severity: .error);
    expect(bag.all.map((d) => d.severity), [Severity.warning, Severity.error]);
    expect(bag.hasErrors, isTrue);
  });

  test('an exact duplicate is ignored; any difference keeps both', () {
    final source = SourceFile.fromString('a: 1\nb: 2\n', url: 'api.yaml');
    final bag = DiagnosticBag()
      ..report(
        .unknownKey,
        'Unknown key "b".',
        file: 'api.yaml',
        pointer: JsonPointer.parse('#/b'),
        span: source.span(5, 6),
      )
      ..report(
        .unknownKey,
        'Unknown key "b".',
        file: 'api.yaml',
        pointer: JsonPointer.parse('#/b'),
        span: source.span(5, 6),
        fix: 'Another fix text does not make it another problem.',
      )
      ..report(
        .unknownKey,
        'Unknown key "b".',
        file: 'api.yaml',
        pointer: JsonPointer.parse('#/b'),
        span: source.span(0, 1),
      )
      ..report(.unknownKey, 'Unknown key "b".', file: 'other.yaml')
      ..report(.invalidValue, 'Unknown key "b".', file: 'api.yaml')
      ..report(.unknownKey, 'Unknown key "c".', file: 'api.yaml')
      ..report(
        .unknownKey,
        'Unknown key "b".',
        file: 'api.yaml',
        pointer: JsonPointer.parse('#/b'),
        span: source.span(5, 6),
        severity: .error,
      );
    expect(bag.all, hasLength(6));
    bag.add(bag.all.first);
    expect(bag.all, hasLength(6));
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
