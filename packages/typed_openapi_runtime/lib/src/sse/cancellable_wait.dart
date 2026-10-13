import 'dart:async';

/// The wait before a reconnection attempt, which a cancel cuts short: the
/// default one is a timer that [cancel] stops, so a cancelled stream does
/// not keep the program alive for up to the longest delay.
final class CancellableWait {
  /// Creates a wait that uses [_custom] (`SseOptions.wait`) when it is not
  /// null, else a timer.
  CancellableWait(this._custom);

  final Future<void> Function(Duration delay)? _custom;
  Timer? _timer;
  Completer<void>? _sleeping;

  /// Waits [delay]; completes early after [cancel].
  Future<void> wait(Duration delay) {
    if (_custom case final custom?) return custom(delay);
    final sleeping = Completer<void>();
    _sleeping = sleeping;
    _timer = Timer(delay, sleeping.complete);
    return sleeping.future;
  }

  /// Stops the timer of a wait in progress and completes it.
  void cancel() {
    _timer?.cancel();
    if (_sleeping case final sleeping? when !sleeping.isCompleted) {
      sleeping.complete();
    }
  }
}
