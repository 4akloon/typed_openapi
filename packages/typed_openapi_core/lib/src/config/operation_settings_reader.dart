import '../diagnostics/json_pointer.dart';
import 'config_reading.dart';
import 'config_sources.dart';
import 'generation_config.dart';

/// Reads the settings of how a client's operations are generated:
/// `naming.operation_prefix`, `naming.stream_suffix` and `sse.reconnect`,
/// each from the last source that has it (`defaults` first). A bad value
/// is reported through the `invalid` function (TOA902) and the next source
/// is tried.
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
  RegExp? operationPrefix() => _sources
      .resolve<RegExp?>(
        'operation_prefix',
        section: 'naming',
        builtIn: null,
        show: (prefix) => prefix?.pattern ?? 'none',
        report: _invalid,
        read: _prefix,
      )
      .value;

  ConfigReading<RegExp?> _prefix(Object? value) {
    if (value is! String || value.isEmpty) {
      return const InvalidValue(
        '"operation_prefix" must be a non-empty string.',
      );
    }
    try {
      return ValidValue(RegExp(value));
    } on FormatException catch (e) {
      return InvalidValue(
        '"operation_prefix" is not a valid regular expression: '
        '${e.message}.',
      );
    }
  }

  /// `naming.stream_suffix`: what the name of the event-stream method of an
  /// operation that also returns JSON ends with.
  String streamSuffix() => _sources
      .resolve<String>(
        'stream_suffix',
        section: 'naming',
        builtIn: GenerationConfig.defaultStreamSuffix,
        report: _invalid,
        read: (value) => value is String && _suffix.hasMatch(value)
            ? ValidValue(value)
            : const InvalidValue(
                '"stream_suffix" must be letters and digits that start with '
                'an uppercase letter or a digit, such as Stream.',
              ),
      )
      .value;

  /// `sse.reconnect`: whether the event streams of GET operations
  /// reconnect unless a call says no.
  bool streamReconnect() => _sources
      .resolve<bool>(
        'reconnect',
        section: 'sse',
        builtIn: false,
        report: _invalid,
        read: (value) => value is bool
            ? ValidValue(value)
            : const InvalidValue('"reconnect" must be true or false.'),
      )
      .value;
}
