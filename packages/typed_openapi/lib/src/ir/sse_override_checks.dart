import '../overrides/sse_override.dart';
import 'ir_context.dart';

/// Reports the generation fields of an `sse` override that change nothing
/// (TOA669). The spec fields `data` and `events` are the applier's: it
/// reports those it could not write.
final class SseOverrideChecks {
  /// Creates the checks that report to [_context].
  const SseOverrideChecks(this._context);

  final IrContext _context;

  /// Reports the generation fields of [sse] on an operation that has no
  /// event stream at all.
  void withoutStream(SseOverride sse) {
    final fields = [
      if (sse.reconnect != null) '"reconnect"',
      if (sse.method != null) '"method"',
      if (sse.keepUnknown != null) '"unknown"',
    ];
    if (fields.isEmpty) return;
    _context.reportAtPointer(
      .sseOverrideNotApplied,
      'The operation has no 2xx response with content text/event-stream, '
      'so ${fields.join(', ')} of "sse" change nothing.',
      sse.pointer,
      fix: 'Remove "sse".',
    );
  }

  /// Reports that `unknown` of [sse] has no event union to apply to.
  void unknownWithoutUnion(SseOverride sse) => _context.reportAtPointer(
    .sseOverrideNotApplied,
    'The "unknown" of "sse" changes nothing: the stream has no events by '
    'name to tell known from unknown.',
    sse.pointer.child('unknown'),
    fix:
        'Name the events with "events" (or an itemSchema in OpenAPI 3.2), '
        'or remove "unknown".',
  );
}
