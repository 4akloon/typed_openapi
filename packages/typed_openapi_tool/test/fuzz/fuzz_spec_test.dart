import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_spec.dart';
import 'package:typed_openapi_tool/src/fuzz/hostile.dart';

void main() {
  test('a spec has an API key, an OAuth 2 and an HTTP scheme', () {
    var complete = 0;
    for (var seed = 0; seed < 20; seed++) {
      final spec = jsonDecode(const FuzzSpec().of(seed).spec) as Map;
      final schemes = (spec['components'] as Map)['securitySchemes'] as Map;
      final types = {for (final s in schemes.values) (s as Map)['type']};
      // Two hostile names can be equal, and then one scheme replaces another.
      if (schemes.length == 3) {
        expect(types, {'apiKey', 'oauth2', 'http'}, reason: 'seed $seed');
        complete++;
      }
    }
    expect(complete, greaterThan(10));
  });

  test('a requirement names a hostile scope, never an empty list', () {
    for (var seed = 0; seed < 20; seed++) {
      final spec = jsonDecode(const FuzzSpec().of(seed).spec) as Map;
      for (final requirement in spec['security'] as List) {
        for (final scopes in (requirement as Map).values) {
          expect(scopes, hasLength(1));
          expect(Hostile.names, contains((scopes as List).single));
        }
      }
    }
  });
}
