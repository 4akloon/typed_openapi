import '../diagnostics/json_pointer.dart';
import 'config_sources.dart';
import 'generation_config.dart';

/// Reads the settings of how a client's operations are generated:
/// `naming.operation_prefix`, `naming.stream_suffix` and `sse.reconnect`,
/// each from the last source that has it (`defaults` first). A bad value
/// is reported through the `invalid` function (TOA902) and the default is
/// used.
final class OperationSettingsReader {
  /// Creates a reader of [_sources] that reports through [_invalid].
  const OperationSettingsReader(this._sources, this._invalid);

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  /// A suffix that keeps a lowerCamelCase method name lowerCamelCase.
  static final _suffix = RegExp(r'^[A-Z0-9][A-Za-z0-9]*$');

  /// `naming.operation_prefix`: what is removed from the start of an
  /// `operationId`; null when not set or not a valid regular expression.
  RegExp? operationPrefix() {
    final picked = _sources.pick('operation_prefix', 'naming');
    if (picked == null) return null;
    final (value, at) = picked;
    if (value is! String || value.isEmpty) {
      _invalid('"operation_prefix" must be a non-empty string.', at);
      return null;
    }
    try {
      return RegExp(value);
    } on FormatException catch (e) {
      _invalid(
        '"operation_prefix" is not a valid regular expression: '
        '${e.message}.',
        at,
      );
      return null;
    }
  }

  /// `naming.stream_suffix`: what the name of the event-stream method of an
  /// operation that also returns JSON ends with.
  String streamSuffix() {
    final picked = _sources.pick('stream_suffix', 'naming');
    if (picked == null) return GenerationConfig.defaultStreamSuffix;
    final (value, at) = picked;
    if (value is String && _suffix.hasMatch(value)) return value;
    _invalid(
      '"stream_suffix" must be letters and digits that start with an '
      'uppercase letter or a digit, such as Stream; '
      '${GenerationConfig.defaultStreamSuffix} is used.',
      at,
    );
    return GenerationConfig.defaultStreamSuffix;
  }

  /// `sse.reconnect`: whether the event streams of GET operations
  /// reconnect unless a call says no.
  bool streamReconnect() {
    final picked = _sources.pick('reconnect', 'sse');
    if (picked == null) return false;
    final (value, at) = picked;
    if (value is bool) return value;
    _invalid('"reconnect" must be true or false.', at);
    return false;
  }
}
