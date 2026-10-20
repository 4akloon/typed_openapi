import '../diagnostics/json_pointer.dart';
import '../overrides/override_set.dart';
import 'config_keys.dart';
import 'config_reader.dart';
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
    final errorSchema = _string('errors', 'default_schema');
    final operations = OperationSettingsReader(_sources, _reader.invalid);
    final types = TypeSettingsReader(_sources, _reader.invalid);
    return GenerationConfig(
      groupTemplate:
          naming.groupTemplate() ?? GenerationConfig.defaultGroupTemplate,
      defaultGroup:
          naming.defaultGroup() ?? GenerationConfig.defaultDefaultGroup,
      inputSuffix: suffixes.$1,
      patchSuffix: suffixes.$2,
      operationPrefix: operations.operationPrefix(),
      streamSuffix: operations.streamSuffix(),
      streamReconnect: operations.streamReconnect(),
      clientClass: naming.clientClass(),
      groupBy: _choice('group_by', GroupBy.values) ?? .tag,
      include: _filters.read('include'),
      exclude: _filters.read('exclude'),
      numberType: types.numberType(),
      formats: _customTypes.read('formats'),
      schemas: _customTypes.read('schemas'),
      triState: _choice('tri_state', TriStateRule.values) ?? .patch,
      union: _choice('union', UnionMode.values) ?? .raw,
      exhaustive: types.exhaustive(),
      defaultErrorSchema: errorSchema?.$1,
      defaultErrorSchemaPointer: errorSchema?.$2,
      defaultErrorSchemaSpan: errorSchema == null
          ? null
          : _reader.spanAt(errorSchema.$2),
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

  (String, JsonPointer)? _string(String section, String key) {
    final picked = _sources.pick(key, section);
    if (picked == null) return null;
    final (value, at) = picked;
    if (value is String && value.isNotEmpty) return (value, at);
    return _invalid('"$key" must be a non-empty string.', at);
  }

  T? _choice<T extends Enum>(String key, List<T> values) {
    final picked = _sources.pick(key);
    if (picked == null) return null;
    final (value, at) = picked;
    for (final choice in values) {
      if (value == choice.name) return choice;
    }
    return _invalid(
      '"$key" must be one of ${values.map((v) => v.name).join(', ')}.',
      at,
    );
  }

  /// Reports an invalid value at [at]; returns null.
  Null _invalid(String message, JsonPointer at) {
    _reader.invalid(message, at);
    return null;
  }
}
