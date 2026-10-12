import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the class of a [ModelDecl] (decisions 3, 4, 8, 10–13 of M8): a
/// `class` with a `const` constructor, `fromJson`, `toJson`, deep
/// `==` and `hashCode`, and `toString`.
///
/// A field of a model sent in requests that holds an enum takes only the
/// known values in the constructor (R8.2); `fromJson`, which may meet
/// unknown ones, then uses a private constructor `_`.
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
    final known =
        model.direction != .response &&
        (fields.any((f) => _codec.hasEnum(f.type)) ||
            (extra != null && _codec.hasEnum(extra)));
    _codec.imports.fromRuntime('immutable');
    out.doc(model.description);
    if (model.deprecated) out.line(deprecation);
    out
      ..line('@immutable')
      ..block('class $name', () {
        out.prose('Creates a [$name].');
        _constructor(out, 'const $name', model, fields, typed: known);
        if (known) {
          out.line();
          _constructor(out, 'const $name._', model, fields, typed: false);
        }
        out.line();
        _fromJson(out, model, fields, constants, private: known);
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

  void _constructor(
    DartWriter out,
    String head,
    ModelDecl model,
    List<FieldIr> fields, {
    required bool typed,
  }) {
    final params = [
      for (final field in fields) _parameter(field, typed: typed),
      if (model.additionalProperties case final extra?)
        '${typed && _codec.hasEnum(extra) ? '${_codec.known(MapType(extra))} ' : ''}'
            'this.${model.additionalPropertiesName} = const {}',
    ];
    if (params.isEmpty) {
      out.line('$head();');
    } else {
      out.list('$head({', params, '});');
    }
  }

  String _parameter(FieldIr field, {required bool typed}) {
    final type = field.type;
    final declared = typed && _codec.hasEnum(type)
        ? '${_codec.known(type)} '
        : '';
    if (field.required) return 'required ${declared}this.${field.name}';
    if (_isJson(type)) {
      _codec.imports.fromRuntime('JsonValue');
      return '${declared}this.${field.name} = const JsonValue(null)';
    }
    return '${declared}this.${field.name}';
  }

  void _fromJson(
    DartWriter out,
    ModelDecl model,
    List<FieldIr> fields,
    List<FieldIr> constants, {
    required bool private,
  }) {
    final name = model.name;
    final create = private ? '$name._' : name;
    out.prose(
      'Decodes a [$name] from [json]; throws a `JsonDecodeException` '
      'when it does not match the schema.',
    );
    final head = 'factory $name.fromJson(Map<String, Object?> json)';
    final extra = model.additionalProperties;
    if (fields.isEmpty && constants.isEmpty && extra == null) {
      out.line('$head => const $create();');
      return;
    }
    _codec.imports.fromRuntime('JsonReader');
    out.block(head, () {
      out.line(
        'final r = JsonReader(json, schema: ${_code.string(name)});',
      );
      for (final field in constants) {
        final value = _code.literal(field.constValue);
        out.line(
          field.required
              ? 'r.constant(${_code.string(field.jsonKey)}, $value);'
              : 'r.constant(${_code.string(field.jsonKey)}, $value, '
                    'required: false);',
        );
      }
      final arguments = [
        for (final field in fields) '${field.name}: ${_read(field)}',
        if (extra != null)
          '${model.additionalPropertiesName}: r.additional(${_known(model)}, '
              '${_item(extra)})',
      ];
      if (arguments.isEmpty) {
        out.line('return const $create();');
      } else {
        out.list('return $create(', arguments, ');');
      }
    });
  }

  /// The set of the JSON keys of [model]'s properties, as a constant.
  String _known(ModelDecl model) {
    final keys = [for (final f in model.fields) _code.string(f.jsonKey)];
    return 'const {${keys.join(', ')}}';
  }

  String _item(DartType type) => type.nullable && !_isJson(type)
      ? 'JsonReader.nullable(${_codec.decoder(type)})'
      : _codec.decoder(type);

  String _read(FieldIr field) {
    final key = _code.string(field.jsonKey);
    final value = field.valueType;
    if (field.triState) {
      if (_isJson(value)) return 'r.patchValue($key)';
      return 'r.patch($key, ${_codec.decoder(value.withNullable(false))})';
    }
    if (_isJson(value)) {
      return field.required ? 'r.requiredValue($key)' : 'r.optionalValue($key)';
    }
    final decoder = _codec.decoder(value.withNullable(false));
    if (!field.required) return 'r.optional($key, $decoder)';
    return value.nullable
        ? 'r.requiredNullable($key, $decoder)'
        : 'r.required($key, $decoder)';
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
        entries.add('$key: ${_code.literal(field.constValue)}');
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
    if (_isJson(type)) return '$key: ?$name.raw';
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

  static bool _isJson(DartType type) =>
      type is CoreType && type.kind == CoreKind.json;
}
