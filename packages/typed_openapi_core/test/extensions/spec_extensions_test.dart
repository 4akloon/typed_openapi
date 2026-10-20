import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/extensions/spec_extensions.dart';

void main() {
  test('every extension key starts with x- and is listed once', () {
    final keys = [for (final e in SpecExtensions.all) e.key];
    expect(keys, [
      'x-enum-varnames',
      'x-enum-descriptions',
      'x-typed-tri-state',
    ]);
    expect(keys.toSet(), hasLength(keys.length));
  });

  test('the enum-varnames diagnostics are every code the key can raise', () {
    expect(SpecExtensions.enumVarnames.diagnostics, [
      DiagnosticCode.enumVarnamesInvalid,
      DiagnosticCode.nameUnrepresentable,
      DiagnosticCode.nameReserved,
      DiagnosticCode.nameCollision,
      DiagnosticCode.nameLossy,
    ]);
  });

  test('every extension says what it does and shows an example', () {
    for (final extension in SpecExtensions.all) {
      expect(extension.appliesTo, isNotEmpty, reason: extension.key);
      expect(extension.effect, endsWith('.'), reason: extension.key);
      expect(extension.example, contains(extension.key));
    }
  });

  test('lib/ writes an x- key only in the registry', () {
    final writers = <String>[];
    final literal = RegExp(r'(?<![\w/])x-[A-Za-z]');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('extensions/spec_extensions.dart')) continue;
      if (path.contains('/load/yaml/')) continue;
      final code = file.readAsLinesSync().where(
        (line) => !line.trimLeft().startsWith('//'),
      );
      if (code.any(literal.hasMatch)) writers.add(path);
    }
    expect(writers, isEmpty, reason: 'use SpecExtensions.<name>.key');
  });
}
