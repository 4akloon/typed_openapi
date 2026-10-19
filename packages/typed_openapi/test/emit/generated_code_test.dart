@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/dart_process.dart';
import '../helpers/emit_fixture.dart';
import '../helpers/temp_dir.dart';

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
        p.absolute(p.join('..', 'typed_openapi_client')),
      );
      temp
        ..write('pubspec.yaml', '''
name: fixture
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  typed_openapi_client:
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
        ..write('bin/extend.dart', _extendProgram)
        ..write('bin/hierarchy.dart', _hierarchyProgram)
        ..write('bin/secrets_raw.dart', _secretsProgram('raw'))
        ..write('bin/secrets_structural.dart', _secretsProgram('structural'))
        ..write('bin/raw_secrets_raw.dart', _rawSecretsProgram('raw'))
        ..write(
          'bin/raw_secrets_structural.dart',
          _rawSecretsProgram('structural'),
        );
      for (final fixture in [
        'pets',
        'everything',
        'hostile',
        'secrets',
        'secrets_raw',
        'hierarchy',
        'nullable_variants',
        'discriminator_array',
        'optional_constant',
      ]) {
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
      final get = DartProcess.run(['pub', 'get', '--offline'], package);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    });

    test('passes dart analyze with the recommended lints (R13.2)', () {
      final result = DartProcess.run(['analyze', '--fatal-infos'], package);
      expect(result.exitCode, 0, reason: '${result.stdout}');
    });

    test('decodes and encodes JSON (R15.3)', () {
      final result = DartProcess.run(['run', 'bin/decode.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _decoded);
    });

    test('a nested base writes the discriminator of every level', () {
      final result = DartProcess.run(['run', 'bin/hierarchy.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, 'ok\n');
    });

    for (final mode in ['raw', 'structural']) {
      test('a secret is never printed ($mode)', () {
        final result = DartProcess.run([
          'run',
          'bin/secrets_$mode.dart',
        ], package);
        expect(result.stderr, '');
        expect(result.stdout, 'ok\n');
      });
      test('a secret in raw JSON is never printed ($mode)', () {
        final result = DartProcess.run([
          'run',
          'bin/raw_secrets_$mode.dart',
        ], package);
        expect(result.stderr, '');
        expect(result.stdout, 'ok\n');
      });
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Pet -> Dog -> Lab, where no model declares a discriminator property: every
/// level writes its own, and what was decoded is what is encoded.
const _hierarchyProgram = r'''
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:fixture/hierarchy_raw/models.dart';

final failures = <String>[];

void check(String name, bool ok) {
  if (!ok) failures.add(name);
}

Object? json(Object? value) => jsonDecode(jsonEncode(value));

void main() {
  const dog = {
    'petType': 'dog',
    'breed': 'pup',
    'name': 'a',
    'weight': 2,
    'color': 'brown',
  };
  final decoded = Pet.fromJson(dog);
  check('decodes the first level', decoded is PetDog);
  check('decodes the second level', (decoded as PetDog).value is DogLab);
  check('decode then encode keeps every key', _sameMap(json(decoded.toJson()), dog));
  check('writes petType', (json(decoded.toJson()) as Map)['petType'] == 'dog');
  check('writes the alias breed', (json(decoded.toJson()) as Map)['breed'] == 'pup');

  const stray = {'petType': 'dog', 'breed': 'zzz', 'name': 'x'};
  final unknown = Pet.fromJson(stray);
  check('a nested unknown value is kept', unknown is PetDog && unknown.value is DogUnknown);
  check('and written as received', _sameMap(json(unknown.toJson()), stray));

  final made = PetDog(DogLab(const Lab(name: 'a', weight: 2, color: 'brown')));
  final again = Pet.fromJson(json(made.toJson()));
  check('a wrapper made in code decodes as PetDog', again is PetDog);
  check('and its value as DogLab', again is PetDog && again.value is DogLab);
  check('and is equal to it', again == made);
  check('with the same hash code', again.hashCode == made.hashCode);
  check('a decoded alias differs from the first value', decoded != made);

  const lab = Lab(name: 'b');
  final direct = PetLab(lab);
  final directAgain = Pet.fromJson(json(direct.toJson()));
  check('a wrapper of the last level round trips', directAgain == direct);

  const cat = Cat(name: 'c', lives: 9);
  final madeCat = PetCat(cat);
  final decodedCat = Pet.fromJson(json(madeCat.toJson()));
  check('PetCat(c) == Pet.fromJson(PetCat(c).toJson())', decodedCat == madeCat);
  check('and the hash codes agree', decodedCat.hashCode == madeCat.hashCode);
  final kitty = Pet.fromJson({'petType': 'kitty', 'name': 'k'});
  check('an alias is written back', (json(kitty.toJson()) as Map)['petType'] == 'kitty');
  check('and is not equal to the first value', kitty != PetCat(const Cat(name: 'k')));

  print(failures.isEmpty ? 'ok' : failures.join('\n'));
}

bool _sameMap(Object? a, Map<String, Object?> b) =>
    a is Map && a.length == b.length && b.entries.every((e) => a[e.key] == e.value);
''';

/// A secret is printed as `<redacted>` wherever the schema puts it.
String _secretsProgram(String mode) =>
    '''
// ignore_for_file: avoid_print
import 'package:fixture/secrets_$mode/models.dart';

final failures = <String>[];

void check(String name, String printed, String secret) {
  if (printed.contains(secret)) failures.add('\$name prints \$secret');
}

void main() {
  final login = Login(
    name: 'public',
    plain: 'S-plain',
    written: 'S-written',
    anyOfNull: 'S-anyOfNull',
    oneOfNull: 'S-oneOfNull',
    refTarget: 'S-refTarget',
    refNullable: 'S-refNullable',
    annotated: 'S-annotated',
    tokens: ['S-tokens'],
    tokenRefs: ['S-tokenRefs'],
    byName: {'k': 'S-byName'},
    cred: const CredString('S-cred'),
    creds: [const CredString('S-creds')],
  );
  final text = login.toString();
  for (final secret in [
    'plain', 'written', 'anyOfNull', 'oneOfNull', 'refTarget', 'refNullable',
    'annotated', 'tokens', 'tokenRefs', 'byName', 'cred', 'creds',
  ]) {
    check(secret, text, 'S-\$secret');
  }
  if (!text.contains('public')) failures.add('a public field is printed');
  check('Extra', const Extra(additionalProperties: {'a': 'S-extra'}).toString(), 'S-extra');
  check('CredString', const CredString('S-variant').toString(), 'S-variant');
  check('CredUnknown', Cred.fromJson(true).toString(), 'true');
  print(failures.isEmpty ? 'ok' : failures.join('\\n'));
}
''';

/// A value that stays raw JSON (`JsonValue`, the unknown variant of a union)
/// holds the properties of models that have a secret.
String _rawSecretsProgram(String mode) =>
    '''
// ignore_for_file: avoid_print
import 'package:fixture/secrets_raw_$mode/models.dart';
final failures = <String>[];

void check(String name, Object value, String secret) {
  if (value.toString().contains(secret)) failures.add('\$name prints \$secret');
}

void main() {
  const login = {'kind': 'sso', 'user': 'u', 'password': 'S-raw'};
  check('Tagged', Tagged.fromJson(login), 'S-raw');
  ${mode == 'raw' ? '''
  final session = Session.fromJson({
    'auth': login,
    'auths': [login],
    'byKey': {'k': login},
    'mixed': login,
    'extra': login,
  });
  check('Session', session, 'S-raw');
  ''' : '''
  check('Auth', Auth.fromJson(const {'user': 'u', 'password': 'S-auth'}), 'S-auth');
  check('Auth unknown', Auth.fromJson(const {'password': 'S-unknown'}), 'S-unknown');
  check('Mixed', Mixed.fromJson(login), 'S-raw');
  if (!Node.fromJson(true).toString().contains('true')) {
    failures.add('the unknown variant of a union with no secret is redacted');
  }
  '''}
  print(failures.isEmpty ? 'ok' : failures.join('\\n'));
}
''';

/// Classes of another library extend generated ones, and a switch over a
/// sealed base is still exhaustive.
const _extendProgram = '''
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
import 'package:typed_openapi_client/typed_openapi_client.dart';

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
