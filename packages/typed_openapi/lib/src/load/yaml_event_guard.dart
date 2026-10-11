// The guard reads package:yaml's own parser events, so that it sees the text
// exactly as `loadYamlNode` will: a text scanner that guesses YAML syntax
// keeps diverging from the real tokenizer. These are not public API, which
// is why pubspec.yaml pins the yaml version and this is the only such import.
// ignore: implementation_imports
import 'package:yaml/src/event.dart';
// ignore: implementation_imports
import 'package:yaml/src/parser.dart';
import 'package:yaml/yaml.dart';

/// Finds text that `loadYamlNode` cannot be trusted with, before it runs.
///
/// The guard runs package:yaml's `Parser` over the text and reads the events
/// (scalars, aliases, collection starts and ends). The parser is a state
/// machine with an explicit stack and builds no tree and hashes nothing, so
/// it neither overflows the stack on deep nesting nor expands an alias bomb.
/// `loadYamlNode` does both, and a `StackOverflowError` cannot be handled
/// like bad input.
///
/// It reports two problems:
///
/// - Nesting deeper than [maxDepth] collections, counted exactly as the
///   converter in `SpecLoader` counts it (the root collection is level 0,
///   keys and the implicit one-pair mappings of `[k: v]` included).
/// - An alias anywhere inside a mapping key, whether the key is the alias or
///   a collection that contains one. The parser hashes a key as a tree, which
///   takes exponential time for an alias bomb and happens before any later
///   check can see it. OpenAPI keys are strings, so this is never needed.
///   Aliases in values, in flow collections and in `<<: *a` merge keys are
///   not reported.
///
/// A syntax error makes the guard stop and report nothing: `loadYamlNode`
/// then reports it with its position.
final class YamlEventGuard {
  /// Creates a guard.
  const YamlEventGuard();

  /// The deepest nesting a spec or config file may have.
  static const maxDepth = 1000;

  /// The first problem in [text], or null when there is none or the text is
  /// not valid YAML.
  ///
  /// A collection nested deeper than [limit] is a [GuardProblem.tooDeep].
  GuardFinding? check(String text, {int limit = maxDepth}) {
    // package:yaml's scanner reads a whole line before it releases the first
    // events of it, and costs time proportional to the flow depth for each
    // token: a long line of `[` takes quadratic time (100 000 of them, a
    // minute). So the parser is first run on the text up to where a crude
    // bracket count passes the limit, where it finds such a flood in a
    // moment. The count ignores quotes, so it only chooses where to look
    // first; the parser decides. Text that hides closing brackets in quotes
    // from the count is still read in full, at the parser's quadratic cost.
    final flood = _bracketDepthExceeds(text, limit + 1);
    if (flood != null) {
      final early = _scan(text.substring(0, flood + 1), limit);
      if (early != null) return early;
    }
    return _scan(text, limit);
  }

  /// The offset where the running count of `[`/`{` minus `]`/`}` in [text]
  /// first exceeds [levels] (the root collection is level 1), or null.
  static int? _bracketDepthExceeds(String text, int levels) {
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      switch (text.codeUnitAt(i)) {
        case 0x5B || 0x7B:
          if (++depth > levels) return i;
        case 0x5D || 0x7D:
          if (depth > 0) depth--;
      }
    }
    return null;
  }

  static GuardFinding? _scan(String text, int limit) {
    final parser = Parser(text);
    final open = <_Collection>[];
    var keyCollections = 0;
    try {
      while (!parser.isDone) {
        final event = parser.parse();
        switch (event.type) {
          case .alias:
            if (keyCollections > 0 || _startsKey(open)) {
              return GuardFinding._(.aliasInKey, event.span.start.offset);
            }
            _finishChild(open);
          case .scalar:
            _finishChild(open);
          case .sequenceStart || .mappingStart:
            if (open.length > limit) {
              return GuardFinding._(.tooDeep, event.span.start.offset);
            }
            final isKey = _startsKey(open);
            if (isKey) keyCollections++;
            open.add(
              _Collection(isMapping: event is MappingStartEvent, isKey: isKey),
            );
          case .sequenceEnd || .mappingEnd:
            if (open.removeLast().isKey) keyCollections--;
            _finishChild(open);
          default:
        }
      }
    } on YamlException {
      return null;
    }
    return null;
  }

  /// Whether the next node starts a mapping key (keys and values alternate).
  static bool _startsKey(List<_Collection> open) =>
      open.isNotEmpty && open.last.isMapping && open.last.children.isEven;

  static void _finishChild(List<_Collection> open) {
    if (open.isNotEmpty) open.last.children++;
  }
}

/// A collection that the guard is inside of.
final class _Collection {
  _Collection({required this.isMapping, required this.isKey});

  final bool isMapping;

  /// Whether the collection is a mapping key (or inside one).
  final bool isKey;

  /// How many children have been completed.
  int children = 0;
}

/// A problem [YamlEventGuard] found.
final class GuardFinding {
  const GuardFinding._(this.problem, this.offset);

  /// The kind of problem.
  final GuardProblem problem;

  /// The offset in the checked text where the problem starts.
  final int offset;
}

/// A kind of problem [YamlEventGuard] reports.
enum GuardProblem {
  /// The text nests deeper than the limit.
  tooDeep,

  /// An alias is part of a mapping key.
  aliasInKey,
}
