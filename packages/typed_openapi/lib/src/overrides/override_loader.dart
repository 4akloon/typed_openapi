import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import 'override_set.dart';

/// Reads a client's overrides file (`typed_openapi.overrides.yaml`, JSON or
/// YAML) into an [OverrideSet].
///
/// Every problem goes to the [DiagnosticBag] given to the constructor, at
/// its position in the overrides file: a missing file is
/// `overrides-not-found`, text that cannot be read and values of the wrong
/// type are `invalid-override`, unknown keys `unknown-override-key`. A bad
/// value is ignored and the rest of the file is read.
final class OverrideLoader {
  /// Creates a loader that reports to [_diagnostics].
  const OverrideLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the overrides file at [path]; [displayPath] names it in
  /// diagnostics. Returns null when the file cannot be used at all.
  OverrideSet? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .overridesNotFound,
        'Overrides file $file does not exist.',
        file: file,
        fix: 'Create it, or fix "overrides" of this client in the config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .invalidOverride,
        'Overrides path $file is a directory, not a file.',
        file: file,
        fix: 'Point "overrides" of this client at the overrides file itself.',
      );
      return null;
    }
    final String? text = _readText(path);
    if (text != null && _isBlank(text, file)) return _empty(file, path);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).load(path, displayPath: file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads overrides from [text]; [file] names it in diagnostics and tells
  /// JSON from YAML by its extension.
  OverrideSet? parse(String text, String file) {
    if (_isBlank(text, file)) return _empty(file, file);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).parse(text, file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads the overrides in an already loaded [document].
  OverrideSet read(SpecDocument document) =>
      _OverrideReader(_diagnostics, document).read();

  /// The text of the file at [path], or null when it cannot be read; the
  /// spec loader then reports why.
  static String? _readText(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Whether [text] has nothing but whitespace, and for YAML comments and
  /// document markers: a file with no override yet.
  static bool _isBlank(String text, String file) {
    final json = p.extension(file).toLowerCase() == '.json';
    return text.split('\n').every((line) {
      final t = line.trim();
      return t.isEmpty ||
          (!json && (t.startsWith('#') || t == '---' || t == '...'));
    });
  }

  /// A set with no override, for a file that has no content.
  static OverrideSet _empty(String file, String path) => OverrideSet(
    SpecDocument(
      file: file,
      uri: p.toUri(p.normalize(p.absolute(path))),
      root: const {},
      spans: const {},
    ),
  );

  /// Reports what the spec loader said about the file as problems of the
  /// overrides file.
  void _forward(DiagnosticBag scratch) {
    for (final d in scratch.all) {
      _diagnostics.report(
        d.code == .positionsUnavailable ? d.code : .invalidOverride,
        d.message,
        severity: d.severity,
        file: d.file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
  }
}

/// One read of an overrides document.
final class _OverrideReader {
  _OverrideReader(this._diagnostics, this._document);

  static const _sections = {'operations', 'schemas'};
  static const _operationKeys = {
    'reason',
    'name',
    'exclude',
    'group',
    'parameters',
    'requestBody',
    'responses',
  };
  static const _parameterKeys = {
    'reason',
    'required',
    'schema',
    'name',
    'dartType',
  };
  static const _bodyKeys = {'reason', 'contentType', 'schema'};
  static const _responseKeys = {'reason', 'contentType', 'schema'};

  /// Fields that change a schema, in the order they are applied.
  static const _schemaFields = [
    r'$ref',
    'type',
    'nullable',
    'format',
    'required',
    'items',
    'additionalProperties',
    'enum',
    'discriminator',
  ];
  static const _schemaKeys = {
    'reason',
    ..._schemaFields,
    'name',
    'exclude',
    'exhaustive',
    'dartType',
    'properties',
  };
  static const _propertyKeys = {
    'reason',
    ..._schemaFields,
    'name',
    'exclude',
    'dartType',
    'triState',
  };
  static const _dartTypeKeys = {'type', 'import', 'converter'};

  static final _methodAndPath = RegExp(r'^([A-Za-z]+) (/.*)$');

  final DiagnosticBag _diagnostics;
  final SpecDocument _document;

  OverrideSet read() {
    final root = _document.root;
    _checkKeys(root, _sections, .root);
    return OverrideSet(
      _document,
      operations: [
        for (final (key, entry, at) in _entries(root, 'operations', .root))
          ?_operation(key, entry, at),
      ],
      schemas: [
        for (final (key, entry, at) in _entries(root, 'schemas', .root))
          _schema(key, entry, at),
      ],
    );
  }

  OperationOverride? _operation(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _operationKeys, at);
    String? method;
    String? path;
    if (_methodAndPath.firstMatch(key) case final match?) {
      method = match[1]!.toLowerCase();
      path = match[2];
      if (!PathItem.methods.contains(method)) {
        _invalid(
          'The method "${match[1]}" is not an OpenAPI operation method.',
          at,
          fix:
              'Write the key as an operationId, or as METHOD /path with one '
              'of ${PathItem.methods.map((m) => m.toUpperCase()).join(', ')}.',
        );
        return null;
      }
    }
    final body = _map(entry, 'requestBody', at);
    return OperationOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      operationId: method == null ? key : null,
      method: method,
      path: path,
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      group: _string(entry, 'group', at),
      parameters: [
        for (final (name, value, p) in _entries(entry, 'parameters', at))
          ?_parameter(name, value, p),
      ],
      requestBody: body == null ? null : _body(body, at.child('requestBody')),
      responses: [
        for (final (status, value, p) in _entries(entry, 'responses', at))
          _response(status, value, p),
      ],
    );
  }

  ParameterOverride? _parameter(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _parameterKeys, at);
    var name = key;
    ParameterLocation? placement;
    final colon = key.indexOf(':');
    if (colon > 0) {
      placement = ParameterLocation.values.asNameMap()[key.substring(0, colon)];
      if (placement == null) {
        _invalid(
          'The parameter key "$key" has no valid "in" before ":".',
          at,
          fix:
              'Write in:name with in one of '
              '${ParameterLocation.values.map((l) => l.name).join(', ')}.',
        );
        return null;
      }
      name = key.substring(colon + 1);
    }
    return ParameterOverride(
      key: key,
      pointer: at,
      parameterName: name,
      placement: placement,
      reason: _string(entry, 'reason', at),
      spec: {
        if (entry.containsKey('required'))
          'required': ?_bool(entry, 'required', at),
        if (entry.containsKey('schema')) 'schema': ?_map(entry, 'schema', at),
      },
      name: _string(entry, 'name', at),
      dartType: _dartType(entry, at),
    );
  }

  BodyOverride _body(Map<String, Object?> entry, JsonPointer at) {
    _checkKeys(entry, _bodyKeys, at);
    return BodyOverride(
      key: 'requestBody',
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  ResponseOverride _response(
    String status,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _responseKeys, at);
    return ResponseOverride(
      key: status,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  Map<String, Object?> _contentSpec(
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    final contentType = _string(entry, 'contentType', at);
    if (contentType != null && !contentType.contains('/')) {
      _invalid(
        '"contentType" must be a media type such as application/json.',
        at.child('contentType'),
      );
    }
    return {
      if (contentType != null && contentType.contains('/'))
        'contentType': contentType,
      if (entry.containsKey('schema')) 'schema': ?_map(entry, 'schema', at),
    };
  }

  SchemaOverride _schema(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _schemaKeys, at);
    final spec = _schemaSpec(entry, at, property: false);
    final properties = [
      for (final (name, value, p) in _entries(entry, 'properties', at))
        _property(name, value, p),
    ];
    if (spec.containsKey(r'$ref') && properties.isNotEmpty) {
      _invalid(
        r'"properties" cannot be combined with "$ref": the schema becomes the '
        'reference.',
        at.child('properties'),
      );
      properties.clear();
    }
    return SchemaOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: spec,
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      exhaustive: _bool(entry, 'exhaustive', at),
      dartType: _dartType(entry, at),
      properties: properties,
    );
  }

  PropertyOverride _property(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _propertyKeys, at);
    return PropertyOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _schemaSpec(entry, at, property: true),
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      dartType: _dartType(entry, at),
      triState: _bool(entry, 'triState', at),
    );
  }

  /// The schema fields of [entry]; for a [property], `required` is a
  /// boolean, else the list of required property names.
  Map<String, Object?> _schemaSpec(
    Map<String, Object?> entry,
    JsonPointer at, {
    required bool property,
  }) {
    final spec = <String, Object?>{};
    for (final field in _schemaFields) {
      if (!entry.containsKey(field)) continue;
      final value = entry[field];
      final valid = switch (field) {
        r'$ref' => value is String && value.isNotEmpty,
        'type' =>
          value == null ||
              SchemaType.values.any(
                (t) => t.wire == value && t != SchemaType.nullType,
              ),
        'nullable' => value is bool,
        'format' => value == null || value is String,
        'required' when property => value is bool,
        'required' =>
          value == null || value is List<Object?> && value.every(_isName),
        'items' || 'discriminator' => value == null || value is Map,
        'additionalProperties' =>
          value == null || value is bool || value is Map,
        'enum' => value == null || value is List<Object?> && value.isNotEmpty,
        _ => false,
      };
      if (!valid) {
        _invalid(
          '"$field" ${_expected(field, property: property)}.',
          at.child(field),
        );
        continue;
      }
      spec[field] = value;
    }
    if (spec.containsKey(r'$ref')) {
      for (final field in spec.keys.toList()) {
        if (field == r'$ref' || field == 'nullable') continue;
        if (field == 'required' && property) continue;
        _invalid(
          '"$field" cannot be combined with "\$ref": the schema becomes the '
          'reference.',
          at.child(field),
        );
        spec.remove(field);
      }
    }
    return spec;
  }

  static bool _isName(Object? value) => value is String && value.isNotEmpty;

  static String _expected(String field, {required bool property}) =>
      switch (field) {
        r'$ref' => 'must be a non-empty string',
        'type' =>
          'must be one of string, number, integer, boolean, array, object, or '
              'null to remove it (use "nullable" for null)',
        'nullable' => 'must be true or false',
        'format' => 'must be a string, or null to remove it',
        'required' when property => 'must be true or false',
        'required' => 'must be a list of property names, or null to remove it',
        'items' || 'discriminator' => 'must be an object, or null to remove it',
        'additionalProperties' =>
          'must be true, false or an object, or null to remove it',
        _ => 'must be a non-empty list, or null to remove it',
      };

  DartTypeOverride? _dartType(Map<String, Object?> entry, JsonPointer at) {
    final value = _map(entry, 'dartType', at);
    if (value == null) return null;
    final p = at.child('dartType');
    _checkKeys(value, _dartTypeKeys, p);
    final type = _string(value, 'type', p, required: true);
    final import = _string(value, 'import', p, required: true);
    final converter = _string(value, 'converter', p);
    if (type == null || import == null) return null;
    var valid = true;
    for (final (field, written) in [
      ('type', type),
      ('import', import),
      if (converter != null) ('converter', converter),
    ]) {
      if (DartTypeOverride.problem(field, written) case final problem?) {
        _invalid(problem, p.child(field));
        valid = false;
      }
    }
    if (!valid) return null;
    return DartTypeOverride(type: type, import: import, converter: converter);
  }

  /// The entries of the [key] mapping of [parent] whose values are
  /// mappings, with their pointers; other values are reported.
  List<(String, Map<String, Object?>, JsonPointer)> _entries(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    // A section whose entries are all commented out reads as null.
    if (parent.containsKey(key) && parent[key] == null) return const [];
    final section = _map(parent, key, at);
    if (section == null) return const [];
    final p = at.child(key);
    final entries = <(String, Map<String, Object?>, JsonPointer)>[];
    for (final MapEntry(key: name, :value) in section.entries) {
      if (value is Map<String, Object?>) {
        entries.add((name, value, p.child(name)));
      } else {
        _invalid('"$name" must be a mapping.', p.child(name));
      }
    }
    return entries;
  }

  Map<String, Object?>? _map(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    _invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  String? _string(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) _invalid('"$key" is required.', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    _invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  bool? _bool(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is bool) return value;
    _invalid('"$key" must be true or false.', at.child(key));
    return null;
  }

  void _checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    final known = allowed.toList()..sort();
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      final closest = _closest(key, known);
      _diagnostics.report(
        .unknownOverrideKey,
        'Unknown key "$key"; it is ignored.',
        file: _document.file,
        pointer: at.child(key),
        span: _document.spanOf(at.child(key)),
        fix:
            '${closest == null ? '' : 'Did you mean "$closest"? '}'
            'Allowed keys here: ${known.join(', ')}.',
      );
    }
  }

  /// The first of the sorted [known] keys at the smallest edit distance
  /// from [key], when that distance is at most [_maxTypoDistance].
  static String? _closest(String key, List<String> known) {
    String? best;
    var bestDistance = _maxTypoDistance + 1;
    for (final candidate in known) {
      final distance = _distance(key, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// How many edits a key may be away from a known key to be suggested.
  static const _maxTypoDistance = 2;

  /// The Levenshtein distance between [a] and [b].
  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + substitution,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  void _invalid(String message, JsonPointer at, {String? fix}) {
    _diagnostics.report(
      DiagnosticCode.invalidOverride,
      message,
      file: _document.file,
      pointer: at,
      span: _document.spanOf(at),
      fix: fix,
    );
  }
}
