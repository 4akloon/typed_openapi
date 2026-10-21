import 'dart_type.dart';

/// Writes a [DartType] as text for the IR dump, with everything that makes
/// the generated code differ: the code of the type alone would not tell
/// `bytes` from `binary` (both `Uint8List`) or one custom type's import,
/// converter and JSON side from another's.
final class IrTypeText {
  /// Creates a writer; [_nameOf] gives the name of a declaration.
  const IrTypeText(this._nameOf);

  final String Function(DeclId id) _nameOf;

  /// [type] as text.
  String of(DartType type) {
    final text = switch (type) {
      CoreType(:final kind) when kind == .bytes || kind == .binary =>
        'Uint8List(${kind.name})',
      CoreType() || NamedType() => type.withNullable(false).code(_nameOf),
      ListType(:final item) => 'List<${of(item)}>',
      MapType(:final value) => 'Map<String, ${of(value)}>',
      PatchType(:final value) => 'Patch<${of(value)}>',
      CustomType(:final type, :final import, :final converter, :final json) =>
        '$type(import: $import, converter: ${converter ?? '-'}, '
            'json: ${of(json)})',
    };
    return type.nullable ? '$text?' : text;
  }
}
