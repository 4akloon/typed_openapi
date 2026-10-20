import 'package:typed_openapi_core/src/ir/ir.dart';

/// Reads declarations back from the IR a schema mapper test built.
final class MappedIr {
  const MappedIr._();

  /// The declaration [name] of [ir].
  static T declaration<T extends Declaration>(ClientIr ir, String name) =>
      ir.declarations.firstWhere((d) => d.name == name) as T;

  /// The union [name] of [ir].
  static UnionDecl union(ClientIr ir, String name) =>
      declaration<UnionDecl>(ir, name);

  /// The variants of the union [name] as `type` strings.
  static List<String> variantsOf(ClientIr ir, String name) => [
    for (final v in declaration<UnionDecl>(ir, name).variants)
      v.type.code(ir.nameOf),
  ];

  /// The values of the enum [name] as `name=value` strings.
  static List<String> valuesOf(ClientIr ir, String name) => [
    for (final v in declaration<EnumDecl>(ir, name).values)
      '${v.name}=${v.value}',
  ];
}
