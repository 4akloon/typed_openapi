import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import '../normalize/normalizer.dart';
import 'project_config.dart';

/// Typed access to the values of a config document that reports bad ones.
final class ConfigReader {
  /// Creates a reader of the config [file] that reports to [diagnostics];
  /// [spans] are the places of its values by JSON pointer.
  ConfigReader(this.file, this.diagnostics, this.spans);

  /// The config file, as diagnostics name it.
  final String file;

  /// Where problems go.
  final DiagnosticBag diagnostics;

  /// The places of the values, by JSON pointer.
  final Map<String, SourceSpan> spans;

  /// The place of the value at [at], if known.
  SourceSpan? spanAt(JsonPointer at) => spans[at.value];

  /// Reports every key of [map], at [at], that is not [allowed].
  void checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    for (final name in map.keys) {
      if (allowed.contains(name)) continue;
      diagnostics.report(
        .configUnknownKey,
        'Unknown key "$name".',
        file: file,
        pointer: at.child(name),
        span: spanAt(at.child(name)),
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  /// The mapping under [key] of [parent] at [at]; null, reported, when it
  /// is not a mapping or [required] and missing.
  Map<String, Object?>? mapAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  /// The non-empty string under [key] of [parent] at [at]; null, reported,
  /// when it is not one or [required] and missing.
  String? stringAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  /// The positive integer under [key] of [parent] at [at]; null, reported,
  /// when it is not one.
  int? intAt(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is int && value > 0) return value;
    invalid('"$key" must be a positive integer.', at.child(key));
    return null;
  }

  /// `rules` of [parent]: normalizer rule names mapped to whether they run.
  /// Unknown names are reported and skipped.
  Map<String, bool> rulesAt(Map<String, Object?> parent, JsonPointer at) {
    final rules = mapAt(parent, 'rules', at);
    if (rules == null) return const {};
    final pointer = at.child('rules');
    final known = Normalizer.ruleNames;
    final result = <String, bool>{};
    for (final MapEntry(key: name, :value) in rules.entries) {
      if (!known.contains(name)) {
        diagnostics.report(
          .configUnknownKey,
          'Unknown normalizer rule "$name".',
          file: file,
          pointer: pointer.child(name),
          span: spanAt(pointer.child(name)),
          fix: 'Known rules: ${(known.toList()..sort()).join(', ')}.',
        );
        continue;
      }
      if (value is! bool) {
        invalid(
          'Rule "$name" must be true or false.',
          pointer.child(name),
        );
        continue;
      }
      result[name] = value;
    }
    return result;
  }

  /// `severity` of [parent]: diagnostic codes, by id or slug, mapped to
  /// their level; `null` is `off`. Unknown codes are a warning, bad levels
  /// and levels a code cannot have are errors; all of them are skipped.
  Map<DiagnosticCode, Severity?> severityAt(
    Map<String, Object?> parent,
    JsonPointer at,
  ) {
    final entries = mapAt(parent, 'severity', at);
    if (entries == null) return const {};
    final pointer = at.child('severity');
    final result = <DiagnosticCode, Severity?>{};
    final names = <DiagnosticCode, String>{};
    for (final MapEntry(key: name, :value) in entries.entries) {
      final at = pointer.child(name);
      final code = _codes[name];
      if (code == null) {
        diagnostics.report(
          .configUnknownKey,
          'Unknown diagnostic code "$name".',
          file: file,
          pointer: at,
          span: spanAt(at),
          fix:
              'Use a code such as TOA201 or its name such as bool-required; '
              'the codes are in `DiagnosticCode` and the CHANGELOG.',
        );
        continue;
      }
      if (names[code] case final first?) {
        invalid(
          '"$name" names the same code as "$first" (${code.id}); '
          'only the first is used.',
          at,
        );
        continue;
      }
      names[code] = name;
      if (value is! String || !_levels.containsKey(value)) {
        invalid(
          'The level of "$name" must be error, warning, info or off.',
          at,
        );
        continue;
      }
      final level = _levels[value];
      if (DiagnosticCode.configCodes.contains(code)) {
        invalid(
          'The level of ${code.id} ${code.slug} cannot be changed: the '
          'config is read before levels apply.',
          at,
        );
        continue;
      }
      if (DiagnosticCode.fixedCodes.contains(code) &&
          (level == null || level.index > code.defaultSeverity.index)) {
        invalid(
          '${code.id} ${code.slug} cannot be lowered or turned off: '
          'without it a file that cannot be read would pass.',
          at,
        );
        continue;
      }
      result[code] = level;
    }
    return result;
  }

  static final _codes = {
    for (final code in DiagnosticCode.values) ...{
      code.id: code,
      code.slug: code,
    },
  };

  static const _levels = <String, Severity?>{
    'error': .error,
    'warning': .warning,
    'info': .info,
    'off': null,
  };

  /// `preset` of [parent] at [at]; null, reported, for an unknown preset.
  Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
    final name = stringAt(parent, 'preset', at);
    if (name == null) return null;
    final preset = Preset.values.asNameMap()[name];
    if (preset != null) return preset;
    final known = Preset.values.map((v) => v.name).toList()..sort();
    invalid(
      'Unknown preset "$name". Known presets: ${known.join(', ')}.',
      at.child('preset'),
    );
    return null;
  }

  /// Reports [message] as an invalid value at [at] (TOA902).
  void invalid(String message, JsonPointer at) {
    diagnostics.report(
      .configInvalid,
      message,
      file: file,
      pointer: at,
      span: spanAt(at),
    );
  }
}
