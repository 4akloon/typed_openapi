import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'type_codec.dart';

/// What the writers of a union share about its variants: how a variant's
/// value is decoded and wrapped, and whether its wrapper keeps the
/// discriminator value it was decoded with.
final class UnionVariants {
  /// Creates the helper that writes with [_codec].
  const UnionVariants(this._codec);

  final TypeCodec _codec;

  /// The value of [type] decoded from [json], a JSON expression.
  String decode(DartType type, String json) {
    final code = _codec.decodeValue(type, json);
    if (code.contains('JsonReader.')) _codec.imports.fromRuntime('JsonReader');
    return code;
  }

  /// [value] wrapped in the class of [variant].
  String wrap(UnionVariantIr variant, String value) =>
      '${variant.name}($value)';

  /// Whether the wrapper of [variant] writes the discriminator itself, as
  /// its model has no property for it (decision 5), and so keeps the value
  /// it was decoded with: an alias (`kitty` for `Cat`) is written back as
  /// it came, not changed into the first value of the mapping. A variant
  /// that is itself a union (`Pet` -> `Dog` -> `Lab`) has no property to
  /// carry the value either, unless it dispatches by the same property and
  /// writes it itself.
  bool remembers(UnionDecl decl, UnionVariantIr variant) {
    final property = decl.discriminator;
    final type = variant.type;
    if (property == null || type is! NamedType) return false;
    return switch (_codec.declaration(type.id)) {
      final ModelDecl model => !model.fields.any((f) => f.jsonKey == property),
      final UnionDecl union => union.discriminator != property,
      _ => false,
    };
  }
}
