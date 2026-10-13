import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/emit/model_library.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';

/// The model files of [spec], a spec whose `GET /x` returns `Root`.
Map<String, String> emit(
  String schemas, {
  GenerationConfig generation = const GenerationConfig(),
  String? overrides,
  String paths = '',
}) {
  final fixture = IrFixture(
    '''
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
              schema: {\$ref: '#/components/schemas/Root'}
$paths
components:
  schemas:
$schemas''',
    generation: generation,
    overrides: overrides,
  );
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return const ModelLibrary().files(ir);
}

void main() {
  group('unions that refer to each other do not crash the emitter', () {
    // Fuzz seed 2251: a union dispatched by JSON type whose first variant is
    // a discriminator union that leads back to it (stack overflow).
    const loop = r'''
    Root:
      type: object
      properties: {a: {$ref: '#/components/schemas/A'}}
    A:
      anyOf:
        - $ref: '#/components/schemas/B'
        - {type: string, format: byte}
    B:
      anyOf:
        - $ref: '#/components/schemas/A'
        - {type: array, items: {type: string}}
      discriminator: {propertyName: kind}
''';
    // Fuzz seed 510: the first variant of a nested union is not a model
    // (null check in `_byJsonType`).
    const nested = r'''
    Root:
      type: object
      properties: {a: {$ref: '#/components/schemas/Kinds'}}
    Kinds:
      oneOf:
        - {type: array, items: {type: string}}
        - {type: number}
        - $ref: '#/components/schemas/D'
    D:
      anyOf:
        - $ref: '#/components/schemas/P'
        - {type: string, format: date-time}
      discriminator: {propertyName: kind}
    P:
      oneOf:
        - $ref: '#/components/schemas/Kinds'
        - {type: object, properties: {q: {type: string}}}
''';

    for (final mode in UnionMode.values) {
      test('a loop through a discriminator union (${mode.name})', () {
        final files = emit(loop, generation: GenerationConfig(union: mode));
        final a = files['models/a.dart']!;
        expect(a, contains('final Map<String, Object?> value => AB('));
        expect(a, contains('final String value => ABytes('));
      });

      test('a first variant that is not a model (${mode.name})', () {
        final files = emit(nested, generation: GenerationConfig(union: mode));
        expect(files.keys, contains('models/root.dart'));
        if (mode == UnionMode.raw) {
          expect(
            files['models/kinds.dart']!,
            contains('final Map<String, Object?> value => KindsD('),
          );
        }
      });
    }
  });

  test('a custom type of an object schema is built from a map', () {
    final files = emit(
      r'''
    Root:
      type: object
      properties:
        price: {$ref: '#/components/schemas/Money'}
        cost: {$ref: '#/components/schemas/Cost'}
        kind: {$ref: '#/components/schemas/Kind'}
    Money: {type: object, properties: {amount: {type: integer}}}
    Cost: {type: object, properties: {amount: {type: integer}}}
    Kind: {type: string, enum: [a, b]}
''',
      generation: const GenerationConfig(
        schemas: {
          'Money': DartTypeOverride(
            type: 'Money',
            import: 'package:app/money.dart',
            converter: 'MoneyConverter',
          ),
          'Cost': DartTypeOverride(
            type: 'Cost',
            import: 'package:app/cost.dart',
          ),
          'Kind': DartTypeOverride(
            type: 'Kind',
            import: 'package:app/kind.dart',
          ),
        },
      ),
    );
    final root = files['models/root.dart']!;
    expect(
      root,
      contains('const MoneyConverter().fromJson(JsonReader.asObject('),
    );
    expect(root, contains('Cost.fromJson(JsonReader.asObject('));
    expect(root, contains('Kind.fromJson(JsonReader.asString('));
  });

  test('a request model takes the known values of its extra properties', () {
    final files = emit(
      r'''
    Root: {type: object, properties: {a: {type: string}}}
    Color: {type: string, enum: [red, blue]}
    Body:
      type: object
      properties: {name: {type: string}}
      additionalProperties: {$ref: '#/components/schemas/Color'}
''',
      paths: r'''
  /y:
    post:
      operationId: postY
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/Body'}
      responses:
        '204': {description: ok}
''',
    );
    final body = files['models/body.dart']!;
    expect(
      body,
      contains('Map<String, ColorKnown> this.additionalProperties = const {}'),
    );
    expect(
      body,
      contains(
        'const Body._({this.name, this.additionalProperties = const {}});',
      ),
    );
    expect(body, contains('final Map<String, Color> additionalProperties;'));
  });

  test('a wrapper no discriminator value picks has no private constructor', () {
    final files = emit(r'''
    Root:
      type: object
      properties: {pet: {$ref: '#/components/schemas/Pet'}}
    Cat: {type: object, properties: {lives: {type: integer}}}
    Dog: {type: object, properties: {bark: {type: boolean}}}
    Pet:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
      discriminator:
        propertyName: kind
        mapping: {Cat: Dog}
''');
    final pet = files['models/pet.dart']!;
    // `Cat` is both the implicit value of Cat and the mapped value of Dog:
    // the earlier variant decodes it, so Dog is never picked.
    expect(pet, contains('const PetCat._(this.value, this.discriminator);'));
    expect(pet, isNot(contains('const PetDog._(')));
    expect(pet, contains('const PetDog(this.value) : discriminator = null;'));
  });

  test('classes are not final, so users can extend and implement them', () {
    final files = emit(r'''
    Root:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
        pet: {$ref: '#/components/schemas/Pet'}
        other: {oneOf: [{type: string}, {type: integer}]}
    Cat: {type: object, properties: {kind: {const: cat}}}
    Dog: {type: object, properties: {kind: {const: dog}}}
    Pet:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
      discriminator: {propertyName: kind}
''');
    final text = files.values.join('\n');
    expect(text, isNot(contains('final class')));
    expect(text, contains('\nclass Root {'));
    expect(text, contains('\nclass RootStatusUnknown implements RootStatus {'));
    expect(text, contains('\nclass PetCat implements Pet {'));
    expect(text, contains('\nclass PetUnknown implements Pet {'));
    expect(text, contains('\nsealed class Pet {'));
    expect(text, contains('const PetUnknown._('));
    expect(text, contains('@immutable\nclass'));
  });

  test('writes a file per declaration and the barrel', () {
    final files = emit(r'''
    Root:
      type: object
      properties:
        a: {$ref: '#/components/schemas/UserDTO'}
        b: {$ref: '#/components/schemas/UserDto'}
        c: {$ref: '#/components/schemas/2fa'}
    UserDTO: {type: object, properties: {x: {type: string}}}
    UserDto: {type: object, properties: {y: {type: string}}}
    2fa: {type: string, enum: [on, off]}
''');
    expect(files.keys, [
      'models.dart',
      'models/root.dart',
      'models/type_2_fa.dart',
      'models/user_dto.dart',
      'models/user_dto2.dart',
    ]);
    expect(
      files['models.dart'],
      '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
      '// dart format off\n'
      '\n'
      "export 'models/root.dart';\n"
      "export 'models/type_2_fa.dart';\n"
      "export 'models/user_dto.dart';\n"
      "export 'models/user_dto2.dart';\n",
    );
    expect(
      files['models/root.dart'],
      startsWith(
        '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
        '// dart format off\n'
        '\n'
        "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'\n"
        '    show DeepEquality, JsonReader, immutable;\n'
        '\n'
        "import 'type_2_fa.dart';\n"
        "import 'user_dto.dart';\n"
        "import 'user_dto2.dart';\n",
      ),
    );
  });

  test('writes the same files twice (R13.1)', () {
    const schemas = '''
    Root:
      type: object
      properties:
        e: {type: string, enum: [a, b]}
        u: {oneOf: [{type: string}, {type: integer}]}
''';
    expect(emit(schemas), emit(schemas));
  });

  group('models', () {
    test('read and write every kind of field', () {
      final root = emit('''
    Root:
      type: object
      required: [id, req, json, dates]
      properties:
        id: {type: integer}
        req: {type: [string, 'null']}
        json: {}
        meta: {}
        born: {type: string, format: date-time}
        day: {type: string, format: date}
        photo: {type: string, format: byte}
        list: {type: array, items: {type: [string, 'null'], format: date-time}}
        map: {type: object, additionalProperties: {type: string, format: date}}
        kind: {const: root}
        dates: {type: [array, 'null'], items: {type: string, format: date}}
''')['models/root.dart']!;
      for (final line in [
        "final r = JsonReader(json, schema: 'Root');",
        "[if (!r.constant('kind', 'root', required: false)) 'kind',],",
        "id: r.required('id', JsonReader.asInt),",
        "req: r.requiredNullable('req', JsonReader.asString),",
        "json: r.requiredValue('json'),",
        "meta: r.optionalValue('meta'),",
        "photo: r.optional('photo', JsonReader.asBytes),",
        "list: r.optional('list', JsonReader.listOf("
            'JsonReader.nullable(JsonReader.asDateTime))),',
        "'id': id,",
        "'req': req,",
        "'json': json,",
        "'meta': ?meta.raw,",
        "'born': ?born?.toUtc().toIso8601String(),",
        "'day': ?day?.toJson(),",
        "if (photo case final v?) 'photo': base64Encode(v),",
        "if (list case final v?) 'list': "
            '[for (final e0 in v) e0?.toUtc().toIso8601String()],',
        "'map': ?map?.map((k0, v0) => MapEntry(k0, v0.toJson())),",
        "if (!_absent.contains('kind')) 'kind': 'root',",
        "'dates': switch (dates) {final v? => "
            '[for (final e0 in v) e0.toJson()], null => null},',
        "String get kind => 'root';",
        'this.meta = const JsonValue(null),',
        "import 'dart:convert' show base64Encode;",
        "import 'dart:typed_data' show Uint8List;",
      ]) {
        expect(root, contains(line));
      }
    });

    test('a request model takes only known enum values (R8.2)', () {
      final files = emit(
        r'''
    Root:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
        statuses: {type: array, items: {$ref: '#/components/schemas/Status'}}
    Status: {type: string, enum: [x]}
''',
        paths: r'''
    post:
      operationId: postX
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/Root'}
      responses:
        '204': {description: ok}''',
      );
      final root = files['models/root.dart']!;
      expect(
        root,
        contains(
          'const Root({RootStatusKnown? this.status, '
          'List<StatusKnown>? this.statuses});',
        ),
      );
      expect(root, contains('const Root._({this.status, this.statuses});'));
      expect(root, contains('return Root._('));
      expect(root, contains('final RootStatus? status;'));
    });

    test('a response model takes any enum value', () {
      final root = emit('''
    Root:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''')['models/root.dart']!;
      expect(root, contains('const Root({this.status});'));
      expect(root, isNot(contains('Root._(')));
    });

    test('documents constraints, defaults and deprecation (R6.7, R13.4)', () {
      final root = emit(r'''
    Root:
      type: object
      properties:
        name:
          type: string
          description: The <name> of [it].
          minLength: 1
          maxLength: 64
          pattern: '^[a-z]+$'
          default: rex
        age: {type: integer, exclusiveMinimum: 0, maximum: 30, deprecated: true}
''')['models/root.dart']!;
      expect(
        root,
        contains(
          '  /// The \\<name\\> of \\[it\\].\n'
          '  ///\n'
          '  /// 1–64 characters, matches `^[a-z]+\$`.\n'
          '  ///\n'
          '  /// Defaults to `"rex"` on the server.\n'
          '  final String? name;\n',
        ),
      );
      expect(
        root,
        contains(
          '  /// Greater than 0, at most 30.\n'
          "  @Deprecated('Deprecated in the API spec.')\n"
          '  final int? age;\n',
        ),
      );
    });

    test('keep names Dart cannot take apart from the JSON keys', () {
      final root = emit(r'''
    Root:
      type: object
      required: [class, other]
      properties:
        class: {type: string}
        other: {type: string}
        int: {type: integer}
        $dollar: {type: string}
        "ім'я": {type: string}
''')['models/root.dart']!;
      for (final line in [
        "class_: r.required('class', JsonReader.asString),",
        "int_: r.optional('int', JsonReader.asInt),",
        r"dollar: r.optional('\$dollar', JsonReader.asString),",
        r"field: r.optional('ім\'я', JsonReader.asString),",
        'other.other == this.other &&',
      ]) {
        expect(root, contains(line));
      }
      expect(root, contains('final int? int_;'));
      expect(
        root,
        contains(
          r"String toString() => 'Root(class_: $class_, other: $other, "
          r"int_: $int_, dollar: $dollar, field: $field)';",
        ),
      );
    });

    test('an empty model and a model of additional properties only', () {
      final files = emit(
        r'''
    Root:
      type: object
      properties:
        empty: {$ref: '#/components/schemas/Empty'}
        extra:
          type: object
          properties:
            additionalProperties: {type: string}
          additionalProperties: {type: integer}
    Empty: {type: object, properties: {gone: {type: string}}}
''',
        overrides: 'schemas:\n  Empty: {properties: {gone: {exclude: true}}}\n',
      );
      final empty = files['models/empty.dart']!;
      expect(
        empty,
        contains(
          'factory Empty.fromJson(Map<String, Object?> json) => '
          'const Empty();',
        ),
      );
      expect(empty, contains('Map<String, Object?> toJson() => {};'));
      expect(
        empty,
        contains('bool operator ==(Object other) => other is Empty;'),
      );
      expect(empty, contains('int get hashCode => (Empty).hashCode;'));
      final extra = files['models/root_extra.dart']!;
      expect(
        extra,
        contains(
          "additionalProperties2: r.additional(const {'additionalProperties'}, "
          'JsonReader.asInt),',
        ),
      );
      expect(extra, contains('...additionalProperties2,'));
      expect(extra, contains('this.additionalProperties2 = const {},'));
    });

    test('a recursive model refers to itself', () {
      final node = emit(r'''
    Root: {$ref: '#/components/schemas/Node'}
    Node:
      type: object
      properties:
        children: {type: array, items: {$ref: '#/components/schemas/Node'}}
''')['models/node.dart']!;
      expect(
        node,
        contains(
          "children: r.optional('children', "
          'JsonReader.listOf(JsonReader.objectOf(Node.fromJson))),',
        ),
      );
      expect(node, isNot(contains("import 'node.dart';")));
    });

    test('a tri-state field writes absent, null and a value (R7)', () {
      final files = emit(
        'Root: {type: object}\n',
        paths: '''
    patch:
      operationId: patchX
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                name: {type: [string, 'null']}
                meta: {}
                tags: {type: [array, 'null'], items: {type: string, format: date}}
      responses:
        '204': {description: ok}''',
      );
      final body = files['models/patch_x_request.dart']!;
      for (final line in [
        "name: r.patch('name', JsonReader.asString),",
        "meta: r.patchValue('meta'),",
        "if (name case final v?) 'name': v.toJson((p0) => p0),",
        "if (meta case final v?) 'meta': v.toJson((p0) => p0),",
        "if (tags case final v?) 'tags': "
            'v.toJson((p0) => [for (final e1 in p0) e1.toJson()]),',
        'final Patch<List<Date>>? tags;',
      ]) {
        expect(body, contains(line));
      }
    });
  });

  group('enums', () {
    test('an open enum with aliases, known values and unknown (R8)', () {
      final files = emit('''
    Root:
      type: object
      properties:
        level: {type: integer, enum: [1, -2]}
        flag: {type: boolean, enum: [true, false]}
        state: {type: string, enum: [unknown, "it's"]}
''');
      final level = files['models/root_level.dart']!;
      expect(level, contains('final value = JsonReader.asInt(json);'));
      expect(
        level,
        contains('static const valueMinus2 = RootLevelKnown.valueMinus2;'),
      );
      expect(level, contains('  value1(1),\n'));
      expect(level, contains('  valueMinus2(-2);\n'));
      expect(level, contains('int toJson() => value;'));
      final flag = files['models/root_flag.dart']!;
      expect(flag, contains('true_(true),'));
      expect(flag, contains('final value = JsonReader.asBool(json);'));
      final state = files['models/root_state.dart']!;
      expect(state, contains("unknown_('unknown'),"));
      expect(state, contains(r"itS('it\'s');"));
      expect(
        state,
        contains('class RootStateUnknown implements RootState'),
      );
    });

    test('a non-exhaustive enum is an interface', () {
      final files = emit(
        r'''
    Root: {$ref: '#/components/schemas/Color'}
    Color: {type: string, enum: [red]}
''',
        overrides: 'schemas:\n  Color: {exhaustive: false}\n',
      );
      expect(
        files['models/color.dart'],
        contains('abstract interface class Color {'),
      );
    });
  });

  group('unions', () {
    test('a discriminator picks the variant and is written back', () {
      final pet = emit(r'''
    Root:
      oneOf:
        - $ref: '#/components/schemas/Cat'
        - $ref: '#/components/schemas/Dog'
      discriminator:
        propertyName: kind
        mapping: {cat: Cat, dog: Dog, puppy: Dog}
    Cat:
      type: object
      properties: {kind: {const: cat}}
    Dog:
      type: object
      properties: {bark: {type: boolean}}
''')['models/root.dart']!;
      for (final line in [
        "final r = JsonReader.of(json, schema: 'Root');",
        "return switch (r.json['kind']) {",
        "'cat' => RootCat(Cat.fromJson(JsonReader.asObject(r.json))),",
        "('dog' || 'puppy') && final String tag => "
            'RootDog._(Dog.fromJson(JsonReader.asObject(r.json)), tag),',
        '_ => RootUnknown._(JsonValue(r.json)),',
        'Object? toJson() => value.toJson();',
        'const RootDog(this.value) : discriminator = null;',
        'final String? discriminator;',
        "Object? toJson() => {...value.toJson(), 'kind': discriminator ?? 'dog'};",
        "(other.discriminator ?? 'dog') == (discriminator ?? 'dog');",
        "int get hashCode => Object.hash(value, discriminator ?? 'dog');",
        'class RootUnknown implements Root {',
      ]) {
        expect(pet, contains(line));
      }
    });

    test('JSON types pick the variant, int before num (R9.3)', () {
      final id = emit('''
    Root:
      oneOf:
        - {type: number}
        - {type: string, format: date}
        - {type: integer}
        - {type: array, items: {type: string}}
''')['models/root.dart']!;
      expect(
        id,
        contains(
          '  factory Root.fromJson(Object? json) => switch (json) {\n'
          '    final String value => RootDate(JsonReader.asDate(value)),\n'
          '    final int value => RootInt(JsonReader.asInt(value)),\n'
          '    final List<Object?> value => '
          'RootList(JsonReader.listOf(JsonReader.asString)(value)),\n'
          '    final num value => RootNum(JsonReader.asNumber(value)),\n'
          '    _ => RootUnknown._(JsonValue(json)),\n'
          '  };\n',
        ),
      );
      expect(id, contains('const DeepEquality().equals(other.value, value)'));
    });

    test('union: structural tries the variants', () {
      const shapes = '''
    Root:
      KIND:
        - {type: object, required: [r], properties: {r: {type: number}}}
        - {type: object, required: [w], properties: {w: {type: number}}}
''';
      const structural = GenerationConfig(union: UnionMode.structural);
      final oneOf = emit(
        shapes.replaceFirst('KIND', 'oneOf'),
        generation: structural,
      )['models/root.dart']!;
      expect(oneOf, contains('final decoders = <Root Function()>['));
      expect(
        oneOf,
        contains(
          'return matches.length == 1 ? matches.single : '
          'RootUnknown._(JsonValue(json));',
        ),
      );
      final anyOf = emit(
        shapes.replaceFirst('KIND', 'anyOf'),
        generation: structural,
      )['models/root.dart']!;
      expect(
        anyOf,
        contains(
          'if (JsonReader.attempt(decode) case final value?) return value;',
        ),
      );
    });

    test('a variant of a custom type decodes its JSON side', () {
      final root = emit(
        r'''
    Root:
      oneOf:
        - $ref: '#/components/schemas/Money'
        - {type: boolean}
    Money: {type: string}
''',
        overrides: '''
schemas:
  Money:
    dartType: {type: Money, import: 'package:app/money.dart'}
''',
      )['models/root.dart']!;
      expect(
        root,
        contains(
          'final String value => '
          'RootMoney(Money.fromJson(JsonReader.asString(value))),',
        ),
      );
      expect(root, contains("import 'package:app/money.dart' show Money;"));
    });

    test('a shared JSON type is one variant of any JSON value', () {
      final root = emit(r'''
    Root:
      anyOf:
        - {type: integer}
        - {type: number}
        - {type: number, format: double}
        - $ref: '#/components/schemas/A'
        - {type: object, properties: {b: {type: string}}}
    A: {type: object, properties: {a: {type: string}}}
''')['models/root.dart']!;
      expect(
        root,
        contains(
          '  factory Root.fromJson(Object? json) => switch (json) {\n'
          '    final int value => RootInt(JsonReader.asInt(value)),\n'
          '    final Map<String, Object?> value => RootJson(JsonValue(value)),\n'
          '    final num value => RootJson(JsonValue(value)),\n'
          '    _ => RootUnknown._(JsonValue(json)),\n'
          '  };\n',
        ),
      );
      expect(
        root,
        contains(
          '/// A [Root] of a JSON type several variants share (number, object), '
          'as\n/// received.',
        ),
      );
    });

    test('imports JsonReader only when a decoder uses it', () {
      final root = emit('''
    Root:
      anyOf:
        - {type: string, enum: [none]}
        - {type: object, properties: {a: {type: string}}}
        - {type: object, properties: {b: {type: string}}}
''')['models/root.dart']!;
      expect(root, contains('show DeepEquality, JsonValue, immutable;'));
      expect(
        root,
        contains(
          'final String value => RootVariant1Case(RootVariant1.fromJson(value)),',
        ),
      );
    });

    test('a polymorphic base decodes into its subtypes', () {
      final files = emit(r'''
    Root:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
      discriminator: {propertyName: kind, mapping: {kitty: Cat}}
    Cat:
      allOf:
        - $ref: '#/components/schemas/Root'
        - {properties: {lives: {type: integer}}}
''');
      final root = files['models/root.dart']!;
      expect(
        root,
        contains(
          "      'kitty' => "
          'RootCat(Cat.fromJson(JsonReader.asObject(r.json))),\n',
        ),
      );
      expect(root, contains('Object? toJson() => value.toJson();'));
      expect(files['models/cat.dart'], contains('final String kind;'));
    });

    test('toString hides secrets', () {
      final files = emit(
        '''
    Root:
      type: object
      properties:
        name: {type: string}
        password: {type: string, format: password}
        token: {type: string, writeOnly: true}
''',
        paths: r'''
    post:
      operationId: postX
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/Root'}
      responses:
        '204': {description: ok}''',
      );
      expect(
        files['models/root_input.dart'],
        contains(
          r"String toString() => 'RootInput(name: $name, "
          "password: <redacted>, token: <redacted>)';",
        ),
      );
      expect(
        files['models/root.dart'],
        contains(
          r"String toString() => 'Root(name: $name, password: <redacted>)';",
        ),
      );
    });

    test('a union of unions wraps the inner union', () {
      final files = emit(r'''
    Root:
      oneOf:
        - $ref: '#/components/schemas/Inner'
        - {type: boolean}
    Inner:
      oneOf:
        - {type: object, properties: {kind: {const: a}}}
        - {type: object, properties: {kind: {const: b}}}
      discriminator: {propertyName: kind}
''');
      final root = files['models/root.dart']!;
      expect(
        root,
        contains(
          'final Map<String, Object?> value => RootInner(Inner.fromJson(value)),',
        ),
      );
      expect(files['models/inner.dart'], contains("'a' => InnerVariant1Case("));
    });
  });

  test('the field documents its known values', () {
    final files = emit('''
    Root:
      type: object
      properties:
        model:
          description: The model.
          anyOf:
            - {type: string}
            - {type: string, enum: [whisper-1, 'gpt`4', '']}
        level:
          anyOf: [{type: integer}, {type: integer, enum: [1, 2]}]
''');
    expect(
      files['models/root.dart'],
      allOf(
        contains(
          '  /// The model.\n'
          '  ///\n'
          '  /// Known values: `"whisper-1"`, `"gpt\\u00604"`, `""`.\n'
          '  final String? model;\n',
        ),
        contains(
          '  /// Known values: `1`, `2`.\n'
          '  final int? level;\n',
        ),
      ),
    );
  });

  test('the sentences the generator writes wrap at the line width', () {
    const long = 'AVeryLongComponentNameThatKeepsGoingForQuiteAWhile';
    for (final mode in UnionMode.values) {
      final files = emit(
        """
    Root:
      type: object
      properties:
        a: {\$ref: '#/components/schemas/${long}Union'}
        b: {\$ref: '#/components/schemas/${long}Enum'}
        c: {\$ref: '#/components/schemas/${long}Extra'}
    ${long}Union:
      oneOf:
        - {\$ref: '#/components/schemas/${long}Extra'}
        - {type: integer}
        - {type: array, items: {type: string}}
    ${long}Enum: {type: string, enum: [a, b]}
    ${long}Extra:
      type: object
      additionalProperties: {type: integer}
""",
        generation: GenerationConfig(union: mode),
      );
      for (final MapEntry(:key, :value) in files.entries) {
        for (final line in value.split('\n')) {
          if (!line.trimLeft().startsWith('///')) continue;
          expect(line.length, lessThanOrEqualTo(80), reason: '$key: $line');
        }
      }
    }
  });
}
