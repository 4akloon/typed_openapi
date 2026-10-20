import '../diagnostics/json_pointer.dart';
import '../overrides/override_set.dart';
import 'config_keys.dart';
import 'config_reader.dart';
import 'config_reading.dart';
import 'config_sources.dart';
import 'custom_types_reader.dart';
import 'generation_config.dart';
import 'naming_settings_reader.dart';
import 'operation_filter_reader.dart';
import 'operation_settings_reader.dart';
import 'type_settings_reader.dart';

/// Reads the generation settings of a client: each key from the client, or
/// from `defaults` when the client does not set it; `naming`, `types` and
/// `errors` key by key, and `types.formats` and `types.schemas` entry by
/// entry.
final class GenerationReader {
  /// Creates a reader of [sources], `defaults` first, that reports through
  /// [_reader].
  GenerationReader(
    this._reader,
    List<(Map<String, Object?>, JsonPointer)> sources,
  ) : _sources = ConfigSources(sources);

  final ConfigReader _reader;

  /// The maps to read, `defaults` first.
  final ConfigSources _sources;

  /// The settings, with the defaults where a value is missing or bad.
  GenerationConfig read() {
    _checkSectionKeys();
    final naming = NamingSettingsReader(_sources, _reader.invalid);
    final suffixes = naming.suffixes();
    final client = _sources.last.$2;
    final errorSchema = _errorSchema();
    final operations = OperationSettingsReader(_sources, _reader.invalid);
    final types = TypeSettingsReader(_sources, _reader.invalid);
    return GenerationConfig(
      groupTemplate: naming.groupTemplate(),
      defaultGroup: naming.defaultGroup(),
      inputSuffix: suffixes.$1,
      patchSuffix: suffixes.$2,
      operationPrefix: operations.operationPrefix(),
      streamSuffix: operations.streamSuffix(),
      streamReconnect: operations.streamReconnect(),
      clientClass: naming.clientClass(),
      groupBy: _choice('group_by', GroupBy.values, .tag),
      include: _filters.read('include'),
      exclude: _filters.read('exclude'),
      numberType: types.numberType(),
      formats: _customTypes.read('formats'),
      schemas: _customTypes.read('schemas'),
      triState: _choice('tri_state', TriStateRule.values, .patch),
      union: _choice('union', UnionMode.values, .raw),
      exhaustive: types.exhaustive(),
      defaultErrorSchema: errorSchema.value,
      defaultErrorSchemaPointer: errorSchema.at,
      defaultErrorSchemaSpan: switch (errorSchema.at) {
        final at? => _reader.spanAt(at),
        null => null,
      },
      file: _reader.file,
      client: client,
      clientSpan: _reader.spanAt(client),
    );
  }

  CustomTypesReader get _customTypes =>
      CustomTypesReader(_sources, _reader.invalid, _reader.checkKeys);

  OperationFilterReader get _filters => OperationFilterReader(
    _sources,
    _reader.invalid,
    _reader.checkKeys,
    _reader.spanAt,
  );

  void _checkSectionKeys() {
    for (final (map, at) in _sources) {
      for (final (section, keys) in [
        ('naming', ConfigKeys.naming),
        ('types', ConfigKeys.types),
        ('errors', const {'default_schema'}),
        ('sse', const {'reconnect'}),
      ]) {
        if (_reader.mapAt(map, section, at) case final inner?) {
          _reader.checkKeys(inner, keys, at.child(section));
        }
      }
    }
  }

  T _choice<T extends Enum>(String key, List<T> values, T builtIn) => _sources
      .resolve<T>(
        key,
        builtIn: builtIn,
        show: (choice) => choice.name,
        report: _reader.invalid,
        read: (value) {
          for (final choice in values) {
            if (value == choice.name) return ValidValue(choice);
          }
          return InvalidValue(
            '"$key" must be one of '
            '${values.map((v) => v.name).join(', ')}.',
          );
        },
      )
      .value;

  /// `errors.default_schema`: the component schema for statuses without a
  /// body, with its pointer; null when not set.
  ({String? value, JsonPointer? at}) _errorSchema() =>
      _sources.resolve<String?>(
        'default_schema',
        section: 'errors',
        builtIn: null,
        show: (name) => name ?? 'none',
        report: _reader.invalid,
        read: (value) => value is String && value.isNotEmpty
            ? ValidValue(value)
            : const InvalidValue(
                '"default_schema" must be a non-empty string.',
              ),
      );
}
