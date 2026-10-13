import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes how a model is made (decisions 3, 8 and 13 of M8): its `const`
/// constructors and its `fromJson` factory.
///
/// A field of a model sent in requests that holds an enum takes only the
/// known values in the constructor (R8.2); `fromJson`, which may meet
/// unknown ones, then uses a private constructor `_`.
final class ModelConstructors {
  /// Creates the writer that writes with [_codec].
  const ModelConstructors(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes the constructors and `fromJson` of [model], whose fields are
  /// [fields] and whose constant fields are [constants], to [out].
  void write(
    DartWriter out,
    ModelDecl model,
    List<FieldIr> fields,
    List<FieldIr> constants,
  ) {
    final name = model.name;
    final extra = model.additionalProperties;
    final known =
        model.direction != .response &&
        (fields.any((f) => _codec.hasEnum(f.type)) ||
            (extra != null && _codec.hasEnum(extra)));
    out.prose('Creates a [$name].');
    _constructor(out, 'const $name', model, fields, typed: known);
    if (known) {
      out.line();
      _constructor(out, 'const $name._', model, fields, typed: false);
    }
    out.line();
    _fromJson(out, model, (fields, constants), private: known);
  }

  /// Whether [type] is `JsonValue`, which is never null.
  static bool isJson(DartType type) =>
      type is CoreType && type.kind == CoreKind.json;

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
    if (isJson(type)) {
      _codec.imports.fromRuntime('JsonValue');
      return '${declared}this.${field.name} = const JsonValue(null)';
    }
    return '${declared}this.${field.name}';
  }

  /// Writes `fromJson`; [split] is the fields and the constant fields.
  void _fromJson(
    DartWriter out,
    ModelDecl model,
    (List<FieldIr>, List<FieldIr>) split, {
    required bool private,
  }) {
    final (fields, constants) = split;
    final name = model.name;
    final create = private ? '$name._' : name;
    out.prose(
      'Decodes a [$name] from [json]; throws a `JsonDecodeException` '
      'when it does not match the schema.',
    );
    final head = 'factory $name.fromJson(Map<String, Object?> json)';
    if (fields.isEmpty &&
        constants.isEmpty &&
        model.additionalProperties == null) {
      out.line('$head => const $create();');
      return;
    }
    _codec.imports.fromRuntime('JsonReader');
    out.block(head, () {
      out.line('final r = JsonReader(json, schema: ${_code.string(name)});');
      constants.map(_check).forEach(out.line);
      final arguments = _arguments(model, fields);
      if (arguments.isEmpty) {
        out.line('return const $create();');
      } else {
        out.list('return $create(', arguments, ');');
      }
    });
  }

  /// The statement of `fromJson` that checks the constant [field].
  String _check(FieldIr field) {
    final value = _code.literal(field.constValue);
    return field.required
        ? 'r.constant(${_code.string(field.jsonKey)}, $value);'
        : 'r.constant(${_code.string(field.jsonKey)}, $value, '
              'required: false);';
  }

  /// The named arguments of the constructor `fromJson` calls.
  List<String> _arguments(ModelDecl model, List<FieldIr> fields) => [
    for (final field in fields) '${field.name}: ${_read(field)}',
    if (model.additionalProperties case final extra?)
      '${model.additionalPropertiesName}: r.additional(${_known(model)}, '
          '${_item(extra)})',
  ];

  /// The set of the JSON keys of [model]'s properties, as a constant.
  String _known(ModelDecl model) {
    final keys = [for (final f in model.fields) _code.string(f.jsonKey)];
    return 'const {${keys.join(', ')}}';
  }

  String _item(DartType type) => type.nullable && !isJson(type)
      ? 'JsonReader.nullable(${_codec.decoder(type)})'
      : _codec.decoder(type);

  String _read(FieldIr field) {
    final key = _code.string(field.jsonKey);
    final value = field.valueType;
    if (field.triState) {
      if (isJson(value)) return 'r.patchValue($key)';
      return 'r.patch($key, ${_codec.decoder(value.withNullable(false))})';
    }
    if (isJson(value)) {
      return field.required ? 'r.requiredValue($key)' : 'r.optionalValue($key)';
    }
    final decoder = _codec.decoder(value.withNullable(false));
    if (!field.required) return 'r.optional($key, $decoder)';
    return value.nullable
        ? 'r.requiredNullable($key, $decoder)'
        : 'r.required($key, $decoder)';
  }
}
