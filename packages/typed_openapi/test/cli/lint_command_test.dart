import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

void main() {
  final fixture = Fixtures.path('backend_defects.yaml');

  Future<(int, String, String)> lint(List<String> args) =>
      CliRunner.run(['lint', ...args]);

  String warningOnly() => TempDir().write('warning.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /tags:
    get:
      operationId: listTags
      responses: {"204": {description: ok}}
components:
  schemas:
    Tags: {type: array}
''');

  test('lint needs no config and is advisory: findings exit 0', () async {
    final (code, out, err) = await lint([fixture]);
    expect(code, 0);
    expect(err, isEmpty);
    expect(out, contains('error TOA402 discriminator-mapping-unresolved'));
    expect(out, contains('errors: 3, warnings: 11, infos: 1'));
  });

  test('--fail-on error exits 1 for an error and 0 for a warning', () async {
    expect((await lint([fixture, '--fail-on', 'error'])).$1, 1);
    expect((await lint([warningOnly(), '--fail-on', 'error'])).$1, 0);
  });

  test('--fail-on warning exits 1 for a warning', () async {
    expect((await lint([warningOnly(), '--fail-on', 'warning'])).$1, 1);
    expect((await lint([warningOnly()])).$1, 0);
  });

  test('the report never tells the reader to write an override', () async {
    final override = RegExp('override', caseSensitive: false);
    for (final format in ['text', 'json', 'sarif', 'github-actions']) {
      for (final preset in ['generic', 'nestjs', 'fastapi', 'springdoc']) {
        final (_, out, err) = await lint([
          fixture,
          '--format',
          format,
          '--preset',
          preset,
        ]);
        expect(out, isNot(matches(override)), reason: '$format $preset');
        expect(err, isNot(matches(override)), reason: '$format $preset');
      }
    }
  });

  test(
    'each finding shows the source fix, then the recipe of the preset',
    () async {
      final (_, out, _) = await lint([fixture, '--preset', 'nestjs']);
      final fix = out
          .split('\n')
          .firstWhere((line) => line.contains('operationIdFactory'));
      expect(
        fix,
        startsWith(
          '  fix: Give each operation its own operationId at the source. '
          'In NestJS',
        ),
      );
    },
  );

  test('the framework of the spec is detected and said', () async {
    final path = TempDir().write(
      'fastapi.yaml',
      '${Fixtures.read('backend_defects.yaml')}'
          '    HTTPValidationError: {type: object}\n'
          '    ValidationError: {type: object}\n',
    );
    final (_, out, _) = await lint([path]);
    expect(out.split('\n').first, startsWith('Preset: fastapi (detected: '));
  });

  test(
    'json and sarif keep stdout a document; the preset goes to stderr',
    () async {
      for (final format in ['json', 'sarif']) {
        final (_, out, err) = await lint([fixture, '--format', format]);
        expect(() => jsonDecode(out), returnsNormally, reason: format);
        expect(err, startsWith('Preset: '), reason: format);
      }
    },
  );

  test('github-actions prints one annotation per finding', () async {
    final (_, out, _) = await lint([fixture, '--format', 'github-actions']);
    expect(
      out.split('\n').where((line) => line.startsWith('::')),
      hasLength(15),
    );
  });

  test('a spec that cannot be read exits 1 and says how to fix it', () async {
    final (code, out, _) = await lint(['missing.yaml']);
    expect(code, 1);
    expect(out, contains('Check the path of the spec file.'));
  });

  test(
    'anything but one spec path and a known option is a usage error',
    () async {
      for (final args in [
        <String>[],
        [fixture, fixture],
        [fixture, '--preset', 'nope'],
        [fixture, '--format', 'xml'],
        [fixture, '--fail-on', 'info'],
      ]) {
        expect((await lint(args)).$1, 64, reason: '$args');
      }
    },
  );
}
