import 'package:typed_openapi/typed_openapi.dart';

/// The spec strings a client's code must hold as string literals with the
/// same value: property keys, string enum values, discriminator properties
/// and the values of the variants an object is (a variant of another JSON
/// type is picked by that type), parameter names and event names, read
/// from the IR (which keeps them as the spec writes them).
final class SpecStrings {
  /// Creates the collector.
  const SpecStrings();

  /// The strings of [ir], sorted.
  List<String> of(ClientIr ir) {
    final byId = {for (final d in ir.declarations) d.id: d};
    bool isObject(DartType type) => switch (type) {
      MapType() || CoreType(kind: CoreKind.json) => true,
      NamedType(:final id) => byId[id] is ModelDecl || byId[id] is UnionDecl,
      _ => false,
    };
    final strings = <String>{
      for (final declaration in ir.declarations)
        ...switch (declaration) {
          ModelDecl(:final fields) => [for (final f in fields) f.jsonKey],
          EnumDecl(:final values) => [
            for (final v in values)
              if (v.value case final String text) text,
          ],
          UnionDecl(:final discriminator, :final variants) => [
            ?discriminator,
            if (discriminator != null)
              for (final v in variants)
                if (isObject(v.type)) ...v.discriminatorValues,
          ],
        },
      for (final group in ir.groups)
        for (final operation in group.operations) ...[
          for (final p in operation.parameters) p.wireName,
          for (final v
              in operation.events?.union?.variants ?? const <EventVariantIr>[])
            v.event,
        ],
    };
    return strings.toList()..sort();
  }
}
