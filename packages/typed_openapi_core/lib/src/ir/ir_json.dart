import 'dart:convert';

import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_declaration_json.dart';
import 'ir_operation_json.dart';
import 'ir_type_text.dart';

/// Writes a [ClientIr] as JSON, to inspect what the generator will emit.
///
/// The output is deterministic: keys come in a fixed order and lists in the
/// IR's order. Locations are written as `file#pointer`, with files named by
/// the function given to the constructor.
final class IrJson {
  /// Creates a writer that names documents with [_fileOf].
  const IrJson(String Function(Uri document) this._fileOf);

  /// Creates a writer that leaves every location out: what is left is what
  /// the emitters read, whatever the place or the name of the spec.
  const IrJson.withoutLocations() : _fileOf = null;

  final String Function(Uri document)? _fileOf;

  /// [ir] as indented JSON text.
  String encode(ClientIr ir) =>
      const JsonEncoder.withIndent('  ').convert(toJson(ir));

  /// [ir] as plain JSON values.
  Map<String, Object?> toJson(ClientIr ir) {
    final type = IrTypeText(ir.nameOf).of;
    final operations = IrOperationJson(_at, type);
    final declarations = IrDeclarationJson(_at, type);
    return {
      'declarations': [
        for (final d in ir.declarations) declarations.declaration(d),
      ],
      'groups': [
        for (final group in ir.groups)
          {
            'name': group.name,
            'field': group.field,
            'key': group.key,
            'operations': [
              for (final operation in group.operations)
                operations.operation(operation),
            ],
          },
      ],
      'root': operations.root(ir.root),
    };
  }

  String? _at(SpecLocation location) => switch (_fileOf) {
    final fileOf? => '${fileOf(location.document)}${location.pointer.value}',
    null => null,
  };
}
