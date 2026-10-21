import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_tracer.dart';
import '../sse/traced_items.dart';

/// Adds the traces of the whole stream to what `EventOpener.open` returns.
final class TracedResult {
  /// Creates the wrapper that reports to [tracer].
  const TracedResult(this.tracer);

  /// Where the traces go.
  final SseTracer tracer;

  /// [result] with its items traced; a result without a stream is traced as
  /// an error and the end of the call.
  Result<Stream<SseItem<T>>, E> wrap<T, E>(
    Result<Stream<SseItem<T>>, E> result,
  ) {
    switch (result) {
      case Success(:final data, :final statusCode, :final headers):
        return Success(
          TracedItems<T>(tracer).bind(data),
          statusCode: statusCode,
          headers: headers,
        );
      case final Failure<Stream<SseItem<T>>, E> failure:
        tracer.failed(failure);
    }
    tracer.closed();
    return result;
  }
}
