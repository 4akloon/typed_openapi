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
import '../paths/real_paths.dart';
import 'config_keys.dart';
import 'config_reader.dart';
import 'generation_reader.dart';
import 'project_config.dart';

/// Reads `typed_openapi.yaml` into a [ProjectConfig].
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class ConfigLoader {
  /// Creates a loader that reports to [_diagnostics]; [_paths] names the
  /// config file in diagnostics.
  const ConfigLoader(this._diagnostics, [this._paths = const DisplayPaths()]);

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
    final reader = ConfigReader(file, _diagnostics, composed.spans);
    final root = composed.root;
    if (root is! Map<String, Object?>) {
      reader.invalid('The config must be a mapping.', .root);
      return null;
    }
    reader.checkKeys(root, ConfigKeys.topLevel, .root);

    final defaultsPointer = JsonPointer.root.child('defaults');
    final defaults = reader.mapAt(root, 'defaults', .root);
    Preset? defaultPreset;
    int? defaultWidth;
    var defaultRules = const <String, bool>{};
    var defaultLevels = const <DiagnosticCode, Severity?>{};
    if (defaults != null) {
      reader.checkKeys(defaults, ConfigKeys.defaults, defaultsPointer);
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
      reader.checkKeys(value, ConfigKeys.client, pointer);
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
      final generation = GenerationReader(reader, [
        if (defaults != null) (defaults, defaultsPointer),
        (value, pointer),
      ]).read();
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
          generation: generation,
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
        if (!RealPaths.overlap(a.output, b.output)) continue;
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
