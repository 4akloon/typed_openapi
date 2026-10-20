import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('every rule that offers an override gives a backend fix too', () {
    final offending = <String>[];
    for (final file in Directory('lib/src/normalize/rules').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      final offersOverride = source.split('\n').any((line) {
        final text = line.trim();
        return !text.startsWith('//') &&
            !text.startsWith('@override') &&
            text.replaceAll('@override', '').toLowerCase().contains('override');
      });
      if (offersOverride && !source.contains('backendFix:')) {
        offending.add(file.path);
      }
    }
    expect(offending, isEmpty);
  });
}
