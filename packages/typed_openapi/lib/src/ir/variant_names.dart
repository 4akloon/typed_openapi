import 'dart_type.dart';
import 'declaration_names.dart';
import 'mapping_state.dart';

/// Names the classes that wrap the variants of a union.
final class VariantNames {
  /// Names variants of the declarations in [_state].
  const VariantNames(this._state);

  final MappingState _state;

  /// The classes that wrap the variants of [types] in the union [union], in
  /// order: [_variantClass] names, except that variants whose short names
  /// are the same (a list of strings and a list of integers) are named by
  /// their whole type (`PetListString`, `PetListInt`).
  List<String> classes(String union, List<DartType> types) {
    final short = [for (final type in types) _variantClass(union, type)];
    return [
      for (final (i, type) in types.indexed)
        if (short.where((name) => name == short[i]).length > 1)
          _variantClass(union, type, deep: true)
        else
          short[i],
    ];
  }

  /// The class that wraps a variant of [type] in the union [union]: the
  /// union's name and the variant's (`PetCat`), or the variant's name and
  /// `Case` when it starts with the union's already (`PetVariant1Case` for
  /// an inline variant, `PetCatCase` for a variant named `PetCat`). A
  /// built-in type is named by its kind (`IdOrNameString`, `IdOrNameInt`);
  /// with [deep], a list or a map also by its element (`IdOrNameListInt`).
  String _variantClass(String union, DartType type, {bool deep = false}) {
    final name = _label(type, deep: deep);
    return name.startsWith(union) ? '${name}Case' : '$union$name';
  }

  String _label(DartType type, {required bool deep}) => switch (type) {
    NamedType(:final id) =>
      _state.pending[id]?.name ?? DeclarationNames.fallbackName,
    CustomType(:final type) => type,
    ListType(:final item) => deep ? 'List${_label(item, deep: deep)}' : 'List',
    MapType(:final value) => deep ? 'Map${_label(value, deep: deep)}' : 'Map',
    PatchType() => 'Patch',
    CoreType(:final kind) => switch (kind) {
      .integer => 'Int',
      .float => 'Double',
      .number => 'Num',
      .string => 'String',
      .boolean => 'Bool',
      .dateTime => 'DateTime',
      .date => 'Date',
      .bytes || .binary => 'Bytes',
      .json => 'Json',
    },
  };
}
