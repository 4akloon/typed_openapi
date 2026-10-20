@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart' show Preset;
import 'package:typed_openapi_tool/src/corpus/corpus_list_reader.dart';

void main() {
  const recipes = <Preset, String>{
    .nestjs: 'nestjs.md',
    .fastapi: 'fastapi.md',
    .springdoc: 'spring.md',
    .aspnet: 'aspnet.md',
  };
  final codePattern = RegExp(r'TOA\d{3}');

  String recipe(Preset preset) => File(
    '../typed_openapi/doc/frameworks/${recipes[preset]}',
  ).readAsStringSync();

  test('every code that fires on a framework spec is in its recipe', () {
    final specs = const CorpusListReader().read(
      File('corpus.yaml').readAsStringSync(),
    );
    final lock =
        jsonDecode(File('corpus.lock').readAsStringSync())
            as Map<String, Object?>;
    final clients = lock['clients']! as Map<String, Object?>;
    final missing = <String>[];
    for (final spec in specs) {
      if (spec.framework == Preset.generic) continue;
      final inRecipe = codePattern
          .allMatches(recipe(spec.framework))
          .map((m) => m.group(0))
          .toSet();
      final client = clients['raw/${spec.name}'] as Map<String, Object?>?;
      final codes = (client?['diagnostics'] as Map<String, Object?>?) ?? {};
      for (final code in codes.keys) {
        if (!inRecipe.contains(code)) missing.add('${spec.name}: $code');
      }
    }
    expect(missing, isEmpty, reason: 'name each code in the recipe');
  });

  test('every recipe has Sources with links and the date they were read', () {
    for (final preset in recipes.keys) {
      final parts = recipe(preset).split('\n## Sources\n');
      expect(parts, hasLength(2), reason: recipes[preset]);
      final section = parts[1].split('\n## ').first;
      expect(
        'https://'.allMatches(section).length,
        greaterThanOrEqualTo(3),
        reason: recipes[preset],
      );
      expect(section, contains('Checked on 20'), reason: recipes[preset]);
      expect(section, contains('Versions:'), reason: recipes[preset]);
    }
  });

  test('the aspnet and nestjs hints no longer carry the old advice', () {
    expect(
      recipe(.aspnet),
      isNot(contains('[JsonPolymorphic] on an abstract')),
    );
    expect(
      recipe(.nestjs),
      isNot(contains('keep the document at OpenAPI 3.0')),
    );
  });
}
