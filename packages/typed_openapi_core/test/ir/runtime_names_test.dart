import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_core/src/ir/names.dart';

void main() {
  test('every type the runtime exports is a name a schema cannot take', () {
    final barrel = File(
      p.join(
        '..',
        'typed_openapi_client',
        'lib',
        'typed_openapi_client.dart',
      ),
    ).readAsStringSync();
    final exported = {
      for (final block in RegExp(r'show\s+([^;]+);').allMatches(barrel))
        for (final name in block.group(1)!.split(','))
          if (name.trim() case final name when name.isNotEmpty) name,
    };
    expect(exported, isNotEmpty);
    final types = exported.where((n) => RegExp('^[A-Z]').hasMatch(n));
    expect(
      [
        for (final name in types)
          if (!DartNames.takenTypeNames.contains(name)) name,
      ],
      isEmpty,
      reason: 'add each to DartNames.takenTypeNames',
    );
  });
}
