import '../diagnostics/json_pointer.dart';
import '../ir/names.dart';
import '../overrides/override_set.dart';
import 'config_keys.dart';
import 'config_reader.dart';
import 'config_sources.dart';
import 'custom_types_reader.dart';
import 'generation_config.dart';
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

  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  final ConfigReader _reader;

  /// The maps to read, `defaults` first.
  final ConfigSources _sources;

  /// The settings, with the defaults where a value is missing or bad.
  GenerationConfig read() {
    _checkSectionKeys();
    final suffixes = _suffixes();
    final client = _sources.last.$2;
    final errorSchema = _string('errors', 'default_schema');
    final operations = OperationSettingsReader(_sources, _reader.invalid);
    return GenerationConfig(
      groupTemplate: _groupTemplate() ?? GenerationConfig.defaultGroupTemplate,
      defaultGroup: _defaultGroup() ?? GenerationConfig.defaultDefaultGroup,
      inputSuffix: suffixes.$1,
      patchSuffix: suffixes.$2,
      operationPrefix: operations.operationPrefix(),
      streamSuffix: operations.streamSuffix(),
      streamReconnect: operations.streamReconnect(),
      clientClass: _clientClass(),
      groupBy: _choice('group_by', GroupBy.values) ?? .tag,
      include: _filters.read('include'),
      exclude: _filters.read('exclude'),
      numberType: TypeSettingsReader(_sources, _reader.invalid).numberType(),
      formats: _customTypes.read('formats'),
      schemas: _customTypes.read('schemas'),
      triState: _choice('tri_state', TriStateRule.values) ?? .patch,
      union: _choice('union', UnionMode.values) ?? .raw,
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

  String? _groupTemplate() {
    final picked = _string('naming', 'group');
    if (picked == null) return null;
    final (value, at) = picked;
    final probe = value.replaceAll('{Tag}', 'Tag');
    if (value.contains('{Tag}') && _identifier.hasMatch(probe)) return value;
    return _invalid(
      '"group" must contain {Tag} and give a Dart identifier, such as '
      '{Tag}Api.',
      at,
    );
  }

  String? _identifierAt(String key) {
    final picked = _sources.pick(key, 'naming');
    if (picked == null) return null;
    final (value, at) = picked;
    if (value is String && _identifier.hasMatch(value)) return value;
    return _invalid('"$key" must be a Dart identifier.', at);
  }

  /// `default_group` is the name of a class, so a reserved word or a
  /// built-in identifier cannot be it.
  String? _defaultGroup() {
    final name = _identifierAt('default_group');
    if (name == null) return null;
    if (!DartNames.reservedWords.contains(name) &&
        !DartNames.builtInIdentifiers.contains(name)) {
      return name;
    }
    return _invalid(
      '"default_group" is the name of a class and "$name" is a reserved word '
      'in Dart.',
      _sources.pick('default_group', 'naming')!.$2,
    );
  }

  /// `client` is the name of a class, as `default_group` is.
  String? _clientClass() {
    final name = _identifierAt('client');
    if (name == null) return null;
    if (!DartNames.reservedWords.contains(name) &&
        !DartNames.builtInIdentifiers.contains(name) &&
        name.startsWith(RegExp(r'[A-Z$]'))) {
      return name;
    }
    return _invalid(
      '"client" is the name of a class: an identifier that starts with an '
      'uppercase letter and is not a reserved word in Dart.',
      _sources.pick('client', 'naming')!.$2,
    );
  }

  /// `input_suffix` and `patch_suffix`: two model names made from one schema
  /// must differ, so equal suffixes are an error, reported at the later
  /// key, and both go back to their defaults.
  (String, String) _suffixes() {
    final input = _identifierAt('input_suffix');
    final patch = _identifierAt('patch_suffix');
    final inputSuffix = input ?? GenerationConfig.defaultInputSuffix;
    final patchSuffix = patch ?? GenerationConfig.defaultPatchSuffix;
    if (inputSuffix != patchSuffix) return (inputSuffix, patchSuffix);
    final at = patch != null
        ? _sources.pick('patch_suffix', 'naming')!.$2
        : _sources.pick('input_suffix', 'naming')!.$2;
    _invalid(
      '"input_suffix" and "patch_suffix" must be different, both are '
      '"$inputSuffix"; the defaults ${GenerationConfig.defaultInputSuffix} '
      'and ${GenerationConfig.defaultPatchSuffix} are used.',
      at,
    );
    return (
      GenerationConfig.defaultInputSuffix,
      GenerationConfig.defaultPatchSuffix,
    );
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
