import 'dart:math';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import 'yaml_reporter.dart';

/// The nesting depth and the node budget of one composition; a document that
/// goes over either is reported and not read.
final class YamlLimits {
  /// Creates the limits of a text of [textLength] characters; [mayHaveAliases]
  /// tells the report which cause to name when the budget is spent.
  YamlLimits(
    this._reporter, {
    required int textLength,
    required bool mayHaveAliases,
  }) : _budget = max(minBudget, budgetPerChar * textLength),
       _mayHaveAliases = mayHaveAliases;

  /// The deepest nesting a document may have.
  static const maxDepth = 1000;

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = 16000000;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = 20;

  final YamlReporter _reporter;
  final bool _mayHaveAliases;
  int _budget;
  bool _hasFailed = false;
  int _open = 0;

  /// Whether a limit was reached; the composition stops.
  bool get hasFailed => _hasFailed;

  /// How many collections are open, skipped ones included: the level a
  /// collection that starts now has.
  int get open => _open;

  /// Opens a collection at [span]; false after reporting that it is deeper
  /// than [maxDepth].
  bool enter(SourceSpan span) {
    final level = _open++;
    if (level <= maxDepth) return true;
    _fail(
      .nestingTooDeep,
      'The document nests deeper than $maxDepth levels.',
      null,
      span,
    );
    return false;
  }

  /// Closes the innermost open collection.
  void leave() => _open--;

  /// Accepts [level], the depth a node copied from an alias reaches at
  /// [pointer]; false after reporting that it is deeper than [maxDepth].
  bool acceptExpandedLevel(int level, JsonPointer pointer, SourceSpan span) {
    if (level <= maxDepth) return true;
    _fail(
      .nestingTooDeep,
      'The document nests deeper than $maxDepth levels, counting what its '
      'aliases expand to.',
      pointer,
      span,
    );
    return false;
  }

  /// Charges the node at [pointer] to the budget; false after reporting that
  /// it is spent.
  bool charge(JsonPointer pointer, SourceSpan span) {
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

  void _fail(
    DiagnosticCode code,
    String message,
    JsonPointer? pointer,
    SourceSpan span, {
    String? fix,
  }) {
    _hasFailed = true;
    _reporter.report(code, message, pointer: pointer, span: span, fix: fix);
  }
}
