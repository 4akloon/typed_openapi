import '../config/project_config.dart';
import 'preset_detection.dart';

/// Finds the framework that wrote a spec from the marks it leaves.
///
/// A preset is detected only when its marks are there and no other
/// framework's are. Values of the wrong type are no marks.
final class PresetDetector {
  /// Creates a detector.
  const PresetDetector();

  static final RegExp _nestOperationId = RegExp(
    r'^[A-Z][A-Za-z0-9]*Controller_[A-Za-z0-9_]+$',
  );

  /// Detects the preset of the document whose plain tree is [root].
  PresetDetection detect(Map<String, Object?> root) {
    final found = <(Preset, String)>[
      ?_pair(.nestjs, _nestjs(root)),
      ?_pair(.fastapi, _fastapi(root)),
      ?_pair(.springdoc, _springdoc(root)),
      ?_pair(.aspnet, _aspnet(root)),
    ];
    return switch (found) {
      [(final preset, final reason)] => PresetDetection(preset, reason),
      [] => const PresetDetection.generic('no framework marks were found'),
      _ => PresetDetection.generic(
        'the marks of ${found.map((f) => f.$1.name).join(' and ')} '
        'were found',
      ),
    };
  }

  static (Preset, String)? _pair(Preset preset, String? reason) =>
      reason == null ? null : (preset, reason);

  static String? _nestjs(Map<String, Object?> root) {
    final id = _operationIds(root).where(_nestOperationId.hasMatch).firstOrNull;
    if (id != null) {
      return 'operationId "$id" has the form of @nestjs/swagger';
    }
    return switch (_at(root, ['info', 'contact'])) {
      Map<Object?, Object?>(isEmpty: true) =>
        'info.contact is the empty object that the DocumentBuilder of '
            '@nestjs/swagger writes',
      _ => null,
    };
  }

  static String? _fastapi(Map<String, Object?> root) =>
      _hasSchema(root, 'HTTPValidationError') &&
          _hasSchema(root, 'ValidationError')
      ? 'components.schemas has HTTPValidationError and ValidationError'
      : null;

  static String? _springdoc(Map<String, Object?> root) {
    if (_at(root, ['info', 'title']) == 'OpenAPI definition') {
      return 'info.title is "OpenAPI definition"';
    }
    final servers = root['servers'];
    if (servers is List<Object?> &&
        servers.any(
          (s) =>
              s is Map<Object?, Object?> &&
              s['description'] == 'Generated server url',
        )) {
      return 'a server has the description "Generated server url"';
    }
    return null;
  }

  static String? _aspnet(Map<String, Object?> root) =>
      _hasSchema(root, 'ProblemDetails') && _hasKey(root, 'text/json')
      ? 'components.schemas has ProblemDetails and a text/json media type '
            'is used'
      : null;

  static bool _hasSchema(Map<String, Object?> root, String name) =>
      switch (_at(root, ['components', 'schemas'])) {
        final Map<Object?, Object?> schemas => schemas.containsKey(name),
        _ => false,
      };

  static Object? _at(Object? node, List<String> keys) {
    var current = node;
    for (final key in keys) {
      if (current is! Map<Object?, Object?>) return null;
      current = current[key];
    }
    return current;
  }

  static Iterable<String> _operationIds(Map<String, Object?> root) sync* {
    final paths = root['paths'];
    if (paths is! Map<Object?, Object?>) return;
    for (final item in paths.values) {
      if (item is! Map<Object?, Object?>) continue;
      for (final operation in item.values) {
        if (operation is! Map<Object?, Object?>) continue;
        final id = operation['operationId'];
        if (id is String) yield id;
      }
    }
  }

  static bool _hasKey(Object? node, String key) => switch (node) {
    final Map<Object?, Object?> map =>
      map.containsKey(key) || map.values.any((v) => _hasKey(v, key)),
    final List<Object?> list => list.any((v) => _hasKey(v, key)),
    _ => false,
  };
}
