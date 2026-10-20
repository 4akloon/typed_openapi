import 'package:test/test.dart';
import 'package:typed_openapi_client/src/sse/sse_settings.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  SseSettings merged(SseOptions defaults, SseOptions call) =>
      SseSettings.of(defaults.merge(call));

  test('SseSettings.of(null) applies the built-in defaults', () {
    final settings = SseSettings.of(null);
    expect(settings.delay, const Duration(seconds: 1));
    expect(settings.maxDelay, const Duration(seconds: 30));
    expect(settings.maxAttempts, 5);
    expect(settings.jitter, 0);
    expect(settings.idleTimeout, isNull);
    expect(settings.handshakeTimeout, isNull);
    expect(settings.cooldown, isNull);
    expect(settings.reconnect, isNull);
    expect(settings.retryOpen, isNull);
    expect(settings.retryWhen, isNull);
  });

  test('maxAttempts: null is unlimited and an omitted maxAttempts is 5', () {
    expect(
      SseSettings.of(const SseOptions(maxAttempts: null)).maxAttempts,
      isNull,
    );
    expect(SseSettings.of(const SseOptions()).maxAttempts, 5);
    expect(const SseOptions(maxAttempts: 3).maxAttempts, 3);
    expect(const SseOptions().maxAttempts, isNull);
  });

  test('Duration.zero switches off a timeout', () {
    final settings = SseSettings.of(
      const SseOptions(
        idleTimeout: Duration.zero,
        handshakeTimeout: Duration.zero,
        cooldown: SseCooldown.none,
      ),
    );
    expect(settings.idleTimeout, isNull);
    expect(settings.handshakeTimeout, isNull);
    expect(settings.cooldown, isNull);
  });

  test('merge: a value the call sets wins, field by field', () {
    final settings = merged(
      const SseOptions(
        reconnect: true,
        jitter: 0.2,
        idleTimeout: Duration(seconds: 60),
      ),
      const SseOptions(reconnect: false),
    );
    expect(settings.reconnect, false);
    expect(settings.jitter, 0.2);
    expect(settings.idleTimeout, const Duration(seconds: 60));
  });

  test('maxAttempts: every negative value counts as omitted', () {
    expect(SseSettings.of(const SseOptions(maxAttempts: -2)).maxAttempts, 5);
    expect(const SseOptions(maxAttempts: -2).maxAttempts, isNull);
    final merged = const SseOptions(maxAttempts: 2).merge(
      const SseOptions(maxAttempts: -2),
    );
    expect(merged.maxAttempts, 2);
  });

  test('merge: an omitted maxAttempts inherits the default, unlimited '
      'included', () {
    const call = SseOptions(reconnect: true);
    expect(
      merged(const SseOptions(maxAttempts: null), call).maxAttempts,
      isNull,
    );
    expect(merged(const SseOptions(maxAttempts: 2), call).maxAttempts, 2);
  });

  test('merge: an explicit null maxAttempts wins over an int', () {
    expect(
      merged(
        const SseOptions(maxAttempts: 2),
        const SseOptions(maxAttempts: null),
      ).maxAttempts,
      isNull,
    );
    expect(
      merged(
        const SseOptions(maxAttempts: null),
        const SseOptions(maxAttempts: 1),
      ).maxAttempts,
      1,
    );
  });

  test('merge: off values override a default', () {
    final settings = merged(
      const SseOptions(
        idleTimeout: Duration(seconds: 60),
        cooldown: SseCooldown(after: 10, duration: Duration(minutes: 5)),
        jitter: 0.2,
        retryOpen: true,
      ),
      const SseOptions(
        idleTimeout: Duration.zero,
        cooldown: SseCooldown.none,
        jitter: 0,
        retryOpen: false,
      ),
    );
    expect(settings.idleTimeout, isNull);
    expect(settings.cooldown, isNull);
    expect(settings.jitter, 0);
    expect(settings.retryOpen, false);
  });

  test('merge: retryWhen and onTrace of the call replace the default', () {
    bool never(Failure<Object?, Object?> _) => false;
    bool always(Failure<Object?, Object?> _) => true;
    void quiet(SseTrace _) {}
    void loud(SseTrace _) {}
    final settings = merged(
      SseOptions(retryWhen: never, onTrace: quiet),
      SseOptions(retryWhen: always, onTrace: loud),
    );
    expect(settings.retryWhen, same(always));
    expect(settings.onTrace, same(loud));
  });

  test('merge(null) returns the defaults', () {
    const defaults = SseOptions(reconnect: true);
    expect(identical(defaults.merge(null), defaults), isTrue);
  });

  test('a cooldown equal to none by value is none', () {
    // Built at run time, so it is not the canonical const instance.
    final after = [1].single;
    final copy = SseCooldown(after: after, duration: Duration.zero);
    expect(identical(copy, SseCooldown.none), isFalse);
    expect(copy.isNone, isTrue);
    expect(copy.hashCode, SseCooldown.none.hashCode);
    expect(
      const SseCooldown(after: 2, duration: Duration.zero).isNone,
      isFalse,
    );
  });
}
