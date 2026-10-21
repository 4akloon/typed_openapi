import 'package:typed_openapi_core/src/ir/ir.dart';

/// Where each IR class is written in the dump of [IrJson], so a test looks
/// for a field among the keys of that class's own objects and not among
/// every key of the dump (`description` of one class would hide a missing
/// `description` of another).
final class IrJsonClasses {
  const IrJsonClasses._();

  static const _operations = 'groups.operations';

  /// The path of the objects of each class: keys, where a list is walked
  /// through; the empty path is the dump itself.
  static final paths = <Type, String>{
    ClientIr: '',
    GroupIr: 'groups',
    OperationIr: _operations,
    EventStreamIr: '$_operations.events',
    EventUnionIr: '$_operations.events.union',
    EventVariantIr: '$_operations.events.union.variants',
    ParameterIr: '$_operations.parameters',
    RequestBodyIr: '$_operations.body',
    ResponseIr: '$_operations.responses',
    // The `errors` entries sit in the operation's object.
    SingleError: _operations,
    ErrorsByStatus: _operations,
    EncodingIr: '$_operations.body.encoding',
    PartIr: '$_operations.body.parts',
    StatusTypeIr: '$_operations.successType',
    StatusCaseIr: '$_operations.successType.cases',
    RootIr: 'root',
    ServerIr: 'root.servers',
    ServerVariableIr: 'root.servers.variables',
    SecurityUseIr: '$_operations.security',
    SecuritySchemeIr: '$_operations.security.scheme',
    Declaration: 'declarations',
    ModelDecl: 'declarations',
    FieldIr: 'declarations.fields',
    ConstraintsIr: 'declarations.fields.constraints',
    EnumDecl: 'declarations',
    EnumValueIr: 'declarations.cases',
    UnionDecl: 'declarations',
    UnionVariantIr: 'declarations.variants',
  };

  /// The keys of the objects [json] holds at [path].
  static Set<String> keysAt(Object? json, String path) {
    final keys = <String>{};
    _walk(json, path.isEmpty ? const [] : path.split('.'), keys);
    return keys;
  }

  static void _walk(Object? json, List<String> path, Set<String> keys) {
    switch (json) {
      case final List<Object?> list:
        for (final item in list) {
          _walk(item, path, keys);
        }
      case final Map<String, Object?> map when path.isEmpty:
        keys.addAll(map.keys);
      case final Map<String, Object?> map:
        _walk(map[path.first], path.sublist(1), keys);
    }
  }
}
