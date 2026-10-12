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
    final content = switch (raw['content']) {
      final Map<String, Object?> content => content,
      _ => const <String, Object?>{},
    };
    final type = entry.spec['contentType'] as String?;
    final hasSchema = entry.spec.containsKey('schema');
    final String key;
    if (type != null) {
      key = type;
    } else if (content.length == 1) {
      key = content.keys.single;
    } else {
      if (hasSchema) {
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
      return;
    }
    final Map<String, Object?> next;
    if (content.containsKey(key) || content.isEmpty || content.length == 1) {
      next = {key: content[key] ?? content.values.firstOrNull ?? {}};
    } else {
      _report(
        .overrideTargetAmbiguous,
        entry,
        'contentType',
        'This has the media types ${content.keys.join(', ')} and none is '
            '$key; it is not clear which one to replace.',
        fix: 'Set "contentType" to one of them.',
      );
      return;
    }
    if (type != null && _equality.equals(content.keys.toList(), [key])) {
      _unchanged(entry, 'contentType');
    }
    if (entry.spec case {'schema': final Object schema}) {
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
    if (_equality.equals(next, raw['content'])) return;
    yield OverrideEdit(SpecEdit.add(at.child('content'), next), [
      if (type != null) (entry, 'contentType'),
      if (hasSchema) (entry, 'schema'),
    ]);
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
    final toRef =
        spec.containsKey(r'$ref') ||
        raw.containsKey(r'$ref') && spec.containsKey('nullable');
    if (toRef) {
      yield* _reference(entry, at, raw, property);
      return;
    }
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

  /// Makes the schema at [at] a (nullable) reference.
  Iterable<OverrideEdit> _reference(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    bool property,
  ) sync* {
    final spec = entry.spec;
    final others = [
      for (final field in spec.keys)
        if (field != r'$ref' &&
            field != 'nullable' &&
            !(property && field == 'required'))
          field,
    ];
    if (others.isNotEmpty) {
      _report(
        .invalidOverride,
        entry,
        others.first,
        '"${others.first}" cannot be set on a schema that is a reference.',
        fix: r'Replace the reference with "$ref" and "nullable" only.',
      );
      return;
    }
    final ref = (spec[r'$ref'] ?? raw[r'$ref']) as String;
    final nullable = spec['nullable'] == true;
    final next = <String, Object?>{
      if (!nullable) r'$ref': ref,
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
    var nullable = spec['nullable'] as bool? ?? wasNullable;
    if (nullable && nextBase.isEmpty) {
      _report(
        .invalidOverride,
        entry,
        'nullable',
        'From OpenAPI 3.1, a schema is nullable through "null" in its '
            '"type", and this schema has no type.',
        fix: 'Add "type" to the override.',
      );
      if (!spec.containsKey('type')) return;
      nullable = false;
    }
    final types = [...nextBase, if (nullable) 'null'];
    final fields = [
      if (spec.containsKey('type')) 'type',
      if (spec.containsKey('nullable') && nextBase.isNotEmpty) 'nullable',
    ];
    if (spec.containsKey('type') && _equality.equals(base, nextBase)) {
      _unchanged(entry, 'type');
      fields.remove('type');
    }
    if (fields.contains('nullable') && wasNullable == nullable) {
      _unchanged(entry, 'nullable');
      fields.remove('nullable');
    }
    if (fields.isEmpty) return;
    final sources = [for (final field in fields) (entry, field)];
    yield OverrideEdit(switch (types) {
      [] => SpecEdit.remove(at.child('type')),
      [final type] => SpecEdit.add(at.child('type'), type),
      _ => SpecEdit.add(at.child('type'), types),
    }, sources);
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
        break;
      }
      if (!dropped.contains(a)) kept.add(a);
    }
    return kept;
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
