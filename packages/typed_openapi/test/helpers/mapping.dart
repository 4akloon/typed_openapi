import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/names.dart';
import 'package:typed_openapi/src/ir/schema_mapper.dart';

import 'ir_fixture.dart';

/// Maps the component schemas [keys] of [fixture]; returns the IR of their
/// declarations and the types of [keys].
(ClientIr, Map<String, String>) mapComponents(
  IrFixture fixture,
  List<String> keys,
) {
  final mapper = SchemaMapper(fixture.context);
  final schemas = fixture.context.model.document.components!.schemas;
  final types = {
    for (final key in keys) key: mapper.typeOfComponent(schemas[key]!),
  };
  final scope = NameScope(
    reserved: {
      ...DartNames.reservedWords,
      ...DartNames.builtInIdentifiers,
      ...DartNames.takenTypeNames,
    },
    reservedSuffix: 'Model',
  );
  final ir = ClientIr(declarations: mapper.declarations(scope), groups: []);
  return (
    ir,
    {
      for (final MapEntry(:key, :value) in types.entries)
        key: value.code(ir.nameOf),
    },
  );
}

/// The fields of the model [name] as `name: type` lines.
List<String> fieldsOf(ClientIr ir, String name) => [
  for (final f
      in (ir.declarations.firstWhere((d) => d.name == name) as ModelDecl)
          .fields)
    '${f.name}(${f.jsonKey}): ${f.type.code(ir.nameOf)}',
];
