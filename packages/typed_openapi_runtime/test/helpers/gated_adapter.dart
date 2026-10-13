import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A Dio adapter whose answers a test can hold back: [respond] is called
/// with the request and its index and may wait on a gate. It tells when a
/// request started and whether Dio cancelled it, so a test can see that a
/// request in flight is aborted.
final class GatedAdapter implements HttpClientAdapter {
  /// Answers the request number `index` with the future [respond] returns.
  GatedAdapter(this.respond);

  /// Builds the response of a request, possibly later.
  final Future<ResponseBody> Function(RequestOptions options, int index)
  respond;

  /// The requests seen, in order.
  final List<RequestOptions> requests = [];

  /// Per request, whether Dio cancelled it.
  final List<bool> cancelsFired = [];

  final Map<int, Completer<void>> _started = {};

  /// Completes when the request number [index] reaches the adapter.
  Future<void> started(int index) =>
      (_started[index] ??= Completer<void>()).future;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final index = requests.length;
    requests.add(options);
    cancelsFired.add(false);
    cancelFuture?.then(
      (_) => cancelsFired[index] = true,
      onError: (Object _) => cancelsFired[index] = true,
    );
    final started = _started[index] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    return respond(options, index);
  }

  @override
  void close({bool force = false}) {}
}
