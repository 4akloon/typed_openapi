import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';

/// The `toString` line of the class [name] in the files [files].
String toStringOf(Map<String, String> files, String name) {
  final source = files.values.join('\n');
  final start = source.indexOf('class $name ');
  if (start < 0) throw StateError('no class $name');
  final end = source.indexOf('String toString()', start);
  return source.substring(end, source.indexOf('\n', end));
}

void main() {
  for (final mode in UnionMode.values) {
    group('toString does not print a secret ($mode)', () {
      late Map<String, String> files;
      late String login;
      setUpAll(() {
        files = emitFixture(
          'secrets.yaml',
          generation: GenerationConfig(union: mode),
        );
        login = toStringOf(files, 'Login');
      });

      for (final field in [
        'plain',
        'written',
        'anyOfNull',
        'oneOfNull',
        'refTarget',
        'refNullable',
        'annotated',
        'tokens',
        'tokenRefs',
        'byName',
        'cred',
        'creds',
      ]) {
        test(field, () => expect(login, contains('$field: <redacted>')));
      }

      test('a field that is not a secret is printed', () {
        expect(login, contains(r'name: $name'));
      });

      test('the values of additionalProperties', () {
        expect(
          toStringOf(files, 'Extra'),
          contains('additionalProperties: <redacted>'),
        );
        expect(toStringOf(files, 'Extra'), contains(r'name: $name'));
      });

      test('a union variant that holds a secret, and the unknown one', () {
        expect(toStringOf(files, 'CredString'), contains('(<redacted>)'));
        expect(toStringOf(files, 'CredInt'), contains(r'($value)'));
        expect(toStringOf(files, 'CredUnknown'), contains('(<redacted>)'));
      });
    });
  }
}
