/// A long pause after many failed reconnection attempts in a row
/// (`SseOptions.cooldown`).
///
/// After [after] consecutive failed attempts the stream waits [duration]
/// instead of the next backoff delay, and the count of failed attempts
/// starts again, so the backoff restarts from its first delay.
final class SseCooldown {
  /// Creates a cooldown of [duration] after [after] failed attempts.
  const SseCooldown({required this.after, required this.duration})
    : assert(after > 0, 'after must be positive');

  /// No cooldown: in a call's options it switches off a default cooldown.
  static const SseCooldown none = SseCooldown(
    after: 1,
    duration: Duration.zero,
  );

  /// Whether this is [none].
  bool get isNone => this == none;

  /// How many failed attempts in a row start the cooldown.
  final int after;

  /// How long the cooldown lasts.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is SseCooldown &&
      other.after == after &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(after, duration);
}
