import '../normalize/spec_edit.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_resolver.dart';
import 'override_set.dart';

/// The edits of the overrides inside an operation: a parameter, a request
/// body or a response.
final class OperationOverrideApplier {
  /// Creates an applier that works in [_context].
  const OperationOverrideApplier(this._context);

  final OverrideEditContext _context;

  static const _equality = OverrideEditContext.equality;

  /// The edits of the `required` and `schema` of a parameter.
  Iterable<OverrideEdit> parameter(ParameterTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _context.object(at) ?? const {};
    if (entry.spec case {'required': final bool required}) {
      if ((raw['required'] == true) == required) {
        _context.unchanged(entry, 'required');
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
      yield* _context.set(entry, 'schema', at, raw, schema);
    }
  }

  /// The edit of the `content` of a request body or a response: the media
  /// type it has or names, and the schema of that media type.
  Iterable<OverrideEdit> content(ContentTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _context.object(at) ?? const {};
    final content = _mediaTypes(raw);
    final type = entry.spec['contentType'] as String?;
    final hasSchema = entry.spec.containsKey('schema');
    final key = _mediaKey(entry, content, type);
    if (key == null) return;
    final next = _contentWith(entry, content, key);
    if (next == null) return;
    if (type != null && _equality.equals(content.keys.toList(), [key])) {
      _context.unchanged(entry, 'contentType');
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
      _context.report(
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
    _context.report(
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
      _context.unchanged(entry, 'schema');
    } else {
      next[key] = {...media, 'schema': schema};
    }
  }
}
