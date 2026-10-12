import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_json.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/spec_node.dart';

void main() {
  final file = Uri.parse('file:///work/api.yaml');
  SpecLocation at(String pointer) =>
      SpecLocation(file, JsonPointer.parse(pointer));
  final pet = DeclId(at('#/components/schemas/Pet'));
  final petInput = DeclId(
    at('#/components/schemas/Pet'),
    variant: DeclVariant.input,
  );

  test('writes types as Dart code', () {
    String code(DartType t) =>
        t.code((id) => id.variant == .input ? 'PetInput' : 'Pet');
    expect(code(const CoreType(.integer)), 'int');
    expect(code(const CoreType(.date, nullable: true)), 'Date?');
    expect(code(const CoreType(.json, nullable: true)), 'JsonValue');
    expect(code(ListType(NamedType(pet), nullable: true)), 'List<Pet>?');
    expect(code(MapType(NamedType(petInput))), 'Map<String, PetInput>');
    expect(
      code(const PatchType(CoreType(.string), nullable: true)),
      'Patch<String>?',
    );
    expect(
      code(
        const CustomType(
          type: 'Money',
          import: 'package:app/money.dart',
          json: CoreType(.string),
        ),
      ),
      'Money',
    );
  });

  test('compares types by structure', () {
    expect(ListType(NamedType(pet)), ListType(NamedType(pet)));
    expect(NamedType(pet) == NamedType(petInput), isFalse);
    expect(
      const CoreType(.string) == const CoreType(.string, nullable: true),
      isFalse,
    );
    expect(
      const CoreType(.json) == const CoreType(.json, nullable: true),
      isTrue,
    );
  });

  test('gives a field its type by the required x nullable matrix', () {
    FieldIr field({
      bool required = false,
      bool nullable = false,
      bool triState = false,
      CoreKind kind = .string,
    }) => FieldIr(
      name: 'tag',
      jsonKey: 'tag',
      valueType: CoreType(kind, nullable: nullable),
      location: at('#/components/schemas/Pet/properties/tag'),
      required: required,
      triState: triState,
    );
    String code(FieldIr f) => f.type.code((_) => '?');
    expect(code(field(required: true)), 'String');
    expect(code(field(required: true, nullable: true)), 'String?');
    expect(code(field()), 'String?');
    expect(code(field(nullable: true)), 'String?');
    expect(code(field(nullable: true, triState: true)), 'Patch<String>?');
    expect(code(field(kind: .json)), 'JsonValue');
  });

  test('sorts declarations and groups and writes them as JSON', () {
    final ir = ClientIr(
      declarations: [
        ModelDecl(
          id: pet,
          name: 'Pet',
          fields: [
            FieldIr(
              name: 'id',
              jsonKey: 'id',
              valueType: const CoreType(.integer),
              location: at('#/components/schemas/Pet/properties/id'),
              required: true,
              readOnly: true,
            ),
          ],
          direction: .response,
        ),
        EnumDecl(
          id: DeclId(at('#/components/schemas/Status')),
          name: 'Status',
          kind: .string,
          values: const [EnumValueIr('available', 'available')],
        ),
      ],
      groups: [
        GroupIr('PetsApi', [
          OperationIr(
            location: at('#/paths/~1pets~1{id}/get'),
            name: 'getPet',
            method: 'GET',
            path: '/pets/{id}',
            parameters: [
              ParameterIr(
                name: 'id',
                wireName: 'id',
                placement: ParameterLocation.path,
                type: const CoreType(.integer),
                location: at('#/paths/~1pets~1{id}/get/parameters/0'),
                required: true,
              ),
            ],
            responses: [
              ResponseIr(
                status: '200',
                kind: .json,
                location: at('#/paths/~1pets~1{id}/get/responses/200'),
                type: NamedType(pet),
                envelopeKey: 'data',
              ),
            ],
            errors: const NoErrors(),
          ),
        ]),
      ],
    );
    expect(ir.declarations.map((d) => d.name), ['Pet', 'Status']);
    expect(ir[pet]?.name, 'Pet');
    expect(ir.nameOf(petInput), '?');
    expect(IrJson((uri) => uri.pathSegments.last).encode(ir), '''
{
  "declarations": [
    {
      "name": "Pet",
      "at": "api.yaml#/components/schemas/Pet",
      "kind": "model",
      "direction": "response",
      "fields": [
        {
          "name": "id",
          "json": "id",
          "type": "int",
          "required": true,
          "readOnly": true
        }
      ]
    },
    {
      "name": "Status",
      "at": "api.yaml#/components/schemas/Status",
      "kind": "enum",
      "values": "string",
      "cases": {
        "available": "available"
      }
    }
  ],
  "groups": [
    {
      "name": "PetsApi",
      "operations": [
        {
          "name": "getPet",
          "method": "GET",
          "path": "/pets/{id}",
          "at": "api.yaml#/paths/~1pets~1{id}/get",
          "parameters": [
            {
              "name": "id",
              "in": "path",
              "wire": "id",
              "type": "int",
              "required": true
            }
          ],
          "responses": [
            {
              "status": "200",
              "kind": "json",
              "type": "Pet",
              "envelope": "data"
            }
          ],
          "errors": "Never"
        }
      ]
    }
  ]
}''');
  });
}
