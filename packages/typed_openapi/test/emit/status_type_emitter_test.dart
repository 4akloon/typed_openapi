@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/emit_fixture.dart';

/// The `toString` line of the class [name] in the files [files].
String toStringOf(Map<String, String> files, String name) {
  final source = files.values.join('\n');
  final start = source.indexOf('class $name ');
  if (start < 0) throw StateError('no class $name');
  final end = source.indexOf('String toString()', start);
  final next = source.indexOf('\nclass ', start + 1);
  if (end < 0 || (next >= 0 && end > next)) return '';
  return source.substring(end, source.indexOf('\n', end));
}

void main() {
  group('the variants of a status type print their body', () {
    late Map<String, String> files;
    setUpAll(() {
      files = emitClient(
        'status_bodies.yaml',
        generation: const GenerationConfig(union: .raw),
      );
    });

    test('a model prints itself, which redacts its own secrets', () {
      expect(
        toStringOf(files, 'GetThingResponseOk'),
        r"String toString() => 'GetThingResponseOk($body)';",
      );
      expect(
        toStringOf(files, 'GetThingErrorNotFound'),
        r"String toString() => 'GetThingErrorNotFound($body)';",
      );
    });

    test('a variant without a body has no body to print', () {
      expect(
        toStringOf(files, 'GetThingResponseNoContent'),
        "String toString() => 'GetThingResponseNoContent()';",
      );
      expect(
        toStringOf(files, 'GetThingErrorServiceUnavailable'),
        "String toString() => 'GetThingErrorServiceUnavailable()';",
      );
    });

    test('bytes print their length, not their content', () {
      expect(
        toStringOf(files, 'GetThingResponseCreated'),
        "String toString() => 'GetThingResponseCreated"
        r"(Uint8List(${body.length}))';",
      );
    });

    test('bytes of a JSON body print their length too', () {
      expect(
        toStringOf(files, 'GetThingResponseMultiStatus'),
        "String toString() => 'GetThingResponseMultiStatus"
        r"(Uint8List(${body.length}))';",
      );
    });

    test('bytes that may be null print null, else their length', () {
      expect(
        toStringOf(files, 'GetThingErrorBadRequest'),
        "String toString() => 'GetThingErrorBadRequest"
        r"(${body == null ? 'null' : 'Uint8List(${body?.length})'})';",
      );
    });

    test('raw JSON without a secret anywhere is printed', () {
      expect(
        toStringOf(files, 'GetThingResponseAccepted'),
        r"String toString() => 'GetThingResponseAccepted($body)';",
      );
    });

    test('raw JSON that could carry a secret is not printed', () {
      expect(
        toStringOf(files, 'GetThingResponseNonAuthoritativeInformation'),
        'String toString() => '
        "'GetThingResponseNonAuthoritativeInformation(<redacted>)';",
      );
    });

    test('a body that is a secret is not printed', () {
      expect(
        toStringOf(files, 'GetThingResponsePartialContent'),
        "String toString() => 'GetThingResponsePartialContent(<redacted>)';",
      );
      expect(
        toStringOf(files, 'GetThingErrorClientError'),
        "String toString() => 'GetThingErrorClientError(<redacted>)';",
      );
    });

    test('a status that takes the default error body takes its secrecy', () {
      final withDefault = emitClient(
        'status_bodies.yaml',
        generation: const GenerationConfig(defaultErrorSchema: 'Secretive'),
      );
      expect(
        toStringOf(withDefault, 'GetThingErrorServiceUnavailable'),
        "String toString() => 'GetThingErrorServiceUnavailable(<redacted>)';",
      );
    });

    test('a value of every union mode is printed the same way', () {
      for (final mode in UnionMode.values) {
        final other = emitClient(
          'status_bodies.yaml',
          generation: GenerationConfig(union: mode),
        );
        expect(
          toStringOf(other, 'GetThingResponsePartialContent'),
          contains('<redacted>'),
          reason: mode.name,
        );
        expect(
          toStringOf(other, 'GetThingResponseNoContent'),
          contains('NoContent()'),
          reason: mode.name,
        );
      }
    });
  });
}
