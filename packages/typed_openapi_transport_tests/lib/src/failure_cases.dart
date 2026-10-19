import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of failures: a refused connection, a dropped one, a timeout and
/// cancellation before and during a call.
final class FailureCases {
  /// Creates the cases on [context].
  const FailureCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a refused connection is a connection failure', _refused)
      ..testCase(
        'a server that closes the socket is a connection failure',
        _closed,
      )
      ..testCase(
        'a timeout is a timeout failure',
        _timeout,
        unavailable: context.hasTimeoutTransport
            ? null
            : 'The suite got no createWithTimeout.',
      )
      ..testCase('a cancel before the call sends nothing', _cancelBefore)
      ..testCase('a cancel in flight is Cancelled', _cancelInFlight);
  }

  Future<void> _refused() async {
    final result = await context.refusedSender.send(
      ConformanceContext.request('/echo'),
      ConformanceContext.echo,
    );
    final failure = result as TransportError<Map<String, Object?>, Never>;
    expect(failure.exception.kind, TransportExceptionKind.connection);
  }

  Future<void> _closed() async {
    final result = await context.sender.send(
      ConformanceContext.request('/close'),
      ConformanceContext.echo,
    );
    final failure = result as TransportError<Map<String, Object?>, Never>;
    expect(failure.exception.kind, TransportExceptionKind.connection);
  }

  Future<void> _timeout() async {
    final result = await context
        .senderWithTimeout(const Duration(milliseconds: 300))
        .send(
          ConformanceContext.request('/slow/timeout'),
          ConformanceContext.echo,
        );
    final failure = result as TransportError<Map<String, Object?>, Never>;
    expect(failure.exception.kind, TransportExceptionKind.timeout);
  }

  Future<void> _cancelBefore() async {
    final signal = CancelSignal()..cancel('early');
    final result = await context.sender.send(
      ConformanceContext.request('/echo/cancel-before'),
      ConformanceContext.echo,
      call: CallOptions(cancel: signal),
    );
    expect(result, isA<Cancelled<Map<String, Object?>, Never>>());
    // The server answers `/stats` after any request that was sent.
    final stats = await context.stats();
    expect(stats['requests']!['/echo/cancel-before'], isNull);
  }

  /// Cancels once the server has the request, which holds its answer back.
  Future<void> _cancelInFlight() async {
    final signal = CancelSignal();
    final result = context.sender.send(
      ConformanceContext.request('/slow/in-flight'),
      ConformanceContext.echo,
      call: CallOptions(cancel: signal),
    );
    await context.waitForServer(
      (s) => s['requests']!['/slow/in-flight'] != null,
    );
    signal.cancel();
    expect(await result, isA<Cancelled<Map<String, Object?>, Never>>());
  }
}
