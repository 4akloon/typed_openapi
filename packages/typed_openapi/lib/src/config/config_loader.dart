import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/yaml_composer.dart';
import 'project_config.dart';

/// Reads `typed_openapi.yaml` into a [ProjectConfig].
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class ConfigLoader {
  /// Creates a loader that reports to [_diagnostics].
  const ConfigLoader(this._diagnostics);

  static const _topLevelKeys = {'defaults', 'clients'};
  static const _defaultsKeys = {'preset', 'line_width'};
  static const _clientKeys = {
    'input',
    'output',
    'preset',
    'overrides',
    'baseline',
    'line_width',
  };

  final DiagnosticBag _diagnostics;

  /// Reads the config file at [path].
  ///
  /// Relative paths inside it are resolved against its directory. Returns
  /// null when the file is missing or unusable; otherwise returns every
  /// client that is valid.
  ProjectConfig? load(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .configInvalid,
        'Config path $path is a directory, not a file.',
        file: path,
        fix: 'Pass the path of typed_openapi.yaml itself with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .configInvalid,
        'Cannot read $path: ${e.message}.',
        file: path,
      );
      return null;
    }
    final composed = _compose(text, path);
    if (composed == null) return null;
    final reader = _ConfigReader(path, _diagnostics, composed.spans);
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
    if (defaults != null) {
      reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
      defaultPreset = reader.presetAt(defaults, defaultsPointer);
      defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
    }

    final clientsPointer = JsonPointer.root.child('clients');
    final clientNodes = reader.mapAt(root, 'clients', .root, required: true);
    if (clientNodes == null) return null;
    if (clientNodes.isEmpty) {
      reader.invalid('"clients" is empty.', clientsPointer);
      return null;
    }

    final baseDir = p.dirname(p.absolute(path));
    String resolve(String value) => p.normalize(p.join(baseDir, value));

    final clients = <ClientConfig>[];
    final declared = <String>{};
    final outputSpans = <String, SourceSpan?>{};
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
      if (input == null || output == null) continue;
      outputSpans[name] = reader.spanAt(pointer.child('output'));
      clients.add(
        ClientConfig(
          name: name,
          input: resolve(input),
          output: resolve(output),
          lineWidth: lineWidth,
          preset: preset,
          overrides: overrides == null ? null : resolve(overrides),
          baseline: baseline == null ? null : resolve(baseline),
        ),
      );
    }
    clients.sort((a, b) => a.name.compareTo(b.name));
    _checkOutputOverlap(clients, outputSpans, path);
    return ProjectConfig(
      file: path,
      clients: clients,
      declaredClients: declared,
    );
  }

  /// Reads [text] into plain values; null after reporting why it cannot be
  /// used. Every problem of the YAML itself is a config error.
  ComposedYaml? _compose(String text, String path) {
    final yaml = DiagnosticBag();
    final composed = YamlComposer(
      yaml,
    ).compose(text, file: path, uri: p.toUri(p.absolute(path)));
    for (final d in yaml.all) {
      _diagnostics.report(
        .configInvalid,
        d.message,
        severity: d.severity,
        file: path,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    if (composed?.syntaxError case final error?) {
      _diagnostics.report(
        .configInvalid,
        error.message,
        file: path,
        span: error.span,
      );
      return null;
    }
    return composed;
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
