import 'tree_hash.dart';

/// What `corpus.lock` records of one client of one `union` mode: the hash of
/// each generated file and of the whole output, and the count of its
/// diagnostics by code.
final class ClientLock {
  /// Creates the record; [files] is empty for a client that is skipped.
  const ClientLock({required this.files, required this.diagnostics});

  /// Reads the record from its JSON [json].
  factory ClientLock.fromJson(Map<String, Object?> json) => ClientLock(
    files: {
      for (final MapEntry(:key, :value)
          in ((json['files'] ?? const <String, Object?>{}) as Map).entries)
        '$key': '$value',
    },
    diagnostics: {
      for (final MapEntry(:key, :value) in (json['diagnostics'] as Map).entries)
        '$key': value as int,
    },
  );

  /// The SHA-256 of each generated file, by its path in the output.
  final Map<String, String> files;

  /// The number of diagnostics of the client by code (`TOA201`).
  final Map<String, int> diagnostics;

  /// The hash of the whole output ([TreeHash] of [files]); null when the
  /// client is skipped.
  String? get output => files.isEmpty ? null : const TreeHash().combine(files);

  /// The record as JSON, keys sorted.
  Map<String, Object?> toJson() => {
    'diagnostics': _sorted(diagnostics),
    if (files.isNotEmpty) 'files': _sorted(files),
    'output': ?output,
  };

  static Map<String, T> _sorted<T>(Map<String, T> map) => Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}
