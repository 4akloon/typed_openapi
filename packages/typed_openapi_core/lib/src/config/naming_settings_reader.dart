import '../diagnostics/json_pointer.dart';
import '../ir/names.dart';
import 'config_reading.dart';
import 'config_sources.dart';
import 'generation_config.dart';

/// Reads the class-name settings of `naming`: `group`, `default_group`,
/// `client`, `input_suffix` and `patch_suffix`, each from the last source
/// whose value is usable (`defaults` first). A bad value is reported through
/// the `invalid` function (TOA902) and the next source is tried.
final class NamingSettingsReader {
  /// Creates a reader of [_sources] that reports through [_invalid].
  const NamingSettingsReader(this._sources, this._invalid);

  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  /// `group`: the template of a group class name, with `{Tag}`.
  String groupTemplate() => _resolve(
    'group',
    GenerationConfig.defaultGroupTemplate,
    (value) {
      if (value is! String || value.isEmpty) {
        return const InvalidValue('"group" must be a non-empty string.');
      }
      final probe = value.replaceAll('{Tag}', 'Tag');
      if (value.contains('{Tag}') && _identifier.hasMatch(probe)) {
        return ValidValue(value);
      }
      return const InvalidValue(
        '"group" must contain {Tag} and give a Dart identifier, such as '
        '{Tag}Api.',
      );
    },
  );

  /// `default_group` is the name of a class, so a reserved word or a
  /// built-in identifier cannot be it.
  String defaultGroup() => _resolve(
    'default_group',
    GenerationConfig.defaultDefaultGroup,
    (value) {
      switch (_identifierOf('default_group', value)) {
        case final InvalidValue<String> invalid:
          return invalid;
        case ValidValue<String>(value: final name):
          if (!_isReserved(name)) return ValidValue(name);
          return InvalidValue(
            '"default_group" is the name of a class and "$name" is a '
            'reserved word in Dart.',
          );
      }
    },
  );

  /// `client` is the name of a class, as `default_group` is; null when not
  /// set, and the name is made from the client's.
  String? clientClass() => _sources
      .resolve<String?>(
        'client',
        section: 'naming',
        builtIn: null,
        show: (name) => name ?? 'the client name with Client',
        report: _invalid,
        read: _clientName,
      )
      .value;

  ConfigReading<String?> _clientName(Object? value) {
    switch (_identifierOf('client', value)) {
      case InvalidValue<String>(:final problem):
        return InvalidValue(problem);
      case ValidValue<String>(value: final name):
        if (!_isReserved(name) && name.startsWith(RegExp(r'[A-Z$]'))) {
          return ValidValue(name);
        }
        return const InvalidValue(
          '"client" is the name of a class: an identifier that starts with '
          'an uppercase letter and is not a reserved word in Dart.',
        );
    }
  }

  /// `input_suffix` and `patch_suffix`: two model names made from one schema
  /// must differ, so equal suffixes are an error, reported at the later
  /// key, and both go back to their defaults.
  (String, String) suffixes() {
    final input = _suffix('input_suffix', GenerationConfig.defaultInputSuffix);
    final patch = _suffix('patch_suffix', GenerationConfig.defaultPatchSuffix);
    if (input.value != patch.value) return (input.value, patch.value);
    final at = patch.at ?? input.at;
    if (at != null) {
      _invalid(
        '"input_suffix" and "patch_suffix" must be different, both are '
        '"${input.value}"; the defaults '
        '${GenerationConfig.defaultInputSuffix} and '
        '${GenerationConfig.defaultPatchSuffix} are used.',
        at,
      );
    }
    return (
      GenerationConfig.defaultInputSuffix,
      GenerationConfig.defaultPatchSuffix,
    );
  }

  ({String value, JsonPointer? at}) _suffix(String key, String builtIn) =>
      _resolveAt(key, builtIn, (value) => _identifierOf(key, value));

  String _resolve(
    String key,
    String builtIn,
    ConfigReading<String> Function(Object?) read,
  ) => _resolveAt(key, builtIn, read).value;

  ({String value, JsonPointer? at}) _resolveAt(
    String key,
    String builtIn,
    ConfigReading<String> Function(Object?) read,
  ) => _sources.resolve<String>(
    key,
    section: 'naming',
    builtIn: builtIn,
    report: _invalid,
    read: read,
  );

  ConfigReading<String> _identifierOf(String key, Object? value) {
    if (value is String && _identifier.hasMatch(value)) {
      return ValidValue(value);
    }
    return InvalidValue('"$key" must be a Dart identifier.');
  }

  bool _isReserved(String name) =>
      DartNames.reservedWords.contains(name) ||
      DartNames.builtInIdentifiers.contains(name);
}
