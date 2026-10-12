import '../diagnostics/diagnostic_bag.dart';
import 'composed_yaml.dart';
import 'yaml_composition.dart';
import 'yaml_limits.dart';
import 'yaml_reporter.dart';

export 'composed_yaml.dart';

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
  static const maxDepth = YamlLimits.maxDepth;

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = YamlLimits.minBudget;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = YamlLimits.budgetPerChar;

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
  }) {
    final reporter = YamlReporter(_diagnostics, file, json: json);
    final limits = YamlLimits(
      reporter,
      textLength: text.length,
      mayHaveAliases: text.contains('*'),
    );
    return YamlComposition(text, uri, reporter, limits).run();
  }
}
