import '../model/operation.dart';
import '../model/spec_node.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'names.dart';

/// Tells which keys of an operation's `responses` the client generates, and
/// reports the others (TOA657, TOA658).
///
/// A key is generated when it is a code from 200 to 299 or from 400 to 599,
/// a range of them (`2XX`, `4XX`, `5XX`, in either case) or `default`. Any
/// other key is not an HTTP status (OpenAPI allows no other), and a 1xx or
/// 3xx response has no result in the client. Nothing from such a key reaches
/// a name or an expression.
final class ResponseStatuses {
  /// Creates the check; it reports through [_context].
  const ResponseStatuses(this._context);

  final IrContext _context;

  static const _names = DartNames();
  static final _code = RegExp(r'^[1-5][0-9]{2}$');
  static final _range = RegExp(r'^[1-5]XX$', caseSensitive: false);

  /// [key] as the IR spells a status: a code, a range in upper case or
  /// `default`; null when [key] is not an HTTP status.
  static String? normalize(String key) {
    if (key == 'default' || _code.hasMatch(key)) return key;
    return _range.hasMatch(key) ? key.toUpperCase() : null;
  }

  /// Whether the client generates the response written under [key].
  static bool isGenerated(String key) => switch (normalize(key)) {
    null => false,
    final status => !status.startsWith('1') && !status.startsWith('3'),
  };

  /// The part of an inline type's name that tells the response: `Response`
  /// for a 2xx status, `Error` for 4xx, 5xx and `default`; with the status
  /// when [shared] says several responses of that kind have a body.
  /// Made a type name here, so a key is never written into a name as it is.
  static String nameOf(String status, {required bool shared}) {
    final base = status.startsWith('2') ? 'Response' : 'Error';
    if (!shared) return base;
    final word = status == 'default' ? 'Default' : status.toUpperCase();
    return _names.pascal('$base$word') ?? base;
  }

  /// The responses of [operation] the client generates, by their status as
  /// [normalize] spells it; the others are reported.
  List<(String, RefOr<Response>)> of(Operation operation) {
    final at = operation.location.child('responses');
    final result = <(String, RefOr<Response>)>[];
    final seen = <String>{};
    final outcome = operation.responses.containsKey('default')
        ? 'handled by the default response'
        : 'an undocumented status (UndocumentedStatus)';
    for (final MapEntry(:key, :value) in operation.responses.entries) {
      final status = normalize(key);
      if (status == null) {
        _context.report(
          .responseStatusInvalid,
          'The response key "$key" is not an HTTP status: use a code from '
          '100 to 599, a range such as 4XX, or default. The response is not '
          'generated.',
          at.child(key),
          fix: 'Rename or remove the key at the source.',
        );
      } else if (!isGenerated(status)) {
        _context.report(
          .responseStatusNotGenerated,
          'The $key response is not generated: the client has no result for '
          'a 1xx or 3xx status, which at run time is $outcome.',
          at.child(key),
        );
      } else if (!seen.add(status)) {
        _context.report(
          .responseStatusInvalid,
          'The response key "$key" repeats another key that differs only in '
          'case, so the response is not generated.',
          at.child(key),
          fix: 'Remove one of the keys at the source.',
        );
      } else {
        result.add((status, value));
      }
    }
    return result;
  }

  /// How many responses of each kind (success or error, by the base of
  /// [nameOf]) declare an inline body type. Inline names carry the status
  /// only when several do; a response read as bytes or text, also a form or
  /// multipart one, declares nothing and does not count.
  static Map<String, int> bodyCounts(List<PickedResponse> responses) {
    final counts = <String, int>{};
    for (final (status, _, (contentType, media)) in responses) {
      final kind = contentType == null
          ? null
          : MediaTypePicker.kindOf(contentType);
      if (kind != .json && kind != .eventStream) continue;
      if (media?.schema == null && media?.itemSchema == null) continue;
      final base = nameOf(status, shared: false);
      counts[base] = (counts[base] ?? 0) + 1;
    }
    return counts;
  }
}
