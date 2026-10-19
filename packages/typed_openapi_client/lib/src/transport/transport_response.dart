/// The raw answer of a `ClientTransport`, of any status.
final class TransportResponse {
  /// Creates a response.
  const TransportResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  /// The HTTP status code.
  final int statusCode;

  /// The response headers, names in lower case; a name maps to its values.
  final Map<String, List<String>> headers;

  /// The body, read once. A failure while it is read is a
  /// `TransportException` error of the stream.
  final Stream<List<int>> body;

  @override
  String toString() => 'TransportResponse($statusCode)';
}
