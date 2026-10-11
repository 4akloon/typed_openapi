import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
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
    final source = File(path);
    if (!source.existsSync()) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = source.readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .configInvalid,
        'Cannot read $path: ${e.message}.',
        file: path,
      );
      return null;
    }
    final YamlNode root;
    try {
      root = loadYamlNode(text, sourceUrl: Uri.file(path));
    } on YamlException catch (e) {
      _diagnostics.report(.configInvalid, e.message, file: path, span: e.span);
      return null;
    }
    final reader = _ConfigReader(path, _diagnostics);
    if (root is! YamlMap) {
      reader.invalid('The config must be a mapping.', root, .root);
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
      reader.invalid('"clients" is empty.', clientNodes, clientsPointer);
      return null;
    }

    final baseDir = p.dirname(p.absolute(path));
    String resolve(String value) => p.normalize(p.join(baseDir, value));

    final clients = <ClientConfig>[];
    final outputSpans = <String, SourceSpan>{};
    for (final MapEntry(:key, :value) in clientNodes.nodes.entries) {
      final name = '${(key as YamlNode).value}';
      final pointer = clientsPointer.child(name);
      if (value is! YamlMap) {
        reader.invalid('Client "$name" must be a mapping.', value, pointer);
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
      outputSpans[name] = value.nodes['output']!.span;
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
    return ProjectConfig(file: path, clients: clients);
  }

  void _checkOutputOverlap(
    List<ClientConfig> clients,
    Map<String, SourceSpan> outputSpans,
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

/// Typed access to the nodes of a config document that reports bad values.
class _ConfigReader {
  _ConfigReader(this.file, this.diagnostics);

  final String file;
  final DiagnosticBag diagnostics;

  void checkKeys(YamlMap map, Set<String> allowed, JsonPointer at) {
    for (final key in map.nodes.keys.cast<YamlNode>()) {
      final name = '${key.value}';
      if (allowed.contains(name)) continue;
      diagnostics.report(
        .configUnknownKey,
        'Unknown key "$name".',
        file: file,
        pointer: at.child(name),
        span: key.span,
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  YamlMap? mapAt(
    YamlMap parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    final node = parent.nodes[key];
    if (node == null) {
      if (required) invalid('Missing required key "$key".', parent, at);
      return null;
    }
    if (node is YamlMap) return node;
    invalid('"$key" must be a mapping.', node, at.child(key));
    return null;
  }

  String? stringAt(
    YamlMap parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    final node = parent.nodes[key];
    if (node == null) {
      if (required) invalid('Missing required key "$key".', parent, at);
      return null;
    }
    final value = node.value;
    if (value is String && value.isNotEmpty) return value;
    invalid('"$key" must be a non-empty string.', node, at.child(key));
    return null;
  }

  int? intAt(YamlMap parent, String key, JsonPointer at) {
    final node = parent.nodes[key];
    if (node == null) return null;
    final value = node.value;
    if (value is int && value > 0) return value;
    invalid('"$key" must be a positive integer.', node, at.child(key));
    return null;
  }

  Preset? presetAt(YamlMap parent, JsonPointer at) {
    final name = stringAt(parent, 'preset', at);
    if (name == null) return null;
    final preset = Preset.values.asNameMap()[name];
    if (preset != null) return preset;
    final known = Preset.values.map((v) => v.name).toList()..sort();
    invalid(
      'Unknown preset "$name". Known presets: ${known.join(', ')}.',
      parent.nodes['preset']!,
      at.child('preset'),
    );
    return null;
  }

  void invalid(String message, YamlNode node, JsonPointer at) {
    diagnostics.report(
      .configInvalid,
      message,
      file: file,
      pointer: at,
      span: node.span,
    );
  }
}
