import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

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

  group(
    'a value that stays raw JSON is not printed when its schema could carry a secret',
    () {
      group('raw', () {
        late Map<String, String> files;
        late String session;
        setUpAll(() {
          files = emitFixture(
            'secrets_raw.yaml',
            generation: const GenerationConfig(union: .raw),
          );
          session = toStringOf(files, 'Session');
        });

        for (final field in [
          'auth',
          'auths',
          'byKey',
          'mixed',
          'additionalProperties',
        ]) {
          test(field, () => expect(session, contains('$field: <redacted>')));
        }

        test('a raw value without a secret anywhere is printed', () {
          expect(session, contains(r'harmless: $harmless'));
          expect(session, contains(r'node: $node'));
        });

        test('a typed model prints itself, with its own redaction', () {
          expect(session, contains(r'typed: $typed'));
          expect(
            toStringOf(files, 'PwLogin'),
            contains('password: <redacted>'),
          );
        });

        test('the unknown variant of a discriminated union', () {
          expect(toStringOf(files, 'TaggedUnknown'), contains('(<redacted>)'));
          expect(toStringOf(files, 'TaggedPwLogin'), contains(r'($value)'));
        });
      });

      group('structural', () {
        late Map<String, String> files;
        late String session;
        setUpAll(() {
          files = emitFixture(
            'secrets_raw.yaml',
            generation: const GenerationConfig(union: .structural),
          );
          session = toStringOf(files, 'Session');
        });

        test('the unknown variant of a union with a secret variant', () {
          for (final name in ['AuthUnknown', 'MixedUnknown', 'TaggedUnknown']) {
            expect(
              toStringOf(files, name),
              contains('(<redacted>)'),
              reason: name,
            );
          }
        });

        test('the variants print their value, which redacts itself', () {
          expect(toStringOf(files, 'AuthPwLogin'), contains(r'($value)'));
          expect(toStringOf(files, 'MixedString'), contains(r'($value)'));
          expect(session, contains(r'auth: $auth'));
        });

        test('the unknown variant of a union with no secret is printed', () {
          for (final name in ['HarmlessUnknown', 'NodeUnknown']) {
            expect(toStringOf(files, name), contains(r'($json)'), reason: name);
          }
        });
      });
    },
  );
}
