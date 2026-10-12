import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'yaml/event.dart';
import 'yaml_reporter.dart';
import 'yaml_scalar_text.dart';

/// Reads the tags of YAML nodes: the JSON Schema ruleset is accepted, any
/// other tag is reported and its node read as plain text.
final class YamlTags {
  /// Creates a reader that reports to [_reporter].
  const YamlTags(this._reporter);

  static const _yamlTags = 'tag:yaml.org,2002:';

  static const _fix =
      'Remove the tag, or quote the value. OpenAPI YAML may only use the '
      'tags of the JSON Schema ruleset: !!str, !!int, !!float, !!bool, '
      '!!null, !!seq and !!map.';

  /// A tag property such as `!custom`, after an optional anchor.
  static final _localTag = RegExp(r'^(?:&\S+\s+)?(![^\s!]\S*)');

  final YamlReporter _reporter;

  /// The value of [event] as package:yaml's loader resolves it, with tags
  /// outside the JSON Schema ruleset reported at [pointer] and read as text.
  Object? resolveScalar(ScalarEvent event, JsonPointer pointer) {
    final tag = _tagOf(event.tag, event.span);
    final text = YamlScalarText(event.value);
    if (tag == null) return text.resolvePlain();
    if (tag == '!' || tag == '${_yamlTags}str') return event.value;
    if (_forced(tag, text) case (final value,)) return value;
    _reporter.report(
      .yamlTagUnsupported,
      _isKnownScalarTag(tag)
          ? '"${event.value}" is not a valid ${_tagName(tag)} value; it is '
                'read as a string.'
          : 'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
                'OpenAPI requires; the value is read as the string '
                '"${event.value}".',
      pointer: pointer,
      span: event.span,
      fix: _fix,
    );
    return event.value;
  }

  /// Reports a tag of the collection at [pointer] that the JSON Schema
  /// ruleset does not have; [isMapping] tells the tag it may have.
  void checkCollection(
    String? tag,
    JsonPointer pointer,
    SourceSpan span, {
    required bool isMapping,
  }) {
    final resolved = _tagOf(tag, span);
    final allowed = isMapping ? '${_yamlTags}map' : '${_yamlTags}seq';
    if (resolved == null || resolved == '!' || resolved == allowed) return;
    _reporter.report(
      .yamlTagUnsupported,
      'The YAML tag ${_tagName(resolved)} is not in the JSON Schema ruleset '
      'OpenAPI requires; the ${isMapping ? 'mapping' : 'list'} is read '
      'without it.',
      pointer: pointer,
      span: span,
      fix: _fix,
    );
  }

  /// The value [tag] forces on [text] in a one-element record, or null when
  /// the tag is not a scalar tag or the text is not a value of it.
  (Object?,)? _forced(String tag, YamlScalarText text) => switch (tag) {
    '${_yamlTags}null' => text.asNull(),
    '${_yamlTags}bool' => text.asBool(),
    '${_yamlTags}int' => text.asNumber(allowFloat: false),
    '${_yamlTags}float' => text.asNumber(allowInt: false),
    _ => null,
  };

  bool _isKnownScalarTag(String tag) =>
      tag.startsWith(_yamlTags) &&
      const {'null', 'bool', 'int', 'float'}.contains(
        tag.substring(_yamlTags.length),
      );

  /// The tag of a node whose parser event has [tag] and [span].
  ///
  /// package:yaml's parser reports a local tag such as `!custom` as the
  /// non-specific tag `!`, the tag of every quoted scalar; the source text
  /// tells them apart.
  String? _tagOf(String? tag, SourceSpan span) {
    if (tag != '!') return tag;
    return _localTag.firstMatch(span.text)?.group(1) ?? tag;
  }

  String _tagName(String tag) => tag.startsWith(_yamlTags)
      ? '!!${tag.substring(_yamlTags.length)}'
      : tag.startsWith('!')
      ? tag
      : '!<$tag>';
}
