import 'dart:convert';

import 'client_lock.dart';

/// `corpus.lock`: the generated output of every corpus client, which CI
/// compares with a new run (spec decision 2).
///
/// The file is JSON with sorted keys and two-space indentation, so the same
/// output gives the same bytes and a change is a readable diff. A client is
/// keyed `<union mode>/<name>` (`raw/stripe`).
final class CorpusLock {
  /// Creates the lock of [clients].
  const CorpusLock(this.clients);

  /// Reads the lock from its text [text].
  factory CorpusLock.parse(String text) {
    final json = jsonDecode(text) as Map<String, Object?>;
    if (json['version'] != version) {
      throw FormatException('corpus.lock: version ${json['version']}.');
    }
    return CorpusLock({
      for (final MapEntry(:key, :value)
          in (json['clients'] as Map<String, Object?>).entries)
        key: ClientLock.fromJson(value as Map<String, Object?>),
    });
  }

  /// The version of the file format.
  static const int version = 1;

  /// The record of each client, by `<union mode>/<name>`.
  final Map<String, ClientLock> clients;

  /// The text of the lock file.
  String format() {
    final keys = clients.keys.toList()..sort();
    return '${const JsonEncoder.withIndent('  ').convert({
      'clients': {for (final key in keys) key: clients[key]?.toJson()},
      'version': version,
    })}\n';
  }

  /// The differences from the [expected] lock, one line each: clients that
  /// appeared or are gone, files added, removed or changed, and codes whose
  /// count changed. Empty when the locks are equal.
  List<String> differencesFrom(CorpusLock expected) {
    final keys = {...clients.keys, ...expected.clients.keys}.toList()..sort();
    return [
      for (final key in keys)
        ..._client(key, clients[key], expected.clients[key]),
    ];
  }

  static List<String> _client(String key, ClientLock? got, ClientLock? want) {
    if (want == null) return ['$key: new client'];
    if (got == null) return ['$key: client is gone'];
    return [
      for (final path in _union(got.files, want.files))
        if (got.files[path] != want.files[path])
          '$key: ${_change(got.files[path], want.files[path])} $path',
      for (final code in _union(got.diagnostics, want.diagnostics))
        if (got.diagnostics[code] != want.diagnostics[code])
          '$key: $code ${want.diagnostics[code] ?? 0} -> '
              '${got.diagnostics[code] ?? 0}',
    ];
  }

  static String _change(String? got, String? want) => switch ((got, want)) {
    (null, _) => 'removed',
    (_, null) => 'added',
    _ => 'changed',
  };

  static List<String> _union(Map<String, Object?> a, Map<String, Object?> b) =>
      {...a.keys, ...b.keys}.toList()..sort();
}
