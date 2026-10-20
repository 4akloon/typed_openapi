@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diff/api_change.dart';
import 'package:typed_openapi_core/src/diff/api_diff.dart';
import 'package:typed_openapi_core/src/diff/fact_changes.dart';
import 'package:typed_openapi_core/src/snapshot/api_snapshot.dart';

import '../helpers/snapshot_fixture.dart';

/// A spec with the schemas [schemas] and the operation `getPet`.
String spec(String schemas, {String parameters = ''}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}:
    get:
      operationId: getPet
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer}}
$parameters
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {\$ref: '#/components/schemas/Pet'}
components:
  schemas:
$schemas''';

const pet = r'''
    Pet:
      type: object
      required: [name]
      properties:
        name: {type: string}
        status: {$ref: '#/components/schemas/Status'}
    Status: {type: string, enum: [available, sold]}
''';

List<ApiChange> diff(
  String before,
  String after, {
  GenerationConfig generation = const GenerationConfig(),
}) => const ApiDiff().compare(
  snapshotOf(before, generation: generation),
  snapshotOf(after, generation: generation),
);

void main() {
  test('the same spec has no change', () {
    expect(diff(spec(pet), spec(pet)), isEmpty);
  });

  test('a new enum value breaks only an exhaustive switch', () {
    final after = spec(pet.replaceFirst('sold]', 'sold, pending]'));
    final changes = diff(spec(pet), after);
    expect(changes.single.category, ChangeCategory.switchBreaking);
    expect(changes.single.message, 'Enum value Status.pending was added.');
  });

  test('with exhaustive: false a new enum value is additive', () {
    final changes = diff(
      spec(pet),
      spec(pet.replaceFirst('sold]', 'sold, pending]')),
      generation: const GenerationConfig(exhaustive: false),
    );
    expect(changes.single.category, ChangeCategory.additive);
  });

  test('a new optional query parameter is additive', () {
    final changes = diff(
      spec(pet),
      spec(
        pet,
        parameters: '        - {name: q, in: query, schema: {type: string}}',
      ),
    );
    expect(changes.single.category, ChangeCategory.additive);
    expect(changes.single.message, 'Argument DefaultApi.getPet(q) was added.');
  });

  test('a new path is a wire change', () {
    final changes = diff(
      spec(pet),
      spec(pet).replaceFirst('/pets/{id}:', '/animals/{id}:'),
    );
    expect(changes.single.category, ChangeCategory.wire);
    expect(
      changes.single.message,
      'Method DefaultApi.getPet: path changed from /pets/{id} to /animals/{id}.',
    );
  });

  test('a renamed schema is removed and added, with a name override', () {
    final after = spec(
      pet
          .replaceFirst('    Pet:', '    Animal:')
          .replaceAll("schemas/Pet'", "schemas/Animal'"),
    ).replaceAll("schemas/Pet'", "schemas/Animal'");
    final changes = diff(spec(pet), after);
    final removed = changes.firstWhere((c) => c.message.contains('removed'));
    expect(removed.category, ChangeCategory.breaking);
    expect(removed.message, 'Model Pet was removed.');
    expect(removed.fix, 'schemas:\n  Animal:\n    name: Pet');
    expect(
      changes.any(
        (c) =>
            c.category == ChangeCategory.additive &&
            c.message == 'Model Animal was added.',
      ),
      isTrue,
    );
  });

  test('the table knows every fact the snapshot writes', () {
    final facts = <String>{};
    for (final fixture in [
      'petstore.yaml',
      'pets.yaml',
      'everything.yaml',
      'chat.yaml',
      'wire.yaml',
      'hierarchy.yaml',
    ]) {
      for (final type in snapshotOfFixture(fixture).types.values) {
        facts.addAll(type.facts.keys);
        for (final SnapshotMember(facts: f) in type.members.values) {
          facts.addAll(f.keys);
        }
      }
    }
    expect(
      facts.difference({
        ...FactChanges.breaking,
        ...FactChanges.wire,
        ...FactChanges.docs,
        'required',
      }),
      isEmpty,
    );
  });
}
