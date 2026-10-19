import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  test('a new signal is not cancelled and has no reason', () {
    final signal = CancelSignal();
    expect(signal.isCancelled, isFalse);
    expect(signal.reason, isNull);
  });

  test('cancel completes whenCancelled and keeps the first reason', () async {
    final signal = CancelSignal();
    var completed = false;
    signal.whenCancelled.then((_) => completed = true);
    signal
      ..cancel('first')
      ..cancel('second');
    await Future<void>.delayed(Duration.zero);
    expect(completed, isTrue);
    expect(signal.isCancelled, isTrue);
    expect(signal.reason, 'first');
  });

  test('a TransportException names its kind', () {
    const exception = TransportException(
      TransportExceptionKind.timeout,
      'no answer in 1 s',
    );
    expect('$exception', 'TransportException(timeout): no answer in 1 s');
  });
}
