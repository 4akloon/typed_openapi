import 'package:collection/collection.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import '../resolve/spec_documents.dart';
import 'override_resolver.dart';
import 'override_set.dart';

/// An edit an override makes, with the override it comes from.
final class OverrideEdit {
  /// Creates an override edit.
  const OverrideEdit(this.edit, this.sources);

  /// The change of the spec's plain tree.
  final SpecEdit edit;

  /// The entries and fields that ask for the change.
  final List<(OverrideEntry, String)> sources;
}

/// Turns the spec fields of resolved overrides into [SpecEdit]s.
///
/// A field replaces the value of the spec (a list replaces the list, an
/// object the object) and `null` removes it. `nullable` follows the
/// document's dialect: `nullable: true` in 3.0, `null` in `type` from 3.1.
/// `$ref` makes the schema a reference; a nullable reference is
/// `allOf: [{$ref}]` with `nullable: true` in 3.0 and
/// `anyOf: [{$ref}, {type: 'null'}]` from 3.1.
///
/// A field whose value the spec already has is `override-unchanged`; two
/// different edits of one node by different overrides are
/// `override-conflict`, and neither is made.
final class OverrideApplier {
  /// Creates an applier of [_overrides] to [_documents], whose root declares
  /// [_version]; it reports to [_diagnostics].
  const OverrideApplier(
    this._diagnostics,
    this._overrides,
    this._documents,
    this._version,
  );

  static const _equality = DeepCollectionEquality();

  /// Keys a null branch may have besides `type`.
  static const _annotations = {
    'type',
    'description',
    'title',
    r'$comment',
    'default',
    'deprecated',
    'example',
    'examples',
    'readOnly',
    'writeOnly',
  };

  /// Schema fields replaced as they are, in the order they are applied.
  static const _plainFields = [
    'format',
    'required',
    'items',
    'additionalProperties',
    'enum',
    'discriminator',
  ];

  final DiagnosticBag _diagnostics;
  final OverrideSet _overrides;
  final SpecDocuments _documents;
  final OpenApiVersion _version;

  /// The edits of [targets], in their order.
  List<OverrideEdit> edits(List<OverrideTarget> targets) {
    final edits = <OverrideEdit>[];
    final required = <SpecLocation, List<PropertyTarget>>{};
    for (final target in targets) {
      switch (target) {
        case OperationTarget():
          break;
        case ParameterTarget():
          edits.addAll(_parameter(target));
        case ContentTarget():
          edits.addAll(_content(target));
        case SchemaTarget():
          edits.addAll(_schema(target.entry, target.node.location, false));
        case PropertyTarget():
          edits.addAll(_schema(target.entry, target.node.location, true));
          if (target.entry.spec.containsKey('required')) {
            (required[target.owner.location] ??= []).add(target);
          }
      }
    }
    for (final MapEntry(key: owner, value: properties) in required.entries) {
      edits.addAll(_required(owner, properties));
    }
    return _withoutConflicts(edits);
  }

  Iterable<OverrideEdit> _parameter(ParameterTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _object(at) ?? const {};
    if (entry.spec case {'required': final bool required}) {
      if ((raw['required'] == true) == required) {
        _unchanged(entry, 'required');
      } else {
        yield OverrideEdit(
          required
              ? SpecEdit.add(at.child('required'), true)
              : SpecEdit.remove(at.child('required')),
          [(entry, 'required')],
        );
      }
    }
    if (entry.spec case {'schema': final Object schema}) {
      yield* _set(entry, 'schema', at, raw, schema);
    }
  }

  Iterable<OverrideEdit> _content(ContentTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _object(at) ?? const {};
    final content = _mediaTypes(raw);
    final type = entry.spec['contentType'] as String?;
    final hasSchema = entry.spec.containsKey('schema');
    final key = _mediaKey(entry, content, type);
    if (key == null) return;
    final next = _contentWith(entry, content, key);
    if (next == null) return;
    if (type != null && _equality.equals(content.keys.toList(), [key])) {
      _unchanged(entry, 'contentType');
    }
    if (entry.spec case {'schema': final Object schema}) {
      _setMediaSchema(entry, next, key, schema);
    }
    if (_equality.equals(next, raw['content'])) return;
    yield OverrideEdit(SpecEdit.add(at.child('content'), next), [
      if (type != null) (entry, 'contentType'),
      if (hasSchema) (entry, 'schema'),
    ]);
  }

  /// The `content` map of [raw], empty when there is none.
  static Map<String, Object?> _mediaTypes(Map<String, Object?> raw) =>
      switch (raw['content']) {
        final Map<String, Object?> content => content,
        _ => const <String, Object?>{},
      };

  /// The media type an override of [entry] changes: [type] if it names one,
  /// else the only one of [content]. Null, with a report when a schema is
  /// to be set, when there is none or several to choose from.
  String? _mediaKey(
    OverrideEntry entry,
    Map<String, Object?> content,
    String? type,
  ) {
    if (type != null) return type;
    if (content.length == 1) return content.keys.single;
    if (entry.spec.containsKey('schema')) {
      _report(
        content.isEmpty ? .invalidOverride : .overrideTargetAmbiguous,
        entry,
        'schema',
        content.isEmpty
            ? 'This has no media type to put the schema in.'
            : 'This has the media types ${content.keys.join(', ')}; it is '
                  'not clear which schema to replace.',
        fix: 'Add "contentType" to the override.',
      );
    }
    return null;
  }

  /// A new `content` map with [key] only, taken from [content]; null, with a
  /// report, when [content] has other media types and none is [key].
  Map<String, Object?>? _contentWith(
    OverrideEntry entry,
    Map<String, Object?> content,
    String key,
  ) {
    if (content.containsKey(key) || content.isEmpty || content.length == 1) {
      return {key: content[key] ?? content.values.firstOrNull ?? {}};
    }
    _report(
      .overrideTargetAmbiguous,
      entry,
      'contentType',
      'This has the media types ${content.keys.join(', ')} and none is '
          '$key; it is not clear which one to replace.',
      fix: 'Set "contentType" to one of them.',
    );
    return null;
  }

  /// Sets the `schema` of the media type [key] in [next], or reports that
  /// the spec already has it.
  void _setMediaSchema(
    OverrideEntry entry,
    Map<String, Object?> next,
    String key,
    Object schema,
  ) {
    final media = switch (next[key]) {
      final Map<String, Object?> media => media,
      _ => const <String, Object?>{},
    };
    if (_equality.equals(media['schema'], schema)) {
      _unchanged(entry, 'schema');
    } else {
      next[key] = {...media, 'schema': schema};
    }
  }

  Iterable<OverrideEdit> _schema(
    OverrideEntry entry,
    SpecLocation at,
    bool property,
  ) sync* {
    final spec = entry.spec;
    if (spec.keys.every((k) => property && k == 'required')) return;
    final raw = _object(at);
    if (raw == null) {
      _report(
        .invalidOverride,
        entry,
        null,
        'The schema at ${at.pointer.value} is not an object; its fields '
        'cannot be set.',
      );
      return;
    }
    final rawRef = raw[r'$ref'] is String ? raw[r'$ref'] as String : null;
    final shape = _nullableShape(raw);
    final toRef =
        spec[r'$ref'] is String ||
        spec.containsKey('nullable') && (rawRef != null || shape != null);
    if (toRef) {
      yield* _reference(entry, at, raw, property, rawRef, shape);
    } else if (_version == .v30 && rawRef != null) {
      _reportIgnoredSiblings(entry, property);
    } else {
      yield* _fields(entry, at, raw, property);
    }
  }

  /// Reports every field of [entry] that 3.0 would ignore on a reference.
  void _reportIgnoredSiblings(OverrideEntry entry, bool property) {
    for (final field in ['type', ..._plainFields]) {
      if (!entry.spec.containsKey(field) || property && field == 'required') {
        continue;
      }
      _report(
        .fixNotApplied,
        entry,
        field,
        'This override was not applied: in OpenAPI 3.0 the siblings of '
        '"\$ref" are ignored, so "$field" would have no effect on a '
        'schema that is a reference.',
        fix: 'Override the referenced schema by its name under "schemas".',
      );
    }
  }

  /// The edits of `type`, `nullable` and the plain fields of a schema that
  /// is not a reference.
  Iterable<OverrideEdit> _fields(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    bool property,
  ) sync* {
    final spec = entry.spec;
    if (spec.containsKey('type') || spec.containsKey('nullable')) {
      yield* _version == .v30
          ? _typeAndNullable30(entry, at, raw)
          : _typeAndNullable31(entry, at, raw);
    }
    for (final field in _plainFields) {
      if (field == 'required' && property) continue;
      if (!spec.containsKey(field)) continue;
      yield* _set(entry, field, at, raw, spec[field]);
    }
  }

  /// Makes the schema at [at] a (nullable) reference, or changes the
  /// nullability of a schema that is one or has a `null` branch.
  ///
  /// An override with `$ref` replaces the node. One with only `nullable`
  /// keeps every other key of the node: [rawRef] is the `$ref` of a schema
  /// that is a reference, [shape] the nullable form of one that is nullable.
  Iterable<OverrideEdit> _reference(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    bool property,
    String? rawRef,
    _NullableShape? shape,
  ) sync* {
    final spec = entry.spec;
    final specRef = spec[r'$ref'];
    final others = [
      for (final field in spec.keys)
        if (field != r'$ref' &&
            field != 'nullable' &&
            !(property && field == 'required'))
          field,
    ];
    if (others.isNotEmpty) {
      _reportOtherField(
        entry,
        others.first,
        specRef is String || rawRef != null,
      );
    } else if (specRef is String) {
      yield* _replaceWithReference(entry, at, raw, specRef);
    } else {
      yield* _changeNullability(entry, at, raw, rawRef, shape);
    }
  }

  /// Reports [field], which cannot be set where the node becomes (or is) a
  /// reference or a nullable union.
  void _reportOtherField(
    OverrideEntry entry,
    String field,
    bool isReference,
  ) {
    _report(
      .invalidOverride,
      entry,
      field,
      isReference
          ? '"$field" cannot be set on a schema that is a reference.'
          : '"$field" cannot be set together with "nullable" on a schema that '
                'is nullable through "anyOf" or "oneOf".',
      fix: isReference
          ? r'Replace the reference with "$ref" and "nullable" only.'
          : 'Override "nullable" alone, or the schema by its name.',
    );
  }

  /// The edit that makes the node at [at] the (nullable) reference [specRef].
  Iterable<OverrideEdit> _replaceWithReference(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    String specRef,
  ) sync* {
    final spec = entry.spec;
    final nullable = spec['nullable'] == true;
    final next = <String, Object?>{
      if (!nullable) r'$ref': specRef,
      ..._nullableForm(specRef, nullable),
    };
    final fields = [
      for (final field in [r'$ref', 'nullable'])
        if (spec.containsKey(field)) field,
    ];
    if (_equality.equals(raw, next)) {
      for (final field in fields) {
        _unchanged(entry, field);
      }
      return;
    }
    yield OverrideEdit(SpecEdit.replace(at, next), [
      for (final field in fields) (entry, field),
    ]);
  }

  /// The edit that adds or removes the nullability of a reference
  /// ([rawRef]) or of a nullable schema ([shape]), keeping the other keys.
  Iterable<OverrideEdit> _changeNullability(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    String? rawRef,
    _NullableShape? shape,
  ) sync* {
    final nullable = entry.spec['nullable'] == true;
    if (nullable == (shape != null)) {
      _unchanged(entry, 'nullable');
      return;
    }
    final Map<String, Object?> next;
    if (shape == null) {
      next = {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key != r'$ref') key: value,
        ..._nullableForm(rawRef!, true),
      };
    } else {
      final merged = shape.withoutNull();
      if (merged == null) {
        _reportUnmergeable(entry, shape);
        return;
      }
      next = merged;
    }
    yield OverrideEdit(SpecEdit.replace(at, next), [(entry, 'nullable')]);
  }

  void _reportUnmergeable(OverrideEntry entry, _NullableShape shape) {
    _report(
      .fixNotApplied,
      entry,
      'nullable',
      'This override was not applied: the schema and the "'
          '${shape.key}" branch both set the same key to different values, '
          'so they cannot be merged.',
      fix: 'Override the schema by its name.',
    );
  }

  /// The keys that make [ref] nullable in the document's dialect; none when
  /// [nullable] is false.
  Map<String, Object?> _nullableForm(String ref, bool nullable) => {
    if (nullable && _version == .v30) ...{
      'allOf': [
        {r'$ref': ref},
      ],
      'nullable': true,
    },
    if (nullable && _version != .v30)
      'anyOf': [
        {r'$ref': ref},
        {'type': 'null'},
      ],
  };

  /// The nullable form of [raw] for the document's dialect: a `$ref` in
  /// `allOf` next to `nullable: true` in 3.0; from 3.1 an `anyOf` or `oneOf`
  /// of one or more branches and a null schema; any other keys are siblings.
  /// Null for any other schema.
  _NullableShape? _nullableShape(Map<String, Object?> raw) {
    if (_version == .v30) {
      final list = raw['allOf'];
      if (raw['nullable'] != true ||
          list is! List<Object?> ||
          list.length != 1) {
        return null;
      }
      final branch = list.single;
      return branch is Map<String, Object?> &&
              branch.length == 1 &&
              branch[r'$ref'] is String
          ? _NullableShape(raw, 'allOf', [branch])
          : null;
    }
    for (final key in ['anyOf', 'oneOf']) {
      final list = raw[key];
      if (list is! List<Object?> || list.length < 2) continue;
      final branches = <Map<String, Object?>>[];
      var nulls = 0;
      for (final item in list) {
        if (item is! Map<String, Object?>) {
          nulls = 0;
          break;
        }
        if (_isNullSchema(item)) {
          nulls++;
        } else {
          branches.add(item);
        }
      }
      if (nulls > 0 && branches.isNotEmpty) {
        return _NullableShape(raw, key, branches);
      }
    }
    return null;
  }

  /// Whether [schema] allows only `null`: `type: 'null'`, with no keys but
  /// annotations.
  static bool _isNullSchema(Map<String, Object?> schema) =>
      schema['type'] == 'null' &&
      schema.keys.every(
        (key) => _annotations.contains(key) || key.startsWith('x-'),
      );

  Iterable<OverrideEdit> _typeAndNullable30(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    if (spec.containsKey('type')) {
      yield* _set(entry, 'type', at, raw, spec['type']);
    }
    if (spec case {'nullable': final bool nullable}) {
      if ((raw['nullable'] == true) == nullable) {
        _unchanged(entry, 'nullable');
      } else {
        yield OverrideEdit(
          nullable
              ? SpecEdit.add(at.child('nullable'), true)
              : SpecEdit.remove(at.child('nullable')),
          [(entry, 'nullable')],
        );
      }
    }
  }

  Iterable<OverrideEdit> _typeAndNullable31(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    final current = switch (raw['type']) {
      final String type => [type],
      final List<Object?> types => types.whereType<String>().toList(),
      _ => const <String>[],
    };
    final wasNullable = current.contains('null');
    final base = [
      for (final type in current)
        if (type != 'null') type,
    ];
    final nextBase = switch (spec) {
      {'type': final String type} => [type],
      {'type': null} => const <String>[],
      _ => base,
    };
    // `type: null` without `nullable` removes the type, and the schema with
    // it is no longer nullable.
    var nullable =
        spec['nullable'] as bool? ??
        (wasNullable && (spec['type'] != null || !spec.containsKey('type')));
    var failed = false;
    if (nullable && nextBase.isEmpty) {
      failed = true;
      _reportNullableWithoutType(entry);
      if (!spec.containsKey('type')) return;
      nullable = false;
    }
    final fields = _changedFields(
      entry,
      sameType: _equality.equals(base, nextBase),
      sameNullable: wasNullable == nullable,
      nullableFailed: failed,
    );
    if (fields.isEmpty) return;
    if (spec.containsKey('type') &&
        spec['type'] == null &&
        wasNullable &&
        !spec.containsKey('nullable')) {
      _reportDroppedNullability(entry);
    }
    final types = [...nextBase, if (nullable) 'null'];
    yield OverrideEdit(
      switch (types) {
        [] => SpecEdit.remove(at.child('type')),
        [final type] => SpecEdit.add(at.child('type'), type),
        _ => SpecEdit.add(at.child('type'), types),
      },
      [for (final field in fields) (entry, field)],
    );
  }

  /// The fields of [entry] that change the `type` list, after reporting the
  /// ones that do not.
  List<String> _changedFields(
    OverrideEntry entry, {
    required bool sameType,
    required bool sameNullable,
    required bool nullableFailed,
  }) {
    final spec = entry.spec;
    final fields = [
      if (spec.containsKey('type')) 'type',
      if (spec.containsKey('nullable') && !nullableFailed) 'nullable',
    ];
    if (spec.containsKey('type') && sameType) {
      _unchanged(entry, 'type');
      fields.remove('type');
    }
    if (fields.contains('nullable') && sameNullable) {
      _unchanged(entry, 'nullable');
      fields.remove('nullable');
    }
    return fields;
  }

  void _reportNullableWithoutType(OverrideEntry entry) {
    _report(
      .invalidOverride,
      entry,
      'nullable',
      'From OpenAPI 3.1, a schema is nullable through "null" in its '
          '"type", and this schema has no type.',
      fix: 'Add "type" to the override.',
    );
  }

  void _reportDroppedNullability(OverrideEntry entry) {
    _report(
      .overrideNullabilityDropped,
      entry,
      'type',
      'From OpenAPI 3.1, nullability is the "null" in "type"; removing the '
          'type also makes the schema non-nullable.',
    );
  }

  /// The edits of the `required` list of the schema at [owner] for the
  /// `required` of its [properties].
  Iterable<OverrideEdit> _required(
    SpecLocation owner,
    List<PropertyTarget> properties,
  ) sync* {
    final raw = _object(owner) ?? const {};
    final current = switch (raw['required']) {
      final List<Object?> names => names,
      _ => const <Object?>[],
    };
    final next = [...current];
    final sources = <(OverrideEntry, String)>[];
    for (final property in properties) {
      final name = property.entry.key;
      final required = property.entry.spec['required'] == true;
      if (next.contains(name) == required) {
        _unchanged(property.entry, 'required');
        continue;
      }
      if (required) {
        next.add(name);
      } else {
        next.remove(name);
      }
      sources.add((property.entry, 'required'));
    }
    if (sources.isEmpty) return;
    final at = owner.child('required');
    yield OverrideEdit(
      next.isEmpty ? SpecEdit.remove(at) : SpecEdit.add(at, next),
      sources,
    );
  }

  /// The edit that sets [field] of the object at [at] to [value]; `null`
  /// removes it.
  Iterable<OverrideEdit> _set(
    OverrideEntry entry,
    String field,
    SpecLocation at,
    Map<String, Object?> raw,
    Object? value,
  ) sync* {
    final has = raw.containsKey(field);
    if (value == null ? !has : has && _equality.equals(raw[field], value)) {
      _unchanged(entry, field);
      return;
    }
    yield OverrideEdit(
      value == null
          ? SpecEdit.remove(at.child(field))
          : SpecEdit.add(at.child(field), value),
      [(entry, field)],
    );
  }

  /// [edits] without the ones that touch a node another override's
  /// different edit touches; those are reported. One edit asked for by
  /// several overrides is made once.
  List<OverrideEdit> _withoutConflicts(List<OverrideEdit> edits) {
    final dropped = <OverrideEdit>{};
    final kept = <OverrideEdit>[];
    for (var i = 0; i < edits.length; i++) {
      final a = edits[i];
      if (kept.any((k) => k.edit.sameAs(a.edit))) continue;
      for (var j = 0; j < edits.length; j++) {
        final b = edits[j];
        if (i == j || b.edit.sameAs(a.edit) || !a.edit.overlaps(b.edit)) {
          continue;
        }
        dropped.add(a);
        _reportConflict(a, b);
        break;
      }
      if (!dropped.contains(a)) kept.add(a);
    }
    return kept;
  }

  /// Reports the sources of [a], which changes a node [b] changes too.
  void _reportConflict(OverrideEdit a, OverrideEdit b) {
    for (final (entry, field) in a.sources) {
      final other = b.sources.first.$1.pointer.child(b.sources.first.$2);
      _report(
        .overrideConflict,
        entry,
        field,
        'This changes ${a.edit.location.pointer.value}, which the '
        'override at ${other.value} changes too; neither is applied.',
        fix: 'Keep one of them.',
      );
    }
  }

  Map<String, Object?>? _object(SpecLocation at) =>
      switch (_documents[at.document]?.valueAt(at.pointer)) {
        (final Map<String, Object?> raw,) => raw,
        _ => null,
      };

  void _unchanged(OverrideEntry entry, String field) => _report(
    .overrideUnchanged,
    entry,
    field,
    'The spec already has this "$field"; the override changes nothing and '
    'can be removed.',
    fix: 'Remove "$field" from the override.',
  );

  void _report(
    DiagnosticCode code,
    OverrideEntry entry,
    String? field,
    String message, {
    String? fix,
  }) {
    final at = field == null ? entry.pointer : entry.pointer.child(field);
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: _overrides.file,
      pointer: at,
      span: _overrides.spanOf(at),
      fix: fix,
    );
  }
}

/// A nullable schema: a `$ref` with `nullable: true` (3.0), or one or more
/// branches next to a null branch (3.1), with the keys around them.
final class _NullableShape {
  /// Reads the shape of [raw] whose nullable form is [key] with [branches].
  const _NullableShape(this.raw, this.key, this.branches);

  /// The schema.
  final Map<String, Object?> raw;

  /// `allOf` (3.0), `anyOf` or `oneOf` (3.1).
  final String key;

  /// The branches that are not `null`.
  final List<Map<String, Object?>> branches;

  /// The schema without nullability, less a `default` that is `null`: one
  /// branch is merged with the other keys, several stay under [key]. Null
  /// when one branch and the other keys set one key to different values.
  Map<String, Object?>? withoutNull() {
    final siblings = {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key != this.key &&
            key != 'nullable' &&
            !(key == 'default' && value == null))
          key: value,
    };
    if (branches.length > 1) {
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key == this.key)
            key: branches
          else if (siblings.containsKey(key))
            key: value,
      };
    }
    for (final MapEntry(:key, :value) in branches.single.entries) {
      if (siblings.containsKey(key) &&
          !const DeepCollectionEquality().equals(siblings[key], value)) {
        return null;
      }
    }
    return {...branches.single, ...siblings};
  }
}
