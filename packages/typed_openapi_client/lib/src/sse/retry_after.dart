import '../result/result.dart';
import 'http_date.dart';

/// Reads a `Retry-After` header: the server's "not before" for one retry.
final class RetryAfter {
  const RetryAfter._();

  /// Longest delta-seconds text read, so a [Duration] never overflows.
  static const _maxDigits = 9;

  /// The wait [value] asks for, or null when it is unparsable, zero or in
  /// the past.
  ///
  /// [value] is delta-seconds or an HTTP date. A date is measured against
  /// [responseDate] (the response's `Date` header, which avoids clock skew)
  /// when that parses, else against [now].
  static Duration? parse(
    String value, {
    required DateTime now,
    String? responseDate,
  }) {
    final text = value.trim();
    if (text.isNotEmpty && text.length <= _maxDigits && _isDigits(text)) {
      final seconds = int.parse(text);
      return seconds > 0 ? Duration(seconds: seconds) : null;
    }
    final target = HttpDate.parse(text, now: now);
    if (target == null) return null;
    final from =
        (responseDate == null
            ? null
            : HttpDate.parse(responseDate, now: now)) ??
        now;
    final wait = target.difference(from);
    return wait > Duration.zero ? wait : null;
  }

  /// The wait [failure] asks for in its `retry-after` header, or null when
  /// it has none or is not a response.
  static Duration? of(
    Failure<Object?, Object?> failure, {
    DateTime Function() clock = DateTime.now,
  }) {
    final headers = switch (failure) {
      HttpError(:final headers) => headers,
      UndocumentedStatus(:final headers) => headers,
      DecodeError(:final headers) => headers,
      _ => null,
    };
    final value = headers?['retry-after']?.firstOrNull;
    if (value == null) return null;
    return parse(
      value,
      responseDate: headers?['date']?.firstOrNull,
      now: clock().toUtc(),
    );
  }

  static bool _isDigits(String text) =>
      text.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39);
}
