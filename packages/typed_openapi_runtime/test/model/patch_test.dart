import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

/// A PATCH body the way generated code writes one.
final class UpdatePet {
  const UpdatePet({this.name, this.tag, this.nickname});

  final Patch<String>? name;
  final Patch<String>? tag;
  final String? nickname;

  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
    'nickname': ?nickname,
  };
}

void main() {
  test('three states reach JSON', () {
    expect(jsonEncode(const UpdatePet().toJson()), '{}');
    expect(
      jsonEncode(
        const UpdatePet(name: .value('Rex'), tag: .nullValue()).toJson(),
      ),
      '{"name":"Rex","tag":null}',
    );
    expect(
      jsonEncode(const UpdatePet(nickname: 'R').toJson()),
      '{"nickname":"R"}',
    );
  });

  test('value semantics and an exhaustive switch', () {
    const Patch<int> a = .value(1);
    expect(a, const Patch.value(1));
    expect(a, isNot(const Patch.value(2)));
    expect(const Patch<int>.nullValue(), const PatchNull<int>());
    // Equality ignores the type argument, in both directions.
    const Patch<num> wide = .value(1);
    expect(wide == a, isTrue);
    expect(a == wide, isTrue);
    expect(wide.hashCode, a.hashCode);
    expect(
      const Patch<num>.nullValue() == const Patch<int>.nullValue(),
      isTrue,
    );
    expect(
      const Patch<int>.nullValue() == const Patch<num>.nullValue(),
      isTrue,
    );
    expect(const Patch<num>.nullValue() == wide, isFalse);
    expect(wide == const Patch<num>.nullValue(), isFalse);
    expect(a.hashCode, const PatchValue(1).hashCode);
    expect(a.valueOrNull, 1);
    expect(const Patch<int>.nullValue().valueOrNull, isNull);
    expect(a.toString(), 'Patch.value(1)');
    expect(const Patch<int>.nullValue().toString(), 'Patch.nullValue()');
    String describe(Patch<int>? p) => switch (p) {
      null => 'absent',
      PatchNull() => 'null',
      PatchValue(:final value) => 'value $value',
    };
    expect([null, const Patch<int>.nullValue(), a].map(describe), [
      'absent',
      'null',
      'value 1',
    ]);
  });
}
