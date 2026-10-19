import 'dart:async';

/// The cancellation of a call: the caller calls [cancel], and the sender
/// and the transport listen to [whenCancelled].
///
/// One signal may serve several calls; a cancelled signal stays cancelled,
/// so a call made with it afterwards is cancelled before it is sent.
///
/// A signal is meant for one call or one scope (a screen, a group of
/// requests). Every call that listens adds a listener that lives as long as
/// the signal, so do not reuse one signal for an unbounded number of calls.
base class CancelSignal {
  /// Creates a signal that is not cancelled.
  CancelSignal();

  final Completer<void> _cancelled = Completer<void>();
  Object? _reason;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// What the first [cancel] was given; null before it, or when it was
  /// given nothing.
  Object? get reason => _reason;

  /// Completes when [cancel] is first called.
  Future<void> get whenCancelled => _cancelled.future;

  /// Cancels the calls that use this signal, for [reason]; a later call
  /// does nothing.
  void cancel([Object? reason]) {
    if (isCancelled) return;
    _reason = reason;
    _cancelled.complete();
  }

  @override
  String toString() =>
      isCancelled ? 'CancelSignal(cancelled: $_reason)' : 'CancelSignal()';
}
