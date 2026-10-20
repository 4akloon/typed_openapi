import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'parse_context.dart';

/// Reports the constructs that tools for bundlers or YAML 1.1 accept and
/// OpenAPI does not: a `$ref` where no Reference Object is allowed (TOA107),
/// a `$ref` that a YAML comment emptied (TOA108) and the merge key `<<`
/// (TOA109).
final class BundlerConstructs {
  /// Creates a reporter that writes to [_context].
  const BundlerConstructs(this._context);

  /// The YAML 1.1 merge key.
  static const mergeKey = '<<';

  static const _bundleFix =
      r'A spec that puts "$ref" anywhere is written for a bundler (Redocly, '
      'swagger-cli) that resolves it as a JSON Reference. Bundle it first, '
      'for example with `redocly bundle`, and check the bundled file.';

  static final _blockComment = RegExp(r'^:?[ \t]+#');
  static final _flowComment = RegExp(r':[ \t]+#[^\n]*\n?$');

  final ParseContext _context;

  /// Whether [raw] is an object with a `$ref` key.
  static bool isRefObject(Object? raw) =>
      raw is Map<String, Object?> && raw.containsKey(r'$ref');

  /// Reports the merge key at [at].
  void reportMergeKey(JsonPointer at) {
    _context.report(
      .yamlMergeKey,
      '"<<" is a YAML 1.1 merge key; OpenAPI tools read it as a plain key '
      'named "<<", so its keys are not merged here.',
      at,
      fix: 'Write the keys out.',
    );
  }

  /// Reports a Reference Object at [at] where the spec expects [expected].
  void reportRefNotAllowed(JsonPointer at, String expected) {
    _context.report(
      .refNotAllowed,
      'OpenAPI expects $expected here, not a Reference Object, so this '
      r'"$ref" is ignored.',
      at,
      fix: _bundleFix,
    );
  }

  /// Reports a `$ref` key at [at] in an object that accepts no Reference
  /// Object.
  void reportUnexpectedRefKey(JsonPointer at) {
    _context.report(
      .refNotAllowed,
      'OpenAPI does not accept a Reference Object here, so this '
      r'"$ref" is ignored.',
      at,
      fix: _bundleFix,
    );
  }

  /// Reports the empty `$ref` at [at] whose value a YAML comment swallowed.
  void reportCommentedOutRef(JsonPointer at) {
    _context.report(
      .refCommentedOut,
      r'This "$ref" is empty: without quotes, "#" starts a YAML comment, '
      'so the reference was read as a comment.',
      at,
      fix: r"Quote the reference: $ref: '#/components/schemas/Pet'.",
    );
  }

  /// Whether the empty value at [at] was written as `key: #...`, so that
  /// the `#` started a comment.
  ///
  /// package:yaml puts an empty block value at the `:` of its key, and an
  /// empty flow value at the token after it, which is on a later line when
  /// a comment ended the line.
  bool isCommentedOut(JsonPointer at) {
    final span = _context.document.spanOf(at);
    if (span is! FileSpan) return false;
    final file = span.file;
    String lineAt(int line) => file.getText(
      file.getOffset(line),
      line + 1 < file.lines ? file.getOffset(line + 1) : file.length,
    );
    final line = span.start.line;
    final before = file.getText(file.getOffset(line), span.start.offset);
    final rest = lineAt(line).substring(before.length);
    if (_blockComment.hasMatch(rest)) return true;
    return before.trim().isEmpty &&
        line > 0 &&
        _flowComment.hasMatch(lineAt(line - 1));
  }
}
