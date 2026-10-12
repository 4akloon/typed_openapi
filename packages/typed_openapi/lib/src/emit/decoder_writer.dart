import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the decoder of an operation (R10.6, R11): a `switch` on the status
/// that decodes successes and errors, and the types of both.
final class DecoderWriter {
  /// Creates a writer that writes with [_codec].
  const DecoderWriter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// How Dio reads the body of every status: by the successes' media
  /// types; errors of a text or binary operation are parsed from it.
  static String responseKind(OperationIr operation) {
    final kinds = {
      for (final s in operation.successes)
        if (s.kind != .none) s.kind,
    };
    if (kinds.isEmpty || (kinds.length == 1 && kinds.single == .json)) {
      return 'json';
    }
    if (kinds.length == 1 && kinds.single == .text) return 'text';
    return 'bytes';
  }

  /// The success type `T` of [operation]: its sealed type, the one body
  /// type, `void` without a body, `JsonValue` without a 2xx (TOA653).
  String successType(OperationIr operation) {
    if (operation.successType case final sealed?) return sealed.name;
    final successes = operation.successes;
    if (successes.isEmpty) {
      _codec.imports.fromRuntime('JsonValue');
      return 'JsonValue';
    }
    final type = successes.first.type;
    return type == null ? 'void' : _codec.type(type);
  }

  /// The error type `E` of [operation]: `Never`, the one body type or the
  /// sealed type of its errors.
  String errorType(OperationIr operation) => switch (operation.errors) {
    NoErrors() => 'Never',
    SingleError(:final type) => _codec.type(type),
    ErrorsByStatus() => operation.errorType!.name,
  };

  /// Writes the static method [decoder] of [operation]: a `switch` on
  /// the status, `undocumented()` for any status it does not name.
  void write(DartWriter out, OperationIr operation, String decoder) {
    _codec.imports.fromRuntime('RawResponse');
    final result = 'Result<${successType(operation)}, ${errorType(operation)}>';
    final json = responseKind(operation) == 'json' ? 'r.json' : 'r.parsedJson';
    out.line('static $result $decoder(RawResponse r) =>');
    out.indented(() {
      out.indented(() {
        out.line('switch (r.statusCode) {');
        out.indented(() {
          for (final arm in [
            ..._successArms(operation, json),
            ..._errorArms(operation, json),
          ]) {
            out.line(arm);
          }
          out.line('_ => r.undocumented(),');
        });
        out.line('};');
      });
    });
  }

  List<String> _successArms(OperationIr operation, String json) {
    final successes = operation.successes;
    if (successes.isEmpty) {
      return ['>= 200 && < 300 => r.success(JsonValue($json)),'];
    }
    final sealed = operation.successType;
    final names = {
      for (final c in [...?sealed?.cases]) c.status: c.name,
    };
    return [
      for (final response in _ordered(successes, (r) => r.status))
        '${_pattern(response.status)} => r.success('
            '${_wrap(names[response.status], _value(response, json))}),',
    ];
  }

  List<String> _errorArms(OperationIr operation, String json) {
    switch (operation.errors) {
      case NoErrors():
        return const [];
      case SingleError(:final type, :final statuses):
        final patterns = statuses.isEmpty
            ? ['>= 400 && < 600']
            : [for (final s in _ordered(statuses, (s) => s)) _pattern(s)];
        final pattern = patterns.length == 1
            ? patterns.single
            : patterns.map((p) => p.contains(' ') ? '($p)' : p).join(' || ');
        return ['$pattern => r.error(${_decode(type, json)}),'];
      case ErrorsByStatus():
        final sealed = operation.errorType!;
        return [
          for (final c in _ordered(sealed.cases, (c) => c.status))
            '${_pattern(c.status)} => r.error(${_wrap(c.name, c.type == null ? null : _decode(c.type!, json))}),',
        ];
    }
  }

  /// [items] by status: codes first, then ranges, then `default`, each in
  /// the spec's order, so a code wins over its range.
  static List<T> _ordered<T>(List<T> items, String Function(T) status) {
    int rank(String s) => s == 'default'
        ? 2
        : int.tryParse(s) == null
        ? 1
        : 0;
    final indexed = items.indexed.toList()
      ..sort((a, b) {
        final byRank = rank(status(a.$2)).compareTo(rank(status(b.$2)));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final (_, item) in indexed) item];
  }

  /// The pattern of the status codes [status] stands for: a code, a range
  /// (`4XX`), or for `default` every status but 2xx (an undocumented 2xx is
  /// not an error).
  static String _pattern(String status) {
    if (status == 'default') return '< 200 || >= 300';
    final code = int.tryParse(status);
    if (code != null) return '$code';
    final hundred = int.parse(status[0]) * 100;
    return '>= $hundred && < ${hundred + 100}';
  }

  /// [value] in the variant [name] of a sealed type, or as it is.
  static String _wrap(String? name, String? value) => switch ((name, value)) {
    (null, final value?) => value,
    (null, null) => 'null',
    (final name?, null) => 'const $name()',
    (final name?, final value?) => '$name($value)',
  };

  /// The decoded body of a success, or null without one.
  String? _value(ResponseIr response, String json) {
    final type = response.type;
    if (type == null) return null;
    return switch (response.kind) {
      .text => 'r.text',
      .bytes => 'r.bytes',
      _ when response.envelopeKey != null => _envelope(
        type,
        response.envelopeKey!,
        json,
      ),
      _ => _decode(type, json),
    };
  }

  String _decode(DartType type, String json) {
    final code = type.nullable
        ? 'JsonReader.nullable(${_codec.decoder(type.withNullable(false))})'
              '($json)'
        : _codec.decodeValue(type, json);
    if (code.contains('JsonReader.')) _codec.imports.fromRuntime('JsonReader');
    return code;
  }

  String _envelope(DartType type, String key, String json) {
    _codec.imports.fromRuntime('JsonReader');
    final reader =
        "JsonReader.of($json, schema: 'envelope').${switch (type) {
          CoreType(kind: .json) => 'requiredValue(${_code.string(key)})',
          _ when type.nullable => 'requiredNullable(${_code.string(key)}, '
              '${_codec.decoder(type.withNullable(false))})',
          _ => 'required(${_code.string(key)}, ${_codec.decoder(type)})',
        }}";
    return reader;
  }
}
