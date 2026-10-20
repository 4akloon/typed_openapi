import 'package:typed_openapi_core/typed_openapi_core.dart';
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

  /// How the client reads the body of every status: by the successes' media
  /// types; errors of a text or binary operation are parsed from it. A
  /// binary error makes the whole operation bytes, since the client would
  /// turn the bytes of a JSON operation into text.
  static String responseKind(OperationIr operation) {
    // An event stream reads its body itself, and its error bodies parsed.
    if (operation.events != null) return 'json';
    if (operation.responses.any((r) => r.isError && r.kind == .bytes)) {
      return 'bytes';
    }
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

  /// The success type `T` of [operation]: its sealed type, the stream of
  /// its events, the one body type, `void` without a body, `JsonValue`
  /// without a 2xx (TOA653).
  String successType(OperationIr operation) {
    if (operation.successType case final sealed?) return sealed.name;
    if (operation.events case final events?) {
      _codec.imports.fromRuntime('SseItem');
      final data = events.data;
      final item = switch (events.union) {
        final union? => union.name,
        null when data != null => _codec.type(data),
        null => 'String',
      };
      return 'Stream<SseItem<$item>>';
    }
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
            // The stream opens for a success before this decoder is asked.
            if (operation.events == null) ..._successArms(operation, json),
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
      case SingleError(:final type, :final statuses) when statuses.isEmpty:
        return ['>= 400 && < 600 => r.error(${decode(type, json)}),'];
      case SingleError(:final type, :final statuses):
        return _singleErrorArms(operation, type, statuses, json);
      case ErrorsByStatus():
        final sealed = operation.errorType!;
        return [
          for (final c in _ordered(sealed.cases, (c) => c.status))
            '${_pattern(c.status)} => r.error(${_wrap(c.name, c.type == null ? null : _errorValue(operation, c.status, c.type!, json))}),',
        ];
    }
  }

  /// The arms of errors that share one body type: one arm for all
  /// statuses when they decode the same way, else an arm for each (a
  /// `text/plain` and a JSON string are both a `String`).
  List<String> _singleErrorArms(
    OperationIr operation,
    DartType type,
    List<String> statuses,
    String json,
  ) {
    final ordered = _ordered(statuses, (s) => s);
    final values = {
      for (final s in ordered) s: _errorValue(operation, s, type, json),
    };
    if (values.values.toSet().length > 1) {
      return [
        for (final MapEntry(key: status, value: value) in values.entries)
          '${_pattern(status)} => r.error($value),',
      ];
    }
    final patterns = [for (final s in ordered) _pattern(s)];
    final pattern = patterns.length == 1
        ? patterns.single
        : patterns.map((p) => p.contains(' ') ? '($p)' : p).join(' || ');
    return ['$pattern => r.error(${values.values.first}),'];
  }

  /// The decoded body of the error [status] of [type], read by the media
  /// type of its response: text and bytes as they are, JSON by its type.
  String _errorValue(
    OperationIr operation,
    String status,
    DartType type,
    String json,
  ) {
    final response = operation.responses
        .where((r) => r.isError && r.status == status)
        .firstOrNull;
    return switch (response?.kind) {
      .text || .eventStream => 'r.text',
      .bytes => 'r.bytes',
      _ => decode(type, json),
    };
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
      _ => decode(type, json),
    };
  }

  /// The code that decodes [json] as [type].
  String decode(DartType type, String json) {
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
