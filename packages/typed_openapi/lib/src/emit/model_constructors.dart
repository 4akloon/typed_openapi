import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes how a model is made (decisions 3, 8 and 13 of M8): its `const`
/// constructors and its `fromJson` factory.
///
/// A field of a model sent in requests that holds an enum takes only the
/// known values in the constructor (R8.2); `fromJson`, which may meet
/// unknown ones, then uses a private constructor `_`. So does a model with
/// an optional constant: `fromJson` passes the keys of the optional
/// constants the JSON did not have ([absent]), which `toJson` leaves out,
/// so a decoded value is written back as it came (a `structural` `oneOf`
/// of overlapping branches keeps its variant); a model made in code writes
/// every constant (decision 8). So a decoded value is not equal to a model
/// made in code with the same getters when an optional constant was absent:
/// `_absent` is part of equality.
final class ModelConstructors {
  /// Creates the writer that writes with [_codec].
  const ModelConstructors(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// The private field of the keys of the optional constants that the
  /// decoded JSON did not have.
  static const absent = '_absent';

  /// Writes the constructors and `fromJson` of [model], whose fields are
  /// [fields] and whose constant fields are [constants], to [out].
  void write(
    DartWriter out,
    ModelDecl model,
    List<FieldIr> fields,
    List<FieldIr> constants,
  ) {
    final extra = model.additionalProperties;
    final known =
        model.direction != .response &&
        (fields.any((f) => _codec.hasEnum(f.type)) ||
            (extra != null && _codec.hasEnum(extra)));
    final tracks = constants.any((f) => !f.required);
    _constructors(out, model, fields, known: known, tracks: tracks);
    out.line();
    _fromJson(out, model, (fields, constants), private: known || tracks);
    if (tracks) _absentField(out);
  }

  /// Writes the public constructor of [model], and the private one `_` when
  /// it takes only [known] enum values or [tracks] optional constants.
  void _constructors(
    DartWriter out,
    ModelDecl model,
    List<FieldIr> fields, {
    required bool known,
    required bool tracks,
  }) {
    final name = model.name;
    out.prose('Creates a [$name].');
    _constructor(
      out,
      _Constructor(
        'const $name',
        initializer: tracks ? ' : $absent = const []' : '',
        isTyped: known,
      ),
      model,
      fields,
    );
    if (known || tracks) {
      out.line();
      _constructor(
        out,
        _Constructor(
          'const $name._',
          leading: tracks ? 'this.$absent' : null,
          isTyped: false,
        ),
        model,
        fields,
      );
    }
  }

  /// Writes the field [absent].
  void _absentField(DartWriter out) => out
    ..line()
    ..prose(
      'The keys of the optional constants the decoded JSON did not have, '
      'which `toJson` leaves out.',
    )
    ..line('final List<String> $absent;');

  /// Whether [type] is `JsonValue`, which is never null.
  static bool isJson(DartType type) =>
      type is CoreType && type.kind == CoreKind.json;

  /// Writes the constructor [shape] of [model], with a named parameter for
  /// each of [fields].
  void _constructor(
    DartWriter out,
    _Constructor shape,
    ModelDecl model,
    List<FieldIr> fields,
  ) {
    final typed = shape.isTyped;
    final params = [
      for (final field in fields) _parameter(field, typed: typed),
      if (model.additionalProperties case final extra?)
        '${typed && _codec.hasEnum(extra) ? '${_codec.known(MapType(extra))} ' : ''}'
            'this.${model.additionalPropertiesName} = const {}',
    ];
    final leading = shape.leading;
    if (params.isEmpty) {
      out.line('${shape.name}(${leading ?? ''})${shape.initializer};');
    } else {
      final head = '${shape.name}(${leading == null ? '' : '$leading, '}{';
      out.list(head, params, '})${shape.initializer};');
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
      constants.where((f) => f.required).map(_check).forEach(out.line);
      final optional = [
        for (final field in constants)
          if (!field.required) _check(field),
      ];
      final arguments = [
        if (optional.isNotEmpty) '[${optional.join(' ')}]',
        ..._arguments(model, fields),
      ];
      if (arguments.isEmpty) {
        out.line('return const $create();');
      } else {
        out.list('return $create(', arguments, ');');
      }
    });
  }

  /// The check of the constant [field] in `fromJson`: a statement, or for
  /// an optional one the element of [absent] it adds when the JSON lacks it.
  String _check(FieldIr field) {
    final value = _code.literal(field.constValue);
    final key = _code.string(field.jsonKey);
    return field.required
        ? 'r.constant($key, $value);'
        : 'if (!r.constant($key, $value, required: false)) $key,';
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

/// How a constructor of a model starts and ends: its name, the positional
/// parameter before the named ones, and its initializer list.
final class _Constructor {
  /// A constructor called [name] (with `const`, and the `_` of a private
  /// one); [isTyped] says its enum parameters take the known values only.
  const _Constructor(
    this.name, {
    required this.isTyped,
    this.leading,
    this.initializer = '',
  });

  final String name;

  /// The positional parameter before the named ones, or null.
  final String? leading;

  /// The initializer list, with its leading space and colon, or empty.
  final String initializer;

  final bool isTyped;
}
