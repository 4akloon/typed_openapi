import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'composed_yaml.dart';
// The composer reads the events of package:yaml's parser, copied into
// yaml/: the YAML syntax exactly as package:yaml tokenizes it, without the
// recursive loader, which overflows the stack on deep nesting, expands alias
// bombs and hashes collection keys.
import 'yaml/event.dart';
import 'yaml/parser.dart';
import 'yaml/yaml_exception.dart';
import 'yaml_anchor.dart';
import 'yaml_anchors.dart';
import 'yaml_frame.dart';
import 'yaml_limits.dart';
import 'yaml_reporter.dart';
import 'yaml_tags.dart';

/// One run of the composer: the parser events of one text, read into a tree
/// with an explicit stack.
final class YamlComposition {
  /// Creates the run for [_text] (the file at [_uri]) that reports to
  /// [_reporter] and stays within [_limits].
  YamlComposition(this._text, this._uri, this._reporter, this._limits)
    : _tags = YamlTags(_reporter),
      _anchors = YamlAnchors(_limits);

  final String _text;
  final Uri _uri;
  final YamlReporter _reporter;
  final YamlLimits _limits;
  final YamlTags _tags;
  final YamlAnchors _anchors;

  final Map<String, SourceSpan> _spans = {};
  final List<YamlFrame> _stack = [];

  /// How deep inside a skipped collection the composer is; 0 when not.
  int _skipped = 0;
  int _documents = 0;
  Object? _root;
  ({String message, SourceSpan span})? _syntaxError;
  SourceSpan? _lastSpan;

  /// Reads the text; null after a limit was reported.
  ComposedYaml? run() {
    final parser = Parser(
      _text,
      sourceUrl: _uri,
      onWarning: _reporter.parserWarning,
    );
    while (!_limits.hasFailed && _syntaxError == null) {
      final event = _next(parser);
      if (event == null) break;
      if (event.type == .streamEnd) {
        return ComposedYaml(root: _root, spans: _spans);
      }
      _handle(event);
    }
    if (_limits.hasFailed) return null;
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

  SourceSpan _here() =>
      _lastSpan ?? SourceFile.fromString(_text, url: _uri).span(0, 0);

  void _handle(Event event) {
    switch (event) {
      case DocumentStartEvent():
        if (++_documents > 1) {
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
        _start(event, event.tag, event.anchor, isMapping: false);
      case MappingStartEvent():
        _start(event, event.tag, event.anchor, isMapping: true);
      case Event(type: .sequenceEnd || .mappingEnd):
        _end(event);
      default:
    }
  }

  // --- scalars -------------------------------------------------------------

  void _scalar(ScalarEvent event) {
    if (_skipped > 0) {
      _anchors.defineSkipped(event.anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      _anchors.defineSkipped(event.anchor);
      frame.state = .key;
      return;
    }
    final isKey = frame != null && frame.state == .key;
    final pointer = isKey ? frame.pointer : _childPointer(frame);
    final value = _tags.resolveScalar(event, pointer);
    if (isKey) {
      _scalarKey(frame, event, value);
      return;
    }
    if (!_limits.charge(pointer, event.span)) return;
    _spans[pointer.value] = event.span;
    _anchors.recordScalar(pointer.value, event.span);
    _anchors.defineScalar(event.anchor, value, event.value, event.span);
    _attach(frame, value);
  }

  void _scalarKey(YamlFrame frame, ScalarEvent event, Object? value) {
    if (value == null) {
      _reporter.nullKey(frame.pointer, event.value, event.span);
    }
    _key(frame, event.value, value, event.span);
    _anchors.defineScalar(event.anchor, value, event.value, event.span);
  }

  void _key(YamlFrame frame, String text, Object? value, SourceSpan span) {
    final earlier = frame.acceptKey(text, value, span);
    if (earlier == null) return;
    _reporter.duplicateKey(frame.pointer, text, earlier, value, span);
  }

  // --- aliases -------------------------------------------------------------

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
      _aliasAsKey(frame, anchor, event.span);
      return;
    }
    _aliasAsValue(frame, anchor, event.span);
  }

  void _aliasAsKey(YamlFrame frame, YamlAnchor anchor, SourceSpan span) {
    if (anchor.text case final text? when !anchor.skipped) {
      _key(frame, text, anchor.value, span);
    } else {
      _reporter.nonStringKey(frame.pointer, span);
      frame.state = .skipValue;
    }
  }

  void _aliasAsValue(YamlFrame? frame, YamlAnchor anchor, SourceSpan span) {
    final pointer = _childPointer(frame);
    if (anchor.skipped) {
      _reporter.aliasInsideNonStringKey(pointer, span);
      _attach(frame, null);
      return;
    }
    if (!_anchors.expand(anchor, pointer, span, _spans)) return;
    _attach(frame, anchor.value);
  }

  // --- collections ---------------------------------------------------------

  void _start(
    Event event,
    String? tag,
    String? anchor, {
    required bool isMapping,
  }) {
    final level = _limits.open;
    if (!_limits.enter(event.span)) return;
    if (_skipped > 0) {
      _skipped++;
      _anchors.defineSkipped(anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state != .value) {
      _skipCollection(frame, event.span, anchor);
      return;
    }
    _pushCollection(event, tag, anchor, level, frame, isMapping: isMapping);
  }

  /// Starts skipping a collection that is a key, or the value of a key that
  /// was not a string.
  void _skipCollection(YamlFrame frame, SourceSpan span, String? anchor) {
    if (frame.state == .key) {
      _reporter.nonStringKey(frame.pointer, span);
      frame.state = .skippedKey;
    } else {
      frame.state = .skippedValue;
    }
    _skipped = 1;
    _anchors.defineSkipped(anchor);
  }

  /// Pushes the frame of a collection that is built.
  void _pushCollection(
    Event event,
    String? tag,
    String? anchor,
    int level,
    YamlFrame? parent, {
    required bool isMapping,
  }) {
    final pointer = _childPointer(parent);
    if (!_limits.charge(pointer, event.span)) return;
    _tags.checkCollection(tag, pointer, event.span, isMapping: isMapping);
    final record = YamlSpanRecord(pointer.value, event.span, level);
    _stack.add(
      YamlFrame(
        pointer,
        isMapping ? <String, Object?>{} : <Object?>[],
        event.span,
        record,
        _anchors.startCollection(anchor, record),
      ),
    );
  }

  void _end(Event event) {
    _limits.leave();
    if (_skipped > 0) {
      _endSkipped();
      return;
    }
    final frame = _stack.removeLast();
    final span = frame.start.expand(event.span);
    frame.record.span = span;
    _spans[frame.pointer.value] = span;
    if (frame.anchor case final anchor?) {
      _anchors.endCollection(anchor, frame.value);
    }
    _attach(_stack.isEmpty ? null : _stack.last, frame.value);
  }

  void _endSkipped() {
    if (--_skipped > 0) return;
    final frame = _stack.last;
    frame.state = frame.state == .skippedKey ? .skipValue : .key;
  }

  // --- values --------------------------------------------------------------

  JsonPointer _childPointer(YamlFrame? frame) =>
      frame == null ? .root : frame.childPointer;

  void _attach(YamlFrame? frame, Object? value) {
    if (frame == null) {
      _root = value;
    } else {
      frame.attach(value);
    }
  }
}
