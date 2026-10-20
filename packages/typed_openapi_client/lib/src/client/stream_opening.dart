import '../result/result.dart';
import '../sse/cancellable_wait.dart';
import '../sse/sse_item.dart';
import '../sse/sse_reconnector.dart';
import '../transport/cancel_signal.dart';
import 'client_results.dart';
import 'event_call.dart';
import 'request_builder.dart';

/// Opens the first connection of an event stream and, when it may, tries
/// again after a transient failure, with the plan, the classifier and the
/// traces that reconnection uses.
final class StreamOpening<T, E> {
  /// Creates the opening of [event]; [connect] makes one attempt from a
  /// [SseResume].
  StreamOpening(this.event, this.connect);

  /// The call being opened.
  final EventCall<T, E> event;

  /// One connection attempt.
  final Future<Result<Stream<SseItem<T>>, E>> Function(SseResume resume)
  connect;

  static const _results = ClientResults();

  /// The result of the first connection that opens, or of the failure that
  /// ends the attempts.
  ///
  /// With [retries], a failure that `SseSettings.shouldRetry` accepts and
  /// the plan allows is traced, waited for and tried again. A cancel during
  /// the wait completes with [Cancelled] at once. An [Exception] thrown by
  /// an injected `wait` ends the opening with the failure it was waiting
  /// after; an `Error` from user code completes the future with it.
  Future<Result<Stream<SseItem<T>>, E>> open({required bool retries}) async {
    final call = event.call;
    final resume = (
      lastEventId: RequestBuilder.userLastEventId(call?.headers),
      retry: null,
    );
    final cancel = call?.cancel;
    final backoff = _Backoff(event.settings.wait, cancel);
    while (true) {
      final result = await connect(resume);
      if (!retries || result is! Failure<Stream<SseItem<T>>, E>) {
        return result;
      }
      final delay = _delayAfter(result);
      if (delay == null) return result;
      if (!await backoff.wait(delay)) return result;
      if (cancel != null && cancel.isCancelled) {
        return _results.cancelledBefore(cancel);
      }
    }
  }

  /// Traces a failed attempt and returns the wait before the next one, or
  /// null when the failure is final or the attempts are used up.
  Duration? _delayAfter(Failure<Stream<SseItem<T>>, E> failure) {
    if (!event.settings.shouldRetry(failure)) return null;
    final step = event.plan.next(null, failure: failure);
    if (step == null) return null;
    event.tracer
      ?..failed(failure)
      ..reconnecting(step.attempt, step.delay);
    return step.delay;
  }
}

/// The waits of one opening: they end early when the call is cancelled.
final class _Backoff {
  _Backoff(Future<void> Function(Duration delay)? wait, this._cancel)
    : _sleep = CancellableWait(wait);

  final CancellableWait _sleep;
  final CancelSignal? _cancel;
  // Read on the first wait only, so an opening that never waits adds no
  // listener to the signal, and once, since a signal keeps one per ask.
  Future<void>? _cancelled;

  /// Waits [delay], or until the call is cancelled; false when the wait
  /// itself threw an [Exception], which ends the opening.
  Future<bool> wait(Duration delay) async {
    final cancelled = _cancelled ??= _cancel?.whenCancelled.then(
      (_) => _sleep.cancel(),
    );
    try {
      // Inside the try: an injected wait may throw before it returns.
      final sleeping = _sleep.wait(delay);
      await (cancelled == null ? sleeping : Future.any([sleeping, cancelled]));
    } on Exception {
      return false;
    }
    return true;
  }
}
