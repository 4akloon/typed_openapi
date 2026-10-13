@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/cached_schema.dart';
import '../helpers/temp_dir.dart';

const _json = '{"type": "object"}';

/// A cached schema pinned to the hash of [_json], with [cached] written in
/// the cache (nothing when null) and [environment] as the environment.
CachedSchema schemaWith({
  String? cached,
  Map<String, String> environment = const {},
}) {
  final temp = TempDir();
  final pin = sha256.convert(utf8.encode(_json));
  final corpus = temp.write('corpus.yaml', '''
specs: {}
schemas:
  sarif_schema: {url: https://example.com/s.json, sha256: $pin, license: MIT}
''');
  if (cached != null) temp.write('cache/sarif_schema/s.json', cached);
  return CachedSchema(
    'sarif_schema',
    corpusFile: corpus,
    cacheDirectory: p.join(temp.path, 'cache'),
    environment: environment,
  );
}

void main() {
  test('a missing schema is skipped locally and names corpus fetch', () {
    final schema = schemaWith();
    expect(schema.skipReason, contains('corpus.dart fetch sarif_schema'));
  });

  test('a missing schema fails the test in CI', () {
    final schema = schemaWith(environment: {'CI': 'true'});
    expect(schema.skipReason, isNull);
    expect(schema.problem, contains('not in the cache'));
    expect(schema.load, throwsStateError);
  });

  test('a cached schema with another hash fails, in CI or not', () {
    final schema = schemaWith(cached: '{"type": "array"}');
    expect(schema.skipReason, isNull);
    expect(schema.problem, contains('pins'));
    expect(schema.load, throwsStateError);
  });

  test('the pinned schema loads', () {
    final schema = schemaWith(cached: _json);
    expect(schema.problem, isNull);
    expect(schema.load(), {'type': 'object'});
  });
}
