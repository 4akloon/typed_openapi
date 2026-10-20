import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  test('cancel: the call\'s signal wins, else the default\'s', () {
    final fromDefaults = CancelSignal();
    final fromCall = CancelSignal();
    expect(
      CallOptions(
        cancel: fromDefaults,
      ).merge(CallOptions(cancel: fromCall)).cancel,
      same(fromCall),
    );
    expect(
      CallOptions(cancel: fromDefaults).merge(const CallOptions()).cancel,
      same(fromDefaults),
    );
  });

  test('headers: union; the call wins per name case-insensitively and '
      'keeps its spelling', () {
    final merged = const CallOptions(
      headers: {'X-Trace': 'd', 'Accept': 'a'},
    ).merge(const CallOptions(headers: {'x-trace': 'c'}));
    expect(merged.headers, {'Accept': 'a', 'x-trace': 'c'});
  });

  test('headers: a null call value removes the default header', () {
    final merged = const CallOptions(
      headers: {'X-Trace': 'd'},
    ).merge(const CallOptions(headers: {'x-trace': null}));
    expect(merged.headers, {'x-trace': null});
    expect(merged.headers.containsKey('X-Trace'), isFalse);
  });

  test('extra: union, the call wins per key, null is a value', () {
    final merged = const CallOptions(
      extra: {'a': 1, 'b': 2},
    ).merge(const CallOptions(extra: {'b': null}));
    expect(merged.extra, {'a': 1, 'b': null});
  });

  test('progress callbacks: the call\'s wins, else the default\'s', () {
    void defaultSend(int c, int t) {}
    void defaultReceive(int c, int t) {}
    void callSend(int c, int t) {}
    final defaults = CallOptions(
      onSendProgress: defaultSend,
      onReceiveProgress: defaultReceive,
    );
    final merged = defaults.merge(CallOptions(onSendProgress: callSend));
    expect(merged.onSendProgress, same(callSend));
    expect(merged.onReceiveProgress, same(defaultReceive));
  });

  test('sse: merged with SseOptions.merge', () {
    final merged = const CallOptions(
      sse: SseOptions(delay: Duration(seconds: 2), jitter: 0.1),
    ).merge(const CallOptions(sse: SseOptions(jitter: 0.5)));
    expect(merged.sse?.delay, const Duration(seconds: 2));
    expect(merged.sse?.jitter, 0.5);
  });

  test('merge(null) returns the defaults', () {
    const defaults = CallOptions(headers: {'A': 'b'});
    expect(defaults.merge(null), same(defaults));
  });
}
