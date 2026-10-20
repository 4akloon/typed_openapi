import 'dart:math';

import '../result/result.dart';
import 'sse_cooldown.dart';
import 'sse_options.dart';
import 'sse_trace.dart';

/// The [SseOptions] of one call with the built-in defaults applied: nothing
/// is unset any more. Built once per call from the merged options.
final class SseSettings {
  SseSettings._({
    required this.reconnect,
    required this.delay,
    required this.maxDelay,
    required this.maxAttempts,
    required this.idleTimeout,
    required this.handshakeTimeout,
    required this.jitter,
    required this.cooldown,
    required this.random,
    required this.onTrace,
    required this.wait,
    required this.retryOpen,
    required this.retryWhen,
  });

  /// Applies the built-in defaults to [options] (null is all unset).
  factory SseSettings.of(SseOptions? options) {
    final idle = options?.idleTimeout;
    final handshake = options?.handshakeTimeout;
    final cooldown = options?.cooldown;
    return SseSettings._(
      reconnect: options?.reconnect,
      delay: options?.delay ?? const Duration(seconds: 1),
      maxDelay: options?.maxDelay ?? const Duration(seconds: 30),
      maxAttempts: options == null || !options.hasMaxAttempts
          ? defaultMaxAttempts
          : options.maxAttempts,
      idleTimeout: idle == Duration.zero ? null : idle,
      handshakeTimeout: handshake == Duration.zero ? null : handshake,
      jitter: options?.jitter ?? 0,
      cooldown: cooldown == null || cooldown.isNone ? null : cooldown,
      random: options?.random,
      onTrace: options?.onTrace,
      wait: options?.wait,
      retryOpen: options?.retryOpen,
      retryWhen: options?.retryWhen,
    );
  }

  /// The attempts in a row that may fail when `maxAttempts` is omitted.
  static const int defaultMaxAttempts = 5;

  /// Whether the stream reconnects; null keeps the operation's setting.
  final bool? reconnect;

  /// The first delay when the server sent no `retry`.
  final Duration delay;

  /// The longest delay a doubling reaches, before jitter.
  final Duration maxDelay;

  /// The failed attempts in a row that end the stream; null never gives up.
  final int? maxAttempts;

  /// The longest silence on a connected stream, or null for no limit.
  final Duration? idleTimeout;

  /// The longest wait for the response headers, or null for no limit.
  final Duration? handshakeTimeout;

  /// The share, from 0 to 1, by which each backoff delay is spread.
  final double jitter;

  /// The long pause after many failed attempts, or null for none.
  final SseCooldown? cooldown;

  /// The source of jitter, or null for a fresh `Random()`.
  final Random? random;

  /// Called with each trace step, or null.
  final void Function(SseTrace trace)? onTrace;

  /// Waits a delay before an attempt, or null for a cancellable timer.
  final Future<void> Function(Duration delay)? wait;

  /// Whether a failure to open is retried; null follows the reconnection
  /// policy.
  final bool? retryOpen;

  /// The classifier of transient failures, or null for the built-in one.
  final bool Function(Failure<Object?, Object?> failure)? retryWhen;

  /// The delay before [attempt] (1 for the first), given the server's last
  /// [retry], without jitter.
  Duration delayBefore(int attempt, Duration? retry) {
    final first = retry ?? delay;
    final cap = first > maxDelay ? first : maxDelay;
    var result = first;
    for (var i = 1; i < attempt && result < cap; i++) {
      result *= 2;
    }
    return result > cap ? cap : result;
  }
}
