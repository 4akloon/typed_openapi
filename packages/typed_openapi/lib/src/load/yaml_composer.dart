import 'dart:math';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
// The composer reads the events of package:yaml's parser, copied into
// yaml/: the YAML syntax exactly as package:yaml tokenizes it, without the
// recursive loader, which overflows the stack on deep nesting, expands alias
// bombs and hashes collection keys.
import 'yaml/event.dart';
import 'yaml/parser.dart';
import 'yaml/yaml_exception.dart';

/// A JSON or YAML text read into plain values, with the source range of
/// every node by JSON pointer value.
final class ComposedYaml {
  /// Creates a composed document.
  const ComposedYaml({
    required this.root,
    required this.spans,
    this.syntaxError,
  });

  /// The root value: `Map<String, Object?>`, `List<Object?>`, `String`,
  /// `num`, `bool` or `null`. Null when [syntaxError] is set.
  final Object? root;

  /// The source range of every node, by pointer value.
  final Map<String, SourceSpan> spans;

  /// Why the text is not valid YAML, when it is not; nothing was reported
  /// for it, so the caller decides how to.
  final ({String message, SourceSpan span})? syntaxError;
}

/// Builds plain values from YAML (and JSON, which is YAML) text, one parser
/// event at a time.
///
/// The composer replaces package:yaml's loader. It walks the events with an
/// explicit stack, so no input overflows the Dart stack, and checks in the
/// same pass:
///
/// - nesting deeper than [maxDepth] collections (`nesting-too-deep`): every
///   collection the parser opens is a level, keys included, and so is every
///   collection an alias expands to; the root collection is level 0;
/// - aliases that expand to more than the budget (`alias-expansion-too-
///   large`): every node built, read or reached through an alias, costs the
///   length of its JSON pointer plus one, and the budget is
///   `max(`[minBudget]`, `[budgetPerChar]` * text length)`;
/// - keys that are the same JSON key (`duplicate-key`): a warning and the
///   last value wins, except two keys YAML itself considers equal outside a
///   `.json` file, which are an error (as in YAML) but are read the same
///   way;
/// - keys that are not strings (`non-string-key`): a collection, or an alias
///   of one, as a key; the entry is dropped and nothing in it is built, so a
///   key cannot hide an alias bomb;
/// - keys that YAML reads as null (`~`, `null`, an empty key)
///   (`null-key`): a warning; they are read as their text;
/// - warnings of the YAML parser, such as an unknown directive
///   (`yaml-warning`);
/// - tags outside the YAML JSON Schema ruleset, such as `!!timestamp` or
///   `!custom` (`yaml-tag-unsupported`): the value is read as its text (a
///   collection as plain), so the rest of the file is still checked.
///
/// Scalar keys are read as their text, the YAML Failsafe schema OpenAPI
/// requires for keys: `200:` is the key `"200"`, `true:` the key `"true"`. Scalar values are resolved
/// with the JSON Schema ruleset exactly as package:yaml's loader does.
///
/// A limit or an undefined alias stops the composition: it is reported and
/// [compose] returns null. A syntax error is returned in
/// [ComposedYaml.syntaxError], unreported.
final class YamlComposer {
  /// Creates a composer that reports to [_diagnostics].
  const YamlComposer(this._diagnostics);

  /// The deepest nesting a document may have.
  static const maxDepth = 1000;

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = 16000000;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = 20;

  final DiagnosticBag _diagnostics;

  /// Composes [text]; [file] names it in diagnostics and [uri] in spans.
  ///
  /// With [json], every duplicate key is a warning (JSON keeps the last
  /// value); otherwise two keys YAML considers equal are an error.
  ComposedYaml? compose(
    String text, {
    required String file,
    required Uri uri,
    bool json = false,
  }) => _Composition(_diagnostics, text, file, uri, json: json).run();
}

/// One run of [YamlComposer].
final class _Composition {
  _Composition(
    this._diagnostics,
    this._text,
    this._file,
    this._uri, {
    required bool json,
  }) : _json = json,
       _budget = max(
         YamlComposer.minBudget,
         YamlComposer.budgetPerChar * _text.length,
       ),
       _mayHaveAliases = _text.contains('*');

  static const _yamlTags = 'tag:yaml.org,2002:';

  final DiagnosticBag _diagnostics;
  final String _text;
  final String _file;
  final Uri _uri;
  final bool _json;
  final bool _mayHaveAliases;
  int _budget;

  final Map<String, SourceSpan> _spans = {};
  final List<_Frame> _stack = [];
  final Map<String, _Anchor> _anchors = {};

  /// Span records of the nodes inside anchored collections being built, so
  /// that an alias can repeat them under its own pointer.
  final List<_Record> _records = [];
  int _openAnchors = 0;

  /// How many collections are open, skipped ones included: the level a
  /// collection that starts now has.
  int _open = 0;

  /// How deep inside a skipped collection the composer is; 0 when not.
  int _skipped = 0;

  Object? _root;
  bool _failed = false;
  ({String message, SourceSpan span})? _syntaxError;
  SourceSpan? _lastSpan;

  ComposedYaml? run() {
    final parser = Parser(_text, sourceUrl: _uri, onWarning: _warning);
    var documents = 0;
    while (!_failed && _syntaxError == null) {
      final event = _next(parser);
      if (event == null) break;
      switch (event) {
        case DocumentStartEvent():
          if (++documents > 1) {
            _syntaxError = (
              message: 'Only expected one document.',
              span: event.span,
            );
          }
        case ScalarEvent():
          _scalar(event);
        case AliasEvent():
          _alias(event);
        case SequenceStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: false,
          );
        case MappingStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: true,
          );
        case Event(type: .sequenceEnd || .mappingEnd):
          _end(event);
        case Event(type: .streamEnd):
          return ComposedYaml(root: _root, spans: _spans);
        default:
      }
    }
    if (_failed) return null;
    return ComposedYaml(root: null, spans: _spans, syntaxError: _syntaxError);
  }

  /// The next parser event, or null after recording a syntax error.
  Event? _next(Parser parser) {
    try {
      final event = parser.parse();
      _lastSpan = event.span;
      return event;
    } on YamlException catch (e) {
      _syntaxError = (message: e.message, span: e.span ?? _here());
      return null;
    }
  }

  void _warning(String message, SourceSpan span) {
    _diagnostics.report(
      .yamlWarning,
      message,
      file: _file,
      span: span,
    );
  }

  SourceSpan _here() =>
      _lastSpan ?? SourceFile.fromString(_text, url: _uri).span(0, 0);

  // --- nodes ---------------------------------------------------------------

  void _scalar(ScalarEvent event) {
    if (_skipped > 0) {
      _skipAnchor(event.anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      _skipAnchor(event.anchor);
      frame.state = .key;
      return;
    }
    final isKey = frame != null && frame.state == .key;
    final pointer = isKey ? frame.pointer : _childPointer(frame);
    final value = _resolve(event, pointer);
    if (isKey) {
      if (value == null) _nullKey(frame, event.value, event.span);
      _key(frame, event.value, value, event.span);
      if (event.anchor case final name?) {
        _anchors[name] = _Anchor.scalar(value, event.value, event.span);
      }
      return;
    }
    if (!_charge(pointer, event.span)) return;
    _spans[pointer.value] = event.span;
    if (_openAnchors > 0) _records.add(_Record(pointer.value, event.span, -1));
    if (event.anchor case final name?) {
      _anchors[name] = _Anchor.scalar(value, event.value, event.span);
    }
    _attach(frame, value);
  }

  void _alias(AliasEvent event) {
    if (_skipped > 0) return;
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      frame.state = .key;
      return;
    }
    final anchor = _anchors[event.name];
    if (anchor == null) {
      _syntaxError = (message: 'Undefined alias.', span: event.span);
      return;
    }
    if (anchor.open) {
      _syntaxError = (
        message: 'Self-referential collections are not supported.',
        span: event.span,
      );
      return;
    }
    if (frame != null && frame.state == .key) {
      if (anchor.text case final text? when !anchor.skipped) {
        _key(frame, text, anchor.value, event.span);
      } else {
        _nonStringKey(frame, event.span);
        frame.state = .skipValue;
      }
      return;
    }
    final pointer = _childPointer(frame);
    if (anchor.skipped) {
      _diagnostics.report(
        .nonStringKey,
        'This alias refers to a node inside a mapping key that is not a '
        'string; it is read as null.',
        file: _file,
        pointer: pointer,
        span: event.span,
        fix: 'Anchor the node outside the key.',
      );
      _attach(frame, null);
      return;
    }
    if (!_expand(anchor, pointer, event.span)) return;
    _attach(frame, anchor.value);
  }

  void _start(
    Event event,
    String? tag,
    String? anchor, {
    required bool isMapping,
  }) {
    final level = _open++;
    if (level > YamlComposer.maxDepth) {
      _fail(
        .nestingTooDeep,
        'The document nests deeper than ${YamlComposer.maxDepth} levels.',
        null,
        event.span,
      );
      return;
    }
    if (_skipped > 0) {
      _skipped++;
      _skipAnchor(anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state != .value) {
      if (frame.state == .key) {
        _nonStringKey(frame, event.span);
        frame.state = .skippedKey;
      } else {
        frame.state = .skippedValue;
      }
      _skipped = 1;
      _skipAnchor(anchor);
      return;
    }
    final pointer = _childPointer(frame);
    if (!_charge(pointer, event.span)) return;
    _checkTag(
      tag,
      isMapping ? '${_yamlTags}map' : '${_yamlTags}seq',
      pointer,
      event.span,
      isMapping ? 'mapping' : 'list',
    );
    final record = _Record(pointer.value, event.span, level);
    _Anchor? anchored;
    if (anchor != null) {
      anchored = _anchors[anchor] = _Anchor.collection(
        _records.length,
        pointer.value,
        level,
      );
      _openAnchors++;
    }
    if (_openAnchors > 0) _records.add(record);
    _stack.add(
      _Frame(
        pointer,
        isMapping ? <String, Object?>{} : <Object?>[],
        event.span,
        record,
        anchored,
      ),
    );
  }

  void _end(Event event) {
    _open--;
    if (_skipped > 0) {
      if (--_skipped > 0) return;
      final frame = _stack.last;
      frame.state = frame.state == .skippedKey ? .skipValue : .key;
      return;
    }
    final frame = _stack.removeLast();
    final span = frame.start.expand(event.span);
    frame.record.span = span;
    _spans[frame.pointer.value] = span;
    if (frame.anchor case final anchor?) {
      anchor
        ..value = frame.value
        ..end = _records.length
        ..open = false;
      _openAnchors--;
    }
    _attach(_stack.isEmpty ? null : _stack.last, frame.value);
  }

  // --- maps ----------------------------------------------------------------

  void _key(_Frame frame, String text, Object? value, SourceSpan span) {
    final earlier = frame.keys[text];
    frame.keys[text] = (value: value, span: span);
    frame.key = text;
    frame.state = .value;
    if (earlier == null) return;
    final yamlEqual = earlier.value == value;
    _diagnostics.report(
      .duplicateKey,
      yamlEqual
          ? 'Duplicate mapping key "$text"; the last value is used.'
          : 'Keys ${earlier.span.text} and ${span.text} are the same key '
                '"$text" in JSON; the last value is used.',
      // YAML forbids equal keys; JSON leaves them to the reader.
      severity: yamlEqual && !_json ? .error : null,
      file: _file,
      pointer: frame.pointer.child(text),
      span: span,
      fix: 'Remove one of the keys.',
    );
  }

  void _nullKey(_Frame frame, String text, SourceSpan span) {
    _diagnostics.report(
      .nullKey,
      text.isEmpty
          ? 'This mapping key is empty, which YAML reads as null; it is read '
                'as the empty string.'
          : 'The mapping key $text is null in YAML; it is read as the string '
                '"$text".',
      file: _file,
      pointer: frame.pointer.child(text),
      span: span,
      fix: 'Quote the key: "$text".',
    );
  }

  void _nonStringKey(_Frame frame, SourceSpan span) {
    _diagnostics.report(
      .nonStringKey,
      'A mapping key must be a string, not a collection; the entry is '
      'ignored.',
      file: _file,
      pointer: frame.pointer,
      span: span,
      fix: 'Write the key as a plain or quoted string.',
    );
  }

  // --- values --------------------------------------------------------------

  JsonPointer _childPointer(_Frame? frame) => switch (frame) {
    null => .root,
    _Frame(value: final List<Object?> list) => frame.pointer.child(list.length),
    _ => frame.pointer.child(frame.key!),
  };

  void _attach(_Frame? frame, Object? value) {
    if (frame == null) {
      _root = value;
      return;
    }
    switch (frame.value) {
      case final List<Object?> list:
        list.add(value);
      case final Map<String, Object?> map:
        map[frame.key!] = value;
        frame.state = .key;
    }
  }

  /// Repeats the records of [anchor] under [pointer], charging each one;
  /// false after reporting a limit.
  bool _expand(_Anchor anchor, JsonPointer pointer, SourceSpan span) {
    if (anchor.end < 0) {
      if (!_charge(pointer, span)) return false;
      _spans[pointer.value] = anchor.span!;
      if (_openAnchors > 0) {
        _records.add(_Record(pointer.value, anchor.span!, -1));
      }
      return true;
    }
    final level = _open;
    for (var i = anchor.first; i < anchor.end; i++) {
      final record = _records[i];
      final at = pointer.value + record.pointer.substring(anchor.base.length);
      final atLevel = record.level < 0
          ? -1
          : level + record.level - anchor.level;
      if (atLevel > YamlComposer.maxDepth) {
        _fail(
          .nestingTooDeep,
          'The document nests deeper than ${YamlComposer.maxDepth} levels, '
          'counting what its aliases expand to.',
          JsonPointer.parse(at),
          record.span!,
        );
        return false;
      }
      if (!_charge(JsonPointer.parse(at), record.span!)) return false;
      _spans[at] = record.span!;
      if (_openAnchors > 0) _records.add(_Record(at, record.span, atLevel));
    }
    return true;
  }

  bool _charge(JsonPointer pointer, SourceSpan span) {
    _budget -= pointer.value.length + 1;
    if (_budget >= 0) return true;
    _fail(
      .aliasExpansionTooLarge,
      _mayHaveAliases
          ? 'YAML aliases expand to far more nodes than the text has; the '
                'document is not read.'
          : 'The JSON pointers of the document\'s nodes add up to more than '
                'the supported size, because of very long keys or very deep '
                'nesting; the document is not read.',
      pointer,
      span,
      fix: _mayHaveAliases
          ? 'Remove the nested aliases.'
          : 'Shorten the longest keys.',
    );
    return false;
  }

  void _skipAnchor(String? name) {
    if (name != null) _anchors[name] = _Anchor.skipped();
  }

  void _fail(
    DiagnosticCode code,
    String message,
    JsonPointer? pointer,
    SourceSpan span, {
    String? fix,
  }) {
    _failed = true;
    _diagnostics.report(
      code,
      message,
      file: _file,
      pointer: pointer,
      span: span,
      fix: fix,
    );
  }

  // --- scalars and tags ----------------------------------------------------

  /// The value of [event] as package:yaml's loader resolves it, with tags
  /// outside the JSON Schema ruleset reported and read as text.
  Object? _resolve(ScalarEvent event, JsonPointer pointer) {
    final tag = _tagOf(event.tag, event.span);
    if (tag == null) return _plain(event.value);
    if (tag == '!' || tag == '${_yamlTags}str') return event.value;
    final value = switch (tag) {
      '${_yamlTags}null' => _null(event.value),
      '${_yamlTags}bool' => _bool(event.value),
      '${_yamlTags}int' => _number(event.value, allowFloat: false),
      '${_yamlTags}float' => _number(event.value, allowInt: false),
      _ => null,
    };
    if (value != null) return value.$1;
    final known =
        tag.startsWith(_yamlTags) &&
        const {'null', 'bool', 'int', 'float'}.contains(
          tag.substring(_yamlTags.length),
        );
    _diagnostics.report(
      .yamlTagUnsupported,
      known
          ? '"${event.value}" is not a valid ${_tagName(tag)} value; it is '
                'read as a string.'
          : 'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
                'OpenAPI requires; the value is read as the string '
                '"${event.value}".',
      file: _file,
      pointer: pointer,
      span: event.span,
      fix: _tagFix,
    );
    return event.value;
  }

  void _checkTag(
    String? tag,
    String allowed,
    JsonPointer pointer,
    SourceSpan span,
    String kind,
  ) {
    if (tag == null || tag == '!' || tag == allowed) return;
    _diagnostics.report(
      .yamlTagUnsupported,
      'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
      'OpenAPI requires; the $kind is read without it.',
      file: _file,
      pointer: pointer,
      span: span,
      fix: _tagFix,
    );
  }

  static const _tagFix =
      'Remove the tag, or quote the value. OpenAPI YAML may only use the '
      'tags of the JSON Schema ruleset: !!str, !!int, !!float, !!bool, '
      '!!null, !!seq and !!map.';

  /// A tag property such as `!custom`, after an optional anchor.
  static final _localTag = RegExp(r'^(?:&\S+\s+)?(![^\s!]\S*)');

  /// The tag of a node whose parser event has [tag] and [span].
  ///
  /// package:yaml's parser reports a local tag such as `!custom` as the
  /// non-specific tag `!`, the tag of every quoted scalar; the source text
  /// tells them apart.
  static String? _tagOf(String? tag, SourceSpan span) {
    if (tag != '!') return tag;
    return _localTag.firstMatch(span.text)?.group(1) ?? tag;
  }

  static String _tagName(String tag) => tag.startsWith(_yamlTags)
      ? '!!${tag.substring(_yamlTags.length)}'
      : tag.startsWith('!')
      ? tag
      : '!<$tag>';

  /// A plain scalar resolved as package:yaml's loader does: null, bool,
  /// int, float, else the string.
  static Object? _plain(String text) {
    if (text.isEmpty) return null;
    final resolved = switch (text.codeUnitAt(0)) {
      0x2E || 0x2B || 0x2D => _number(text),
      0x6E || 0x4E => text.length == 4 ? _null(text) : null,
      0x74 || 0x54 => text.length == 4 ? _bool(text) : null,
      0x66 || 0x46 => text.length == 5 ? _bool(text) : null,
      0x7E => text.length == 1 ? (null,) : null,
      final c when c >= 0x30 && c <= 0x39 => _number(text),
      _ => null,
    };
    return resolved == null ? text : resolved.$1;
  }

  static (Object?,)? _null(String text) => switch (text) {
    '' || 'null' || 'Null' || 'NULL' || '~' => (null,),
    _ => null,
  };

  static (Object?,)? _bool(String text) => switch (text) {
    'true' || 'True' || 'TRUE' => (true,),
    'false' || 'False' || 'FALSE' => (false,),
    _ => null,
  };

  static (Object?,)? _number(
    String text, {
    bool allowInt = true,
    bool allowFloat = true,
  }) {
    final value = _numberValue(
      text,
      allowInt: allowInt,
      allowFloat: allowFloat,
    );
    return value == null ? null : (value,);
  }

  static num? _numberValue(
    String text, {
    required bool allowInt,
    required bool allowFloat,
  }) {
    if (text.isEmpty) return null;
    final first = text.codeUnitAt(0);
    if (text.length == 1) {
      final digit = first - 0x30;
      if (digit < 0 || digit > 9) return null;
      return allowInt ? digit : digit.toDouble();
    }
    final second = text.codeUnitAt(1);
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    if (allowInt && first == 0x30) {
      if (second == 0x78) return int.tryParse(text);
      if (second == 0x6F) return int.tryParse(text.substring(2), radix: 8);
    }
    if (isDigit(first) ||
        ((first == 0x2B || first == 0x2D) && isDigit(second))) {
      num? result;
      if (allowInt) result = int.tryParse(text, radix: 10);
      if (allowFloat) result ??= double.tryParse(text);
      return result;
    }
    if (!allowFloat) return null;
    if ((first == 0x2E && isDigit(second)) ||
        ((first == 0x2D || first == 0x2B) && second == 0x2E)) {
      if (text.length == 5) {
        switch (text) {
          case '+.inf' || '+.Inf' || '+.INF':
            return double.infinity;
          case '-.inf' || '-.Inf' || '-.INF':
            return -double.infinity;
        }
      }
      return double.tryParse(text);
    }
    if (text.length == 4 && first == 0x2E) {
      switch (text) {
        case '.inf' || '.Inf' || '.INF':
          return double.infinity;
        case '.nan' || '.NaN' || '.NAN':
          return double.nan;
      }
    }
    return null;
  }
}

/// What a mapping frame expects next.
enum _State {
  /// A key.
  key,

  /// The value of [_Frame.key].
  value,

  /// A value to skip, because its key was not a string.
  skipValue,

  /// The rest of a key collection that is being skipped.
  skippedKey,

  /// The rest of a value collection that is being skipped.
  skippedValue,
}

/// A collection being built.
final class _Frame {
  _Frame(this.pointer, this.value, this.start, this.record, this.anchor)
    : state = value is List<Object?> ? .value : .key;

  final JsonPointer pointer;

  /// The `Map<String, Object?>` or `List<Object?>` being filled.
  final Object value;

  /// The span of the start event.
  final FileSpan start;

  /// The span record of the collection.
  final _Record record;

  /// The anchor defined on the collection, if any.
  final _Anchor? anchor;

  /// The keys read so far, with their YAML values and spans.
  final Map<String, ({Object? value, SourceSpan span})> keys = {};

  /// The key whose value comes next.
  String? key;

  /// What comes next; always [_State.value] in a list.
  _State state;
}

/// The span of one node, kept while an anchored collection is open.
final class _Record {
  _Record(this.pointer, this.span, this.level);

  final String pointer;

  /// Set when the node is complete.
  SourceSpan? span;

  /// The level of a collection; -1 for a scalar.
  final int level;
}

/// What an anchor names.
final class _Anchor {
  _Anchor.scalar(this.value, this.text, this.span)
    : skipped = false,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  _Anchor.collection(this.first, this.base, this.level)
    : skipped = false,
      text = null,
      span = null,
      end = -1,
      open = true;

  _Anchor.skipped()
    : skipped = true,
      value = null,
      text = null,
      span = null,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  /// Whether the anchored node is inside a skipped key or value.
  final bool skipped;

  Object? value;

  /// The text of a scalar.
  final String? text;

  /// The span of a scalar.
  final SourceSpan? span;

  /// The records of a collection: from [first] to [end] (exclusive).
  final int first;
  int end;

  /// The pointer value of the anchored collection.
  final String base;

  /// The level of the anchored collection.
  final int level;

  /// Whether the anchored collection is still being built.
  bool open;
}
