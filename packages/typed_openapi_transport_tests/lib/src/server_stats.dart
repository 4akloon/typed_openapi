/// What the server counts, for the cases that check what it saw: requests
/// by path and the connections a client dropped while the server wrote.
final class ServerStats {
  final Map<String, int> _requests = {};
  final Map<String, int> _disconnects = {};

  /// How many requests the server has answered or is answering, except the
  /// ones for `/stats` and the preflight `OPTIONS` of a browser.
  int get requestCount => _requests.values.fold(0, (a, b) => a + b);

  /// Counts a request for [path].
  void request(String path) =>
      _requests.update(path, (n) => n + 1, ifAbsent: () => 1);

  /// Counts a client that went away while the server wrote to [path].
  void disconnect(String path) =>
      _disconnects.update(path, (n) => n + 1, ifAbsent: () => 1);

  /// The counts, as the `/stats` route answers them.
  Map<String, Object?> toJson() => {
    'requests': {..._requests},
    'disconnects': {..._disconnects},
  };
}
