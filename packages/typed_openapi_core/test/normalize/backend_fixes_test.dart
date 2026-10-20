import 'dart:io';

import 'package:test/test.dart';

void main() {
  /// The text of a call from just after its opening parenthesis to the
  /// closing one; parentheses in strings are balanced in these rules.
  String callBody(String rest) {
    var depth = 1;
    for (var i = 0; i < rest.length; i++) {
      if (rest[i] == '(') depth++;
      if (rest[i] == ')' && --depth == 0) return rest.substring(0, i);
    }
    return rest;
  }

  test('every finding that offers an override gives a backend fix too', () {
    final offending = <String>[];
    for (final file in Directory('lib/src/normalize/rules').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final calls = file.readAsStringSync().split('.finding(').skip(1);
      for (final (index, call) in calls.indexed) {
        final code = callBody(call);
        final offersOverride = code.toLowerCase().contains('override');
        if (offersOverride && !code.contains('backendFix:')) {
          offending.add('${file.path} finding ${index + 1}');
        }
      }
    }
    expect(offending, isEmpty);
  });
}
