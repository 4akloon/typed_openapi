import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';
import 'package:typed_openapi_core/src/ir/ir_json.dart';
import 'package:typed_openapi_core/src/ir/names.dart';
import 'package:typed_openapi_core/src/ir/schema_mapper.dart';
import 'package:typed_openapi_core/src/load/openapi_version.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';

import '../helpers/ir_fixture.dart';

/// A spec text with the text of its overrides file, if it has one.
typedef ProbeCase = ({String name, String spec, String? overrides});

/// The configurations every spec is built with.
const configs = [
  GenerationConfig(),
  GenerationConfig(groupBy: GroupBy.path, triState: TriStateRule.optional),
  GenerationConfig(groupBy: GroupBy.single, triState: TriStateRule.extension),
];

/// The cases of the probe files: `#--- name` starts a case and
/// `#OVERRIDES` starts the text of its overrides file.
List<ProbeCase> probeCases() {
  final cases = <ProbeCase>[];
  final files =
      Directory('test/ir/probes')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    for (final part in file.readAsStringSync().split(
      RegExp('^#--- ', multiLine: true),
    )) {
      if (part.trim().isEmpty) continue;
      final newline = part.indexOf('\n');
      final name =
          '${file.uri.pathSegments.last}: ${part.substring(0, newline)}';
      final body = part
          .substring(newline + 1)
          .split(RegExp('^#OVERRIDES\n', multiLine: true));
      cases.add((
        name: name,
        spec: body.first,
        overrides: body.length > 1 ? body[1] : null,
      ));
    }
  }
  return cases;
}

/// The specs written as `'''openapi: ...'''` strings in the tests of the
/// package, which is every OpenAPI fixture the tests have.
///
/// It scans the spec literals of this package's tests only; those of the
/// generator's tests are covered by those tests.
List<ProbeCase> sourceCases() {
  final cases = <ProbeCase>[];
  final string = RegExp(r"(r?)'''([\s\S]*?)'''");
  final files =
      Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('_test.dart') &&
                // Its own doc comment shows the pattern.
                !f.path.endsWith('ir_robustness_test.dart'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final source = file.readAsStringSync();
    for (final (index, match) in string.allMatches(source).indexed) {
      var text = match[2]!;
      if (!text.trimLeft().startsWith('openapi:')) continue;
      if (match[1]!.isEmpty) {
        // An interpolated string is not a fixture on its own.
        if (RegExp(r'(?<!\\)\$[{A-Za-z_]').hasMatch(text)) continue;
        text = text.replaceAll(r'\$', r'$');
      }
      cases.add((name: '${file.path} #$index', spec: text, overrides: null));
    }
  }
  return cases;
}

/// Builds the IR of [probe] with [generation], then maps every schema of
/// the spec with a mapper of its own in both key orders; the JSON of all of
/// it, or null when the spec does not load.
String? buildAll(ProbeCase probe, GenerationConfig generation) {
  final scratch = DiagnosticBag();
  final document = SpecLoader(scratch).parse(probe.spec, 'api.yaml');
  if (document == null ||
      OpenApiVersionDetector(scratch).detect(document) == null) {
    return null;
  }
  const json = IrJson(_fileOf);
  final fixture = IrFixture(
    probe.spec,
    generation: generation,
    overrides: probe.overrides,
  );
  final out = StringBuffer(
    json.encode(
      IrBuilder(
        fixture.diagnostics,
      ).build(fixture.context.spec, fixture.context.client),
    ),
  );
  final keys =
      fixture.context.model.document.components?.schemas.keys.toList() ??
      const [];
  for (final order in [keys, keys.reversed.toList()]) {
    final again = IrFixture(
      probe.spec,
      generation: generation,
      overrides: probe.overrides,
    );
    final mapper = SchemaMapper(again.context);
    final schemas =
        again.context.model.document.components?.schemas ?? const {};
    for (final key in order) {
      mapper.typeOfComponent(schemas[key]!);
    }
    final scope = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.builtInIdentifiers,
        ...DartNames.takenTypeNames,
      },
      reservedSuffix: 'Model',
    );
    out.write(
      json.encode(
        ClientIr(declarations: mapper.declarations(scope), groups: []),
      ),
    );
  }
  return out.toString();
}

String _fileOf(Uri document) => 'api.yaml';

void main() {
  final probes = probeCases();
  final fixtures = sourceCases();

  // The extraction finds 134 probes and 150 fixtures. The floors are 80% of
  // that, so a few fixtures can move or go without failing this test, while
  // an extraction that stops finding the files does fail it.
  test('has probes and fixtures to build', () {
    expect(probes.length, greaterThanOrEqualTo(107));
    expect(fixtures.length, greaterThanOrEqualTo(120));
  });

  for (final (label, cases) in [('probe', probes), ('fixture', fixtures)]) {
    test('builds the IR of every $label spec without throwing, the same '
        'twice', () {
      var built = 0;
      for (final probe in cases) {
        for (final generation in configs) {
          String? first;
          try {
            first = buildAll(probe, generation);
          } on Object catch (error, stack) {
            fail('${probe.name} threw $error\n$stack');
          }
          if (first == null) continue;
          built++;
          expect(
            buildAll(probe, generation),
            first,
            reason: '${probe.name} is not deterministic',
          );
        }
      }
      // Every spec is valid enough to load, and is built in every config.
      expect(built, cases.length * configs.length);
    });
  }
}
