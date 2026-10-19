@TestOn('vm')
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

// The literals below do not compile to JavaScript (they are not exactly
// representable), so this file runs on the VM only.
const int maxInt64 = 9223372036854775807;
const int minInt64 = -9223372036854775808;

void main() {
  JsonDecodeException failure(void Function() body) {
    try {
      body();
    } on JsonDecodeException catch (e) {
      return e;
    }
    fail('expected a JsonDecodeException');
  }

  test('the int64 boundary: 2^63 - 1 is an int, 2^63 is not', () {
    expect(JsonReader.asInt(jsonDecode('9223372036854775807')), maxInt64);
    expect(JsonReader.asInt(jsonDecode('-9223372036854775808')), minInt64);
    expect(
      failure(
        () => JsonReader.asInt(jsonDecode('9223372036854775808')),
      ).expected,
      'an integer',
    );
    expect(
      failure(
        () => JsonReader.asInt(jsonDecode('-9223372036854775809')),
      ).expected,
      'an integer',
    );
  });
}
