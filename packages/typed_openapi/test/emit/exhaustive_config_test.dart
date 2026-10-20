@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/model_library.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/emit_fixture.dart';

void main() {
  const open = GenerationConfig(exhaustive: false);

  test('exhaustive: false makes enums and unions interfaces', () {
    final files = emitClient('pets.yaml', generation: open);
    expect(
      files['models/status.dart'],
      contains('abstract interface class Status {'),
    );
    expect(
      files['models/pet.dart'],
      contains('abstract interface class Pet {'),
    );
  });

  test('exhaustive: false makes status types interfaces', () {
    final api = emitClient(
      'petstore.yaml',
      generation: open,
    )['api/pets_api.dart']!;
    expect(api, contains('abstract interface class CreatePetResponse {'));
    expect(api, contains('abstract interface class CreatePetError {'));
    expect(api, contains('by status: a `switch` needs a default'));
    expect(api, isNot(contains('sealed class')));
  });

  test('exhaustive: false makes event unions interfaces', () {
    final api = emitClient(
      'chat.yaml',
      generation: open,
    )['api/chat_api.dart']!;
    expect(api, contains('abstract interface class FollowChatEvent {'));
    expect(api, contains('by their event name: a `switch` needs a\n'));
  });

  test('a schema override exhaustive: true wins over the config', () {
    final fixture = NormalizedFixture(
      r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /x:
    get:
      operationId: getX
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
                  color: {$ref: '#/components/schemas/Color'}
                  size: {$ref: '#/components/schemas/Size'}
components:
  schemas:
    Color: {type: string, enum: [red]}
    Size: {type: string, enum: [small]}
''',
      generation: open,
      overrides: 'schemas:\n  Color: {exhaustive: true}\n',
    );
    final files = const ModelLibrary().files(fixture.build());
    expect(files['models/color.dart'], contains('sealed class Color {'));
    expect(
      files['models/size.dart'],
      contains('abstract interface class Size {'),
    );
  });
}
