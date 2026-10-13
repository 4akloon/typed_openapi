import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';
import 'union_variants.dart';

/// Writes the `fromJson` of a union that dispatches by a discriminator
/// property (R9.1): a variant whose JSON is not an object (GitHub's
/// directory listing is an array) is picked by its JSON type first, as it
/// has no property to read; then a `switch` on the property's value, with
/// the default mapping's variant or the unknown variant for any other value.
final class DiscriminatorDecoder {
  /// Creates the writer that writes with [_codec] and [_variants].
  const DiscriminatorDecoder(this._codec, this._variants);

  final TypeCodec _codec;
  final UnionVariants _variants;

  static const _code = DartCode();

  /// The JSON pattern of an object: a variant of it has the property.
  static const _object = 'Map<String, Object?>';

  /// Writes the `fromJson` factory of [decl] to [out].
  void write(DartWriter out, UnionDecl decl) {
    final name = decl.name;
    final property = decl.discriminator!;
    _codec.imports.fromRuntime('JsonReader');
    out
      ..prose(
        'Decodes a [$name] by its `${_code.docSpan(property)}`; a value no '
        'variant has is a [${decl.unknownName}].',
      )
      ..block('factory $name.fromJson(Object? json)', () {
        for (final (pattern, variant) in _byJsonType(decl)) {
          final decoded = _variants.decode(variant.type, 'value');
          out.block(
            'if (json case final $pattern value)',
            () => out.line('return ${_variants.wrap(variant, decoded)};'),
          );
        }
        out
          ..line(
            'final r = JsonReader.of(json, schema: ${_code.string(name)});',
          )
          ..line('return switch (r.json[${_code.string(property)}]) {')
          ..indented(() {
            _cases(decl).forEach(out.line);
            out.line('${_otherwise(decl)},');
          })
          ..line('};');
      });
  }

  /// The variants whose JSON is not an object, each with the pattern of its
  /// JSON type; the first variant of a type wins.
  List<(String, UnionVariantIr)> _byJsonType(UnionDecl decl) {
    final patterns = <String>{};
    return [
      for (final variant in decl.variants)
        if (_codec.jsonPattern(variant.type) case final pattern?
            when pattern != _object && patterns.add(pattern))
          (pattern, variant),
    ];
  }

  /// A case per object variant that a discriminator value selects first.
  List<String> _cases(UnionDecl decl) {
    final seen = <String>{};
    final cases = <String>[];
    for (final variant in decl.variants) {
      final json = _codec.jsonPattern(variant.type);
      if (json != null && json != _object) continue;
      final values = [
        for (final value in variant.discriminatorValues)
          if (seen.add(value)) _code.string(value),
      ];
      if (values.isEmpty) continue;
      final decoded = _variants.decode(variant.type, 'r.json');
      if (_variants.remembers(decl, variant)) {
        final pattern = values.length == 1
            ? values.single
            : '(${values.join(' || ')})';
        cases.add(
          '$pattern && final String tag => '
          '${variant.name}._($decoded, tag),',
        );
      } else {
        cases.add(
          '${values.join(' || ')} => ${_variants.wrap(variant, decoded)},',
        );
      }
    }
    return cases;
  }

  /// The last case: the default mapping's variant, or the unknown one.
  String _otherwise(UnionDecl decl) {
    final fallback = switch (decl.defaultVariant) {
      final type? => decl.variants.firstWhere((v) => v.type == type),
      null => null,
    };
    if (fallback == null) {
      return '_ => ${decl.unknownName}._(JsonValue(r.json))';
    }
    final decoded = _variants.decode(fallback.type, 'r.json');
    if (_variants.remembers(decl, fallback)) {
      return 'final tag => ${fallback.name}._($decoded, '
          'tag is String ? tag : null)';
    }
    return '_ => ${_variants.wrap(fallback, decoded)}';
  }
}
