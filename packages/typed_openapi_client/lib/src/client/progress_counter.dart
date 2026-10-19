/// Reports the bytes of a request or response body as they pass, as
/// `CallOptions.onSendProgress` and `onReceiveProgress` want them.
final class ProgressCounter {
  /// Reports to [onProgress]; null counts nothing.
  const ProgressCounter(this.onProgress);

  /// Called with the bytes so far and the total.
  final void Function(int count, int total)? onProgress;

  /// [stream], reporting after each chunk the bytes so far and [total]
  /// (`-1` when the total is not known).
  Stream<List<int>> count(Stream<List<int>> stream, int total) {
    final report = onProgress;
    if (report == null) return stream;
    var count = 0;
    return stream.map((chunk) {
      count += chunk.length;
      report(count, total);
      return chunk;
    });
  }
}
