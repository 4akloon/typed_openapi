import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';

/// The cases of failures: a refused connection and cancellation before and
/// during a call.
final class FailureCases {
  /// Creates the cases on [context].
  const FailureCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a refused connection is a connection failure', _refused)
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

  Future<void> _cancelBefore() async {
    final signal = CancelSignal()..cancel('early');
    final result = await context.sender.send(
      ConformanceContext.request('/echo'),
      ConformanceContext.echo,
      call: CallOptions(cancel: signal),
    );
    expect(result, isA<Cancelled<Map<String, Object?>, Never>>());
  }

  Future<void> _cancelInFlight() async {
    final signal = CancelSignal();
    final watch = Stopwatch()..start();
    Timer(const Duration(milliseconds: 200), signal.cancel);
    final result = await context.sender.send(
      ConformanceContext.request('/slow'),
      ConformanceContext.echo,
      call: CallOptions(cancel: signal),
    );
    expect(result, isA<Cancelled<Map<String, Object?>, Never>>());
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
  }
}
