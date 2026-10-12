@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/emit/model_library.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/temp_dir.dart';

/// The model files of the fixture spec [name] in `test/emit/fixtures`.
Map<String, String> emitFixture(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
}) {
  final fixture = IrFixture(
    File(p.join('test', 'emit', 'fixtures', name)).readAsStringSync(),
    generation: generation,
  );
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return const ModelLibrary().files(ir);
}

/// Runs `dart` with [arguments] in [directory].
ProcessResult dart(List<String> arguments, String directory) => Process.runSync(
  Platform.resolvedExecutable,
  arguments,
  workingDirectory: directory,
);

void main() {
  test('strings from the spec cannot leave their literal or comment', () {
    for (final mode in UnionMode.values) {
      final files = emitFixture(
        'hostile.yaml',
        generation: GenerationConfig(union: mode),
      );
      for (final MapEntry(:key, :value) in files.entries) {
        final lines = value.split('\n');
        for (final line in lines) {
          final code = line.trimLeft();
          expect(
            code.startsWith('injected') || code.startsWith('void injected'),
            isFalse,
            reason: '$key: $line',
          );
          expect(line, isNot(contains('\r')), reason: key);
          if (!code.startsWith('///') && !code.startsWith('//')) {
            expect(code, isNot(startsWith('/*')), reason: '$key: $line');
          }
        }
        expect(
          value,
          isNot(matches(RegExp('[\u202a-\u202e\u2066-\u2069\u2028\u2029]'))),
          reason: key,
        );
      }
    }
  });

  test('the pets fixture matches its goldens (R15.3)', () {
    final files = emitFixture('pets.yaml');
    final goldens = p.join('test', 'emit', 'goldens', 'pets');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      for (final MapEntry(:key, :value) in files.entries) {
        File(p.join(goldens, '$key.golden'))
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
    }
    final expected = {
      for (final file in Directory(
        goldens,
      ).listSync(recursive: true).whereType<File>())
        p
            .relative(file.path, from: goldens)
            .replaceAll(r'\', '/')
            .replaceAll(RegExp(r'\.golden$'), ''): file
            .readAsStringSync(),
    };
    expect(files.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in files.entries) {
      expect(value, expected[key], reason: key);
    }
  });

  group('a package of generated code', () {
    late String package;

    setUpAll(() {
      final temp = TempDir();
      package = temp.path;
      final runtime = p.normalize(
        p.absolute(p.join('..', 'typed_openapi_runtime')),
      );
      temp
        ..write('pubspec.yaml', '''
name: fixture
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  typed_openapi_runtime:
    path: ${runtime.replaceAll(r'\', '/')}
dev_dependencies:
  lints: ^6.1.0
''')
        // package:lints/recommended and the rules flutter_lints adds.
        ..write('analysis_options.yaml', '''
include: package:lints/recommended.yaml
linter:
  rules:
    - avoid_print
    - avoid_unnecessary_containers
    - avoid_web_libraries_in_flutter
    - no_logic_in_create_state
    - prefer_const_constructors_in_immutables
    - sized_box_for_whitespace
    - sort_child_properties_last
    - use_build_context_synchronously
    - use_full_hex_values_for_flutter_colors
    - use_key_in_widget_constructors
''')
        ..write('bin/decode.dart', _decodeProgram)
        ..write('bin/extend.dart', _extendProgram);
      for (final fixture in ['pets', 'everything', 'hostile']) {
        for (final mode in UnionMode.values) {
          final files = emitFixture(
            '$fixture.yaml',
            generation: GenerationConfig(union: mode),
          );
          for (final MapEntry(:key, :value) in files.entries) {
            temp.write(p.join('lib', '${fixture}_${mode.name}', key), value);
          }
        }
      }
      final get = dart(['pub', 'get', '--offline'], package);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    });

    test('passes dart analyze with the recommended lints (R13.2)', () {
      final result = dart(['analyze', '--fatal-infos'], package);
      expect(result.exitCode, 0, reason: '${result.stdout}');
    });

    test('decodes and encodes JSON (R15.3)', () {
      final result = dart(['run', 'bin/decode.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _decoded);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Classes of another library extend generated ones, and a switch over a
/// sealed base is still exhaustive.
const _extendProgram = r'''
import 'package:fixture/pets_raw/models.dart';

class MyCat extends PetCat {
  const MyCat(super.value);
}

class BigCat extends Cat {
  const BigCat() : super(lives: 9);
}

class Tagged implements StatusUnknown {
  @override
  String toJson() => 'tagged';

  @override
  String get value => 'tagged';
}

String describe(Pet pet) => switch (pet) {
  PetCat() => 'cat',
  PetDog() => 'dog',
  PetUnknown() => 'unknown',
};

String status(Status status) => switch (status) {
  StatusKnown() => 'known',
  StatusUnknown() => 'unknown',
};

void main() {
  describe(const MyCat(BigCat()));
  status(Tagged());
}
''';

const _decodeProgram = r'''
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:fixture/pets_raw/models.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  const text = """
{"id": "o-1", "status": "away", "birthday": "2020-02-29",
 "pets": [
   {"kind": "cat", "lives": 7, "bornAt": "2024-01-02T03:04:05+02:00"},
   {"kind": "dog", "bark": false, "photo": "AQID"},
   {"kind": "puppy", "bark": true},
   {"kind": "fish", "fins": 2}
 ],
 "score": 10}
""";
  final owner = Owner.fromJson(jsonDecode(text) as Map<String, Object?>);
  print(jsonEncode(owner.toJson()));
  print(owner.id is IdOrNameString);
  print(owner.status is StatusUnknown);
  final pets = owner.pets!;
  print([for (final pet in pets) pet.runtimeType].join(', '));
  print(jsonEncode(const PetDog(Dog(bark: true)).toJson()));
  print(Owner(id: const IdOrNameInt(5), secret: 's3cret'));
  print(owner == Owner.fromJson(jsonDecode(text) as Map<String, Object?>));
  print(owner.hashCode == Owner.fromJson(jsonDecode(text) as Map<String, Object?>).hashCode);
  print(jsonEncode(Owner(id: const IdOrNameInt(5), status: Status.active).toJson()));
  print(Owner.fromJson({'id': true}).id);
  for (final bad in ['{}', '{"id": 1, "status": 1}', '{"id": 1, "pets": [{"kind": "cat"}]}', '{"id": 1, "score": "x"}']) {
    try {
      Owner.fromJson(jsonDecode(bad) as Map<String, Object?>);
    } on JsonDecodeException catch (e) {
      print('${e.pointer} ${e.schema} ${e.message}');
    }
  }
  print(jsonEncode(const PatchOwnerRequest(name: Patch.nullValue()).toJson()));
  print(jsonEncode(const PatchOwnerRequest(meta: Patch.value(JsonValue([1]))).toJson()));
  print(jsonEncode(const PatchOwnerRequest().toJson()));
}
''';

const _decoded = '''
{"id":"o-1","status":"away","birthday":"2020-02-29","pets":[{"kind":"cat","lives":7,"bornAt":"2024-01-02T01:04:05.000Z"},{"bark":false,"photo":"AQID","kind":"dog"},{"bark":true,"kind":"puppy"},{"kind":"fish","fins":2}],"score":10}
true
true
PetCat, PetDog, PetDog, PetUnknown
{"bark":true,"kind":"dog"}
Owner(id: IdOrNameInt(5), status: null, birthday: null, pets: null, secret: <redacted>, additionalProperties: {})
true
true
{"id":5,"status":"active"}
IdOrNameUnknown(true)
/id Owner expected a required property, got no value
/status Owner expected a string, got a number
/pets/0/lives Cat expected a required property, got no value
/score Owner expected an integer, got a string
{"name":null}
{"meta":[1]}
{}
''';
