import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'model_emitter.dart';
import 'type_codec.dart';

/// Writes a [UnionDecl] (decisions 5–7 of M8): a `sealed` class (an
/// `abstract interface` one when the union is not exhaustive) whose
/// `fromJson` picks a variant, a class per variant that wraps a value of
/// the variant's type (`PetCat(Cat value)`), and a class for a value no
/// variant takes, which keeps the raw JSON (R9.1).
final class UnionEmitter {
  /// Creates an emitter that writes with [_codec].
  const UnionEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes [decl] to [out].
  void write(UnionDecl decl, DartWriter out) {
    final name = decl.name;
    _codec.imports
      ..fromRuntime('immutable')
      ..fromRuntime('JsonValue');
    out.doc(decl.description);
    if (decl.deprecated) out.line(ModelEmitter.deprecation);
    final modifier = decl.exhaustive ? 'sealed' : 'abstract interface';
    out.block('$modifier class $name', () {
      switch (decl.dispatch) {
        case .discriminator:
          _byDiscriminator(out, decl);
        case .jsonType:
          _byJsonType(out, decl);
        case .structural:
          _byStructure(out, decl);
      }
      out
        ..line()
        ..line('/// The value in JSON.')
        ..line('Object? toJson();');
    });
    for (final variant in decl.variants) {
      out.line();
      _variant(out, decl, variant);
    }
    out.line();
    _unknown(out, decl);
  }

  void _byDiscriminator(DartWriter out, UnionDecl decl) {
    final name = decl.name;
    final property = decl.discriminator!;
    _codec.imports.fromRuntime('JsonReader');
    out
      ..prose(
        'Decodes a [$name] by its `${_code.docSpan(property)}`; a value no '
        'variant has is a [${decl.unknownName}].',
      )
      ..block('factory $name.fromJson(Object? json)', () {
        out.line(
          'final r = JsonReader.of(json, schema: ${_code.string(name)});',
        );
        final seen = <String>{};
        final cases = <String>[];
        for (final variant in decl.variants) {
          final values = [
            for (final value in variant.discriminatorValues)
              if (seen.add(value)) _code.string(value),
          ];
          if (values.isEmpty) continue;
          final decoded = _decode(variant.type, 'r.json');
          if (_remembers(decl, variant)) {
            final pattern = values.length == 1
                ? values.single
                : '(${values.join(' || ')})';
            cases.add(
              '$pattern && final String tag => '
              '${variant.name}._($decoded, tag),',
            );
          } else {
            cases.add('${values.join(' || ')} => ${_wrap(variant, decoded)},');
          }
        }
        final fallback = switch (decl.defaultVariant) {
          final type? => decl.variants.firstWhere((v) => v.type == type),
          null => null,
        };
        final String otherwise;
        if (fallback == null) {
          otherwise = '_ => ${decl.unknownName}._(JsonValue(r.json))';
        } else if (_remembers(decl, fallback)) {
          otherwise =
              'final tag => ${fallback.name}._('
              '${_decode(fallback.type, 'r.json')}, '
              'tag is String ? tag : null)';
        } else {
          otherwise =
              '_ => ${_wrap(fallback, _decode(fallback.type, 'r.json'))}';
        }
        out
          ..line(
            'return switch (r.json[${_code.string(property)}]) {',
          )
          ..indented(() {
            cases.forEach(out.line);
            out.line('$otherwise,');
          })
          ..line('};');
      });
  }

  void _byJsonType(DartWriter out, UnionDecl decl) {
    final name = decl.name;
    out
      ..prose(
        'Decodes a [$name] by the JSON type of [json]; a value of another '
        'type is a [${decl.unknownName}].',
      )
      ..line('factory $name.fromJson(Object? json) => switch (json) {')
      ..indented(() {
        final cases = <(String, String)>[
          for (final variant in decl.variants)
            if (variant.jsonKinds.isEmpty)
              (
                _codec.jsonPattern(variant.type) ??
                    (throw StateError(
                      '${decl.name}.${variant.name} takes any JSON, so the '
                      'union cannot be dispatched by JSON type.',
                    )),
                _wrap(variant, _decode(variant.type, 'value')),
              )
            else
              for (final kind in variant.jsonKinds)
                (_kindPattern(kind), '${variant.name}(JsonValue(value))'),
        ];
        // An integer must meet `int` before `num` takes it.
        for (final (pattern, value) in [
          for (final c in cases)
            if (c.$1 != 'num') c,
          for (final c in cases)
            if (c.$1 == 'num') c,
        ]) {
          out.line('final $pattern value => $value,');
        }
        out.line('_ => ${decl.unknownName}._(JsonValue(json)),');
      })
      ..line('};');
  }

  void _byStructure(DartWriter out, UnionDecl decl) {
    final name = decl.name;
    final oneOf = decl.kind == .oneOf;
    _codec.imports.fromRuntime('JsonReader');
    out
      ..prose(
        oneOf
            ? 'Decodes a [$name] as the one variant [json] matches; none or '
                  'several make a [${decl.unknownName}].'
            : 'Decodes a [$name] as the first variant [json] matches; none '
                  'makes a [${decl.unknownName}].',
      )
      ..block('factory $name.fromJson(Object? json)', () {
        out.list('final decoders = <$name Function()>[', [
          for (final variant in decl.variants)
            '() => ${_wrap(variant, _decode(variant.type, 'json'))}',
        ], '];');
        if (oneOf) {
          out
            ..line('final matches = [')
            ..indented(() {
              out.line(
                'for (final decode in decoders) ?JsonReader.attempt(decode),',
              );
            })
            ..line('];')
            ..line(
              'return matches.length == 1 ? matches.single : '
              '${decl.unknownName}._(JsonValue(json));',
            );
        } else {
          out
            ..block('for (final decode in decoders)', () {
              out.line(
                'if (JsonReader.attempt(decode) case final value?) return value;',
              );
            })
            ..line('return ${decl.unknownName}._(JsonValue(json));');
        }
      });
  }

  /// The value of [type] decoded from [json], a JSON expression.
  String _decode(DartType type, String json) {
    final code = _codec.decodeValue(type, json);
    if (code.contains('JsonReader.')) _codec.imports.fromRuntime('JsonReader');
    return code;
  }

  String _wrap(UnionVariantIr variant, String value) =>
      '${variant.name}($value)';

  /// The pattern of a JSON value of [kind].
  static String _kindPattern(JsonKind kind) => switch (kind) {
    .string => 'String',
    .integer => 'int',
    .number => 'num',
    .boolean => 'bool',
    .array => 'List<Object?>',
    .object => 'Map<String, Object?>',
  };

  /// Whether the wrapper of [variant] writes the discriminator itself, as
  /// its model has no property for it (decision 5), and so keeps the value
  /// it was decoded with: an alias (`kitty` for `Cat`) is written back as
  /// it came, not changed into the first value of the mapping. A variant
  /// that is itself a union (`Pet` -> `Dog` -> `Lab`) has no property to
  /// carry the value either, unless it dispatches by the same property and
  /// writes it itself.
  bool _remembers(UnionDecl decl, UnionVariantIr variant) {
    final property = decl.discriminator;
    final type = variant.type;
    if (property == null || type is! NamedType) return false;
    return switch (_codec.declaration(type.id)) {
      final ModelDecl model => !model.fields.any((f) => f.jsonKey == property),
      final UnionDecl union => union.discriminator != property,
      _ => false,
    };
  }

  /// The discriminator a wrapper of [variant] has when it was made in code:
  /// the first value of the mapping, as a Dart string literal; null when no
  /// value selects the variant.
  String? _firstValue(UnionVariantIr variant) =>
      switch (variant.discriminatorValues.firstOrNull) {
        final first? => _code.string(first),
        null => null,
      };

  /// The discriminator [remembered] stands for, an expression: the value a
  /// wrapper was decoded with, else the first value of the mapping. Wrappers
  /// are equal when this is, so a wrapper made in code equals the one
  /// decoded from its JSON.
  String _effective(
    UnionVariantIr variant,
    String remembered, {
    bool group = true,
  }) => switch (_firstValue(variant)) {
    final first? when group => '($remembered ?? $first)',
    final first? => '$remembered ?? $first',
    null => remembered,
  };

  /// Whether `fromJson` creates the wrapper of [variant] with the value it
  /// was decoded with: it is picked by a discriminator value no earlier
  /// variant has, or is the default. A wrapper that is never picked has no
  /// such constructor (it would be unused).
  bool _decodedWithTag(UnionDecl decl, UnionVariantIr variant) {
    if (!_remembers(decl, variant)) return false;
    if (decl.defaultVariant != null && decl.defaultVariant == variant.type) {
      return true;
    }
    final seen = <String>{};
    for (final other in decl.variants) {
      final fresh = [
        for (final value in other.discriminatorValues)
          if (seen.add(value)) value,
      ];
      if (identical(other, variant)) return fresh.isNotEmpty;
    }
    return false;
  }

  void _variant(DartWriter out, UnionDecl decl, UnionVariantIr variant) {
    final type = _codec.type(variant.type);
    final name = variant.name;
    final remembers = _remembers(decl, variant);
    final property = decl.discriminator ?? '';
    final first = variant.discriminatorValues.firstOrNull;
    out
      ..prose(
        variant.jsonKinds.isEmpty
            ? 'A [${decl.name}] that is a `${_code.docSpan(type)}`.'
            : 'A [${decl.name}] of a JSON type several variants share '
                  '(${variant.jsonKinds.map((k) => k.name).join(', ')}), '
                  'as received.',
      )
      ..line('@immutable')
      ..block('class $name implements ${decl.name}', () {
        out.line('/// Wraps [value].');
        if (remembers) {
          out.line('const $name(this.value) : discriminator = null;');
          if (_decodedWithTag(decl, variant)) {
            out
              ..line()
              ..line('const $name._(this.value, this.discriminator);');
          }
        } else {
          out.line('const $name(this.value);');
        }
        out
          ..line()
          ..line('/// The value of the variant.')
          ..line('final $type value;');
        if (remembers) {
          out
            ..line()
            ..prose(
              'The `${_code.docSpan(property)}` [value] was decoded with; '
              'null for a wrapper made in code, which writes '
              '${first == null ? 'none' : '`${_code.docSpan(_code.string(first))}`'}.',
            )
            ..line('final String? discriminator;');
        }
        out
          ..line()
          ..line('@override')
          ..line('Object? toJson() => ${_toJson(decl, variant)};')
          ..line()
          ..line('@override');
        final deep = _codec.needsDeep(variant.type);
        if (deep) _codec.imports.fromRuntime('DeepEquality');
        out.chain('bool operator ==(Object other) =>', [
          'other is $name',
          if (deep)
            'const DeepEquality().equals(other.value, value)'
          else
            'other.value == value',
          if (remembers)
            '${_effective(variant, 'other.discriminator')} == '
                '${_effective(variant, 'discriminator')}',
        ], '&&');
        out
          ..line()
          ..line('@override')
          ..line(
            remembers
                ? 'int get hashCode => '
                      'Object.hash(value, ${_effective(variant, 'discriminator', group: false)});'
                : deep
                ? 'int get hashCode => const DeepEquality().hash(value);'
                : 'int get hashCode => value.hashCode;',
          )
          ..line()
          ..line('@override')
          ..line(
            "String toString() => '${name.replaceAll(r'$', r'\$')}"
            "(${variant.sensitive ? '<redacted>' : r'$value'})';",
          );
      });
  }

  /// The JSON of a variant: the value's, and for a variant of a union with a
  /// discriminator that the variant has no property for, the discriminator
  /// too (decision 5): the one it was decoded with, else the first value of
  /// the mapping. When the variant is a union, its JSON is not always an
  /// object (the one it keeps as received may be anything), so the
  /// discriminator is added to an object only.
  String _toJson(UnionDecl decl, UnionVariantIr variant) {
    final encoded = _codec.encode(variant.type, 'value');
    if (!_remembers(decl, variant)) return encoded;
    final key = _code.string(decl.discriminator!);
    final tag = switch (_firstValue(variant)) {
      final first? => 'discriminator ?? $first',
      null => '?discriminator',
    };
    final entry = '$key: $tag';
    final type = variant.type;
    if (type is NamedType && _codec.declaration(type.id) is UnionDecl) {
      return 'switch ($encoded) {'
          'final Map<String, Object?> json => {...json, $entry}, '
          'final json => json}';
    }
    return '{...$encoded, $entry}';
  }

  void _unknown(DartWriter out, UnionDecl decl) {
    final name = decl.unknownName;
    final shown = decl.unknownSensitive || decl.variants.any((v) => v.sensitive)
        ? '<redacted>'
        : r'$json';
    _codec.imports.fromRuntime('DeepEquality');
    out
      ..prose(
        'A [${decl.name}] that no variant takes; only [${decl.name}.fromJson] '
        'creates one.',
      )
      ..line('@immutable')
      ..block('class $name implements ${decl.name}', () {
        out
          ..line('const $name._(this.json);')
          ..line()
          ..line('/// The JSON as received.')
          ..line('final JsonValue json;')
          ..line()
          ..line('@override')
          ..line('Object? toJson() => json;')
          ..line()
          ..line('@override')
          ..chain('bool operator ==(Object other) =>', [
            'other is $name',
            'const DeepEquality().equals(other.json, json)',
          ], '&&')
          ..line()
          ..line('@override')
          ..line('int get hashCode => const DeepEquality().hash(json);')
          ..line()
          ..line('@override')
          ..line(
            "String toString() => '${name.replaceAll(r'$', r'\$')}"
            "($shown)';",
          );
      });
  }
}
