import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'model_constructors.dart';
import 'type_codec.dart';

/// Writes the class of a [ModelDecl] (decisions 3, 4, 8, 10–13 of M8): a
/// `class` with a `const` constructor and `fromJson` ([ModelConstructors]),
/// `toJson`, deep `==` and `hashCode`, and `toString`.
final class ModelEmitter {
  /// Creates an emitter that writes with [_codec].
  const ModelEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// The message of `@Deprecated` for what the spec marks deprecated.
  static const deprecation = "@Deprecated('Deprecated in the API spec.')";

  /// Writes [model] to [out].
  void write(ModelDecl model, DartWriter out) {
    final name = model.name;
    final fields = [
      for (final field in model.fields)
        if (field.constValue == null) field,
    ];
    final constants = [
      for (final field in model.fields)
        if (field.constValue != null) field,
    ];
    final extra = model.additionalProperties;
    _codec.imports.fromRuntime('immutable');
    out.doc(model.description);
    if (model.deprecated) out.line(deprecation);
    out
      ..line('@immutable')
      ..block('class $name', () {
        ModelConstructors(_codec).write(out, model, fields, constants);
        for (final field in constants) {
          out.line();
          _constant(out, field);
        }
        for (final field in fields) {
          out.line();
          _field(out, field);
        }
        if (extra != null) {
          out
            ..line()
            ..prose(
              'The properties of the object the schema does not list '
              '(`additionalProperties`).',
            )
            ..line(
              'final ${_codec.type(MapType(extra))} '
              '${model.additionalPropertiesName};',
            );
        }
        out.line();
        _toJson(out, model, fields, constants);
        out.line();
        _equality(out, model, fields);
        out.line();
        _toString(out, model, fields);
      });
  }

  void _constant(DartWriter out, FieldIr field) {
    _docs(out, field, constant: true);
    out.line(
      '${_codec.type(field.valueType.withNullable(false))} get ${field.name} '
      '=> ${_code.literal(field.constValue)};',
    );
  }

  void _field(DartWriter out, FieldIr field) {
    _docs(out, field);
    out.line('final ${_codec.type(field.type)} ${field.name};');
  }

  void _docs(DartWriter out, FieldIr field, {bool constant = false}) {
    final parts = [
      ?field.description,
      if (constant && field.description == null)
        'Always ${_code.jsonSpan(field.constValue)}.',
      ?_constraints(field.constraints),
      ?_knownValues(field.knownValues),
      if (field.defaultValue case (final value,))
        'Defaults to ${_code.jsonSpan(value)} on the server.',
    ];
    if (parts.isNotEmpty) out.doc(parts.join('\n\n'));
    if (field.deprecated) out.line(deprecation);
  }

  /// The values a union left out of a field's type as a sentence, each as
  /// a JSON code span; null when there are none. A backtick in a value is
  /// the JSON escape `\u0060`, so a span never ends early.
  static String? _knownValues(List<Object?> values) => values.isEmpty
      ? null
      : 'Known values: ${[
          for (final value in values) _code.jsonSpan(value),
        ].join(', ')}.';

  /// The constraints of a field as a sentence (decision 12), such as
  /// `1–64 characters, matches `^[a-z]+$`.`; null when there are none.
  static String? _constraints(ConstraintsIr c) {
    if (c.isEmpty) return null;
    String range(int? min, int? max, String unit) => switch ((min, max)) {
      (final a?, final b?) when a == b => '$a $unit',
      (final a?, final b?) => '$a–$b $unit',
      (final a?, null) => 'at least $a $unit',
      (null, final b?) => 'at most $b $unit',
      (null, null) => '',
    };
    final pattern = c.pattern;
    final parts = [
      range(c.minLength, c.maxLength, 'characters'),
      if (pattern != null && pattern.contains('`'))
        'matches ${_code.string(pattern)}'
      else if (pattern != null)
        'matches `${_code.docSpan(pattern)}`',
      if (c.minimum case final v?) 'at least $v',
      if (c.exclusiveMinimum case final v?) 'greater than $v',
      if (c.maximum case final v?) 'at most $v',
      if (c.exclusiveMaximum case final v?) 'less than $v',
      if (c.multipleOf case final v?) 'a multiple of $v',
      range(c.minItems, c.maxItems, 'items'),
      if (c.uniqueItems) 'unique items',
      range(c.minProperties, c.maxProperties, 'properties'),
    ].where((part) => part.isNotEmpty);
    final text = parts.join(', ');
    return '${text[0].toUpperCase()}${text.substring(1)}.';
  }

  void _toJson(
    DartWriter out,
    ModelDecl model,
    List<FieldIr> fields,
    List<FieldIr> constants,
  ) {
    out.prose(
      'Encodes this [${model.name}]; optional fields that are not set are '
      'not sent.',
    );
    final entries = <String>[];
    for (final field in model.fields) {
      final key = _code.string(field.jsonKey);
      if (field.constValue != null) {
        const absent = ModelConstructors.absent;
        entries.add(
          '${field.required ? '' : 'if (!$absent.contains($key)) '}'
          '$key: ${_code.literal(field.constValue)}',
        );
        continue;
      }
      entries.add(_entry(field, key));
    }
    if (model.additionalProperties case final extra?) {
      final name = model.additionalPropertiesName;
      entries.add(
        _codec.isIdentity(extra)
            ? '...$name'
            : '...$name.map((k, v) => MapEntry(k, '
                  '${_codec.encodeNullable(extra, 'v')}))',
      );
    }
    if (entries.isEmpty) {
      out.line('Map<String, Object?> toJson() => {};');
    } else {
      out.list('Map<String, Object?> toJson() => {', entries, '};');
    }
  }

  String _entry(FieldIr field, String key) {
    final name = field.name;
    final type = field.type;
    if (field.triState) {
      return 'if ($name case final v?) $key: '
          '${_codec.encode(type.withNullable(false), 'v')}';
    }
    if (field.required) {
      final nullable = _codec.encodeNullable(type, name);
      if (!type.nullable ||
          _codec.isIdentity(type) ||
          nullable.startsWith('$name?.')) {
        return '$key: $nullable';
      }
      // A field is not promoted by `name == null ? ...`; a pattern binds it.
      return '$key: switch ($name) {final v? => '
          '${_codec.encode(type.withNullable(false), 'v')}, null => null}';
    }
    if (ModelConstructors.isJson(type)) return '$key: ?$name.raw';
    final inner = type.withNullable(false);
    if (_codec.isIdentity(inner)) return '$key: ?$name';
    final nullable = _codec.encodeNullable(type, name);
    if (nullable.startsWith('$name?.')) return '$key: ?$nullable';
    return 'if ($name case final v?) $key: ${_codec.encode(inner, 'v')}';
  }

  void _equality(DartWriter out, ModelDecl model, List<FieldIr> fields) {
    final name = model.name;
    final compared = [
      for (final field in fields) (field.name, field.type),
      if (model.additionalProperties case final extra?)
        (model.additionalPropertiesName, MapType(extra)),
      if (model.fields.any((f) => f.constValue != null && !f.required))
        (ModelConstructors.absent, const ListType(CoreType(.string))),
    ];
    out.line('@override');
    out.chain('bool operator ==(Object other) =>', [
      'other is $name',
      for (final (field, type) in compared) _equals(field, type),
    ], '&&');
    out
      ..line()
      ..line('@override');
    if (compared.isEmpty) {
      out.line('int get hashCode => ($name).hashCode;');
    } else {
      _codec.imports.fromRuntime('DeepEquality');
      out.list('int get hashCode => const DeepEquality().hash([', [
        for (final (field, _) in compared) field,
      ], ']);');
    }
  }

  String _equals(String field, DartType type) {
    if (_codec.needsDeep(type)) {
      _codec.imports.fromRuntime('DeepEquality');
      return 'const DeepEquality().equals(other.$field, ${_own(field)})';
    }
    return 'other.$field == ${_own(field)}';
  }

  /// The field [name] of `this` inside `operator ==`, whose parameter is
  /// `other`.
  static String _own(String name) => name == 'other' ? 'this.other' : name;

  /// `toString` with every field but the constants; a secret (`writeOnly`,
  /// `format: password`) prints as `<redacted>`.
  void _toString(DartWriter out, ModelDecl model, List<FieldIr> fields) {
    final names = [
      for (final field in fields) (field.name, field.sensitive),
      if (model.additionalProperties != null)
        (model.additionalPropertiesName, model.additionalSensitive),
    ];
    final shown = [
      for (final (name, secret) in names)
        '${name.replaceAll(r'$', r'\$')}: '
            '${secret ? '<redacted>' : _code.interpolate(name)}',
    ];
    out
      ..line('@override')
      ..line(
        "String toString() => '${model.name.replaceAll(r'$', r'\$')}"
        "(${shown.join(', ')})';",
      );
  }
}
