import '../diagnostics/json_pointer.dart';
import '../ir/names.dart';
import 'config_sources.dart';
import 'generation_config.dart';

/// Reads the class-name settings of `naming`: `group`, `default_group`,
/// `client`, `input_suffix` and `patch_suffix`, each from the last source
/// that has it (`defaults` first). A bad value is reported through the
/// `invalid` function (TOA902) and left out.
final class NamingSettingsReader {
  /// Creates a reader of [_sources] that reports through [_invalid].
  const NamingSettingsReader(this._sources, this._invalid);

  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  (String, JsonPointer)? _string(String key) {
    final picked = _sources.pick(key, 'naming');
    if (picked == null) return null;
    final (value, at) = picked;
    if (value is String && value.isNotEmpty) return (value, at);
    return _report('"$key" must be a non-empty string.', at);
  }

  /// `group`: the template of a group class name, with `{Tag}`.
  String? groupTemplate() {
    final picked = _string('group');
    if (picked == null) return null;
    final (value, at) = picked;
    final probe = value.replaceAll('{Tag}', 'Tag');
    if (value.contains('{Tag}') && _identifier.hasMatch(probe)) return value;
    return _report(
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
    return _report('"$key" must be a Dart identifier.', at);
  }

  /// `default_group` is the name of a class, so a reserved word or a
  /// built-in identifier cannot be it.
  String? defaultGroup() {
    final name = _identifierAt('default_group');
    if (name == null) return null;
    if (!DartNames.reservedWords.contains(name) &&
        !DartNames.builtInIdentifiers.contains(name)) {
      return name;
    }
    return _report(
      '"default_group" is the name of a class and "$name" is a reserved word '
      'in Dart.',
      _sources.pick('default_group', 'naming')!.$2,
    );
  }

  /// `client` is the name of a class, as `default_group` is.
  String? clientClass() {
    final name = _identifierAt('client');
    if (name == null) return null;
    if (!DartNames.reservedWords.contains(name) &&
        !DartNames.builtInIdentifiers.contains(name) &&
        name.startsWith(RegExp(r'[A-Z$]'))) {
      return name;
    }
    return _report(
      '"client" is the name of a class: an identifier that starts with an '
      'uppercase letter and is not a reserved word in Dart.',
      _sources.pick('client', 'naming')!.$2,
    );
  }

  /// `input_suffix` and `patch_suffix`: two model names made from one schema
  /// must differ, so equal suffixes are an error, reported at the later
  /// key, and both go back to their defaults.
  (String, String) suffixes() {
    final input = _identifierAt('input_suffix');
    final patch = _identifierAt('patch_suffix');
    final inputSuffix = input ?? GenerationConfig.defaultInputSuffix;
    final patchSuffix = patch ?? GenerationConfig.defaultPatchSuffix;
    if (inputSuffix != patchSuffix) return (inputSuffix, patchSuffix);
    final at = patch != null
        ? _sources.pick('patch_suffix', 'naming')!.$2
        : _sources.pick('input_suffix', 'naming')!.$2;
    _report(
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

  /// Reports an invalid value at [at]; returns null.
  Null _report(String message, JsonPointer at) {
    _invalid(message, at);
    return null;
  }
}
