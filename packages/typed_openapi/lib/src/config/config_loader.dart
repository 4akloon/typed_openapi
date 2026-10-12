import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import '../diagnostics/severity_levels.dart';
import '../load/yaml_composer.dart';
import '../normalize/normalizer.dart';
import 'project_config.dart';

/// Reads `typed_openapi.yaml` into a [ProjectConfig].
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class ConfigLoader {
  /// Creates a loader that reports to [_diagnostics]; [_paths] names the
  /// config file in diagnostics.
  const ConfigLoader(this._diagnostics, [this._paths = const DisplayPaths()]);

  static const _topLevelKeys = {'defaults', 'clients'};
  static const _defaultsKeys = {'preset', 'line_width', 'rules', 'severity'};
  static const _clientKeys = {
    'input',
    'output',
    'preset',
    'overrides',
    'baseline',
    'line_width',
    'rules',
    'severity',
  };

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// Reads the config file at [path], relative to the working directory of
  /// the [DisplayPaths] given to the constructor.
  ///
  /// Relative paths inside it are resolved against its directory. Returns
  /// null when the file is missing or unusable; otherwise returns every
  /// client that is valid.
  ProjectConfig? load(String path) {
    final full = _paths.absolute(path);
    final file = _paths.of(path);
    final type = FileSystemEntity.typeSync(full);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .configNotFound,
        'Config file $file does not exist.',
        file: file,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .configInvalid,
        'Config path $file is a directory, not a file.',
        file: file,
        fix: 'Pass the path of typed_openapi.yaml itself with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = File(full).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .configInvalid,
        'Cannot read $file: ${e.message}.',
        file: file,
      );
      return null;
    }
    final composed = _compose(text, file, full);
    if (composed == null) return null;
    final reader = _ConfigReader(file, _diagnostics, composed.spans);
    final root = composed.root;
    if (root is! Map<String, Object?>) {
      reader.invalid('The config must be a mapping.', .root);
      return null;
    }
    reader.checkKeys(root, _topLevelKeys, .root);

    final defaultsPointer = JsonPointer.root.child('defaults');
    final defaults = reader.mapAt(root, 'defaults', .root);
    Preset? defaultPreset;
    int? defaultWidth;
    var defaultRules = const <String, bool>{};
    var defaultLevels = const <DiagnosticCode, Severity?>{};
    if (defaults != null) {
      reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
      defaultPreset = reader.presetAt(defaults, defaultsPointer);
      defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
      defaultRules = reader.rulesAt(defaults, defaultsPointer);
      defaultLevels = reader.severityAt(defaults, defaultsPointer);
    }

    final clientsPointer = JsonPointer.root.child('clients');
    final clientNodes = reader.mapAt(root, 'clients', .root, required: true);
    if (clientNodes == null) return null;
    if (clientNodes.isEmpty) {
      reader.invalid('"clients" is empty.', clientsPointer);
      return null;
    }

    final baseDir = p.dirname(full);
    String resolve(String value) => p.normalize(p.join(baseDir, value));

    final clients = <ClientConfig>[];
    final declared = <String>{};
    final outputSpans = <String, SourceSpan?>{};
    final baselineSpans = <String, SourceSpan?>{};
    for (final MapEntry(key: name, :value) in clientNodes.entries) {
      declared.add(name);
      final pointer = clientsPointer.child(name);
      if (value is! Map<String, Object?>) {
        reader.invalid('Client "$name" must be a mapping.', pointer);
        continue;
      }
      reader.checkKeys(value, _clientKeys, pointer);
      final input = reader.stringAt(value, 'input', pointer, required: true);
      final output = reader.stringAt(value, 'output', pointer, required: true);
      final preset = reader.presetAt(value, pointer) ?? defaultPreset;
      final lineWidth =
          reader.intAt(value, 'line_width', pointer) ??
          defaultWidth ??
          ClientConfig.defaultLineWidth;
      final overrides = reader.stringAt(value, 'overrides', pointer);
      final baseline = reader.stringAt(value, 'baseline', pointer);
      final rules = {...defaultRules, ...reader.rulesAt(value, pointer)};
      final levels = {
        ...defaultLevels,
        ...reader.severityAt(value, pointer),
      };
      if (input == null || output == null) continue;
      outputSpans[name] = reader.spanAt(pointer.child('output'));
      baselineSpans[name] = reader.spanAt(pointer.child('baseline'));
      clients.add(
        ClientConfig(
          name: name,
          input: resolve(input),
          output: resolve(output),
          lineWidth: lineWidth,
          preset: preset,
          overrides: overrides == null ? null : resolve(overrides),
          baseline: baseline == null ? null : resolve(baseline),
          disabledRules: {
            for (final MapEntry(:key, :value) in rules.entries)
              if (!value) key,
          },
          severity: SeverityLevels(levels),
        ),
      );
    }
    clients.sort((a, b) => a.name.compareTo(b.name));
    _checkOutputOverlap(clients, outputSpans, file);
    _checkSharedBaselines(clients, baselineSpans, file);
    return ProjectConfig(
      file: path,
      clients: clients,
      declaredClients: declared,
    );
  }

  /// Reads [text] into plain values; null after reporting why it cannot be
  /// used. Every problem of the YAML itself is a config error.
  ComposedYaml? _compose(String text, String file, String path) {
    final yaml = DiagnosticBag();
    final composed = YamlComposer(
      yaml,
    ).compose(text, file: file, uri: p.toUri(path));
    for (final d in yaml.all) {
      _diagnostics.report(
        .configInvalid,
        d.message,
        severity: d.severity,
        file: file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    if (composed?.syntaxError case final error?) {
      _diagnostics.report(
        .configInvalid,
        error.message,
        file: file,
        span: error.span,
      );
      return null;
    }
    return composed;
  }

  /// Reports a baseline file named by two clients: each client's baseline
  /// is written from that client's diagnostics alone.
  void _checkSharedBaselines(
    List<ClientConfig> clients,
    Map<String, SourceSpan?> spans,
    String file,
  ) {
    final owners = <String, String>{};
    for (final client in clients) {
      final baseline = client.baseline;
      if (baseline == null) continue;
      final owner = owners[p.canonicalize(baseline)];
      if (owner == null) {
        owners[p.canonicalize(baseline)] = client.name;
        continue;
      }
      _diagnostics.report(
        .configInvalid,
        'Clients "$owner" and "${client.name}" name the same baseline file.',
        file: file,
        pointer: JsonPointer.root
            .child('clients')
            .child(client.name)
            .child('baseline'),
        span: spans[client.name],
        fix: 'Give each client its own baseline file.',
      );
    }
  }

  void _checkOutputOverlap(
    List<ClientConfig> clients,
    Map<String, SourceSpan?> outputSpans,
    String file,
  ) {
    for (var i = 0; i < clients.length; i++) {
      for (var j = i + 1; j < clients.length; j++) {
        final a = clients[i];
        final b = clients[j];
        final overlap =
            p.equals(a.output, b.output) ||
            p.isWithin(a.output, b.output) ||
            p.isWithin(b.output, a.output);
        if (!overlap) continue;
        _diagnostics.report(
          .outputOverlap,
          'Clients "${a.name}" and "${b.name}" write to overlapping '
          'directories.',
          file: file,
          pointer: JsonPointer.root
              .child('clients')
              .child(b.name)
              .child('output'),
          span: outputSpans[b.name],
          fix: 'Give each client its own output directory.',
        );
      }
    }
  }
}

/// Typed access to the values of a config document that reports bad ones.
class _ConfigReader {
  _ConfigReader(this.file, this.diagnostics, this.spans);

  final String file;
  final DiagnosticBag diagnostics;
  final Map<String, SourceSpan> spans;

  SourceSpan? spanAt(JsonPointer at) => spans[at.value];

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
