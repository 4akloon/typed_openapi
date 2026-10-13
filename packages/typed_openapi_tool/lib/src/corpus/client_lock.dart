import 'tree_hash.dart';

/// What `corpus.lock` records of one client of one `union` mode: the hash of
/// each generated file and of the whole output, and the count of its
/// diagnostics by code.
final class ClientLock {
  /// Creates the record; [files] is empty and [values] null for a client
  /// that is skipped.
  const ClientLock({
    required this.files,
    required this.diagnostics,
    this.values,
  });

  /// Reads the record of the client [name] from its JSON [json]; a value
  /// of another shape is a [FormatException].
  factory ClientLock.fromJson(String name, Object? json) {
    if (json is! Map<String, Object?>) {
      throw FormatException('the client $name is not an object.');
    }
    return ClientLock(
      files: _strings(name, 'files', json['files']),
      diagnostics: _counts(name, 'diagnostics', json['diagnostics'])!,
      values: _counts(name, 'values', json['values'], required: false),
    );
  }

  static Map<String, String> _strings(String name, String field, Object? json) {
    if (json == null) return const {};
    if (json is! Map<String, Object?>) {
      throw FormatException('$name: "$field" is not an object.');
    }
    return {
      for (final MapEntry(:key, :value) in json.entries)
        key: switch (value) {
          final String text => text,
          _ => throw FormatException(
            '$name: "$field" has a value that is not a string.',
          ),
        },
    };
  }

  static Map<String, int>? _counts(
    String name,
    String field,
    Object? json, {
    bool required = true,
  }) {
    if (json == null && !required) return null;
    if (json is! Map<String, Object?>) {
      throw FormatException('$name: "$field" is not an object.');
    }
    return {
      for (final MapEntry(:key, :value) in json.entries)
        key: switch (value) {
          final int count => count,
          _ => throw FormatException(
            '$name: "$field" has a value that is not a count.',
          ),
        },
    };
  }

  /// The SHA-256 of each generated file, by its path in the output.
  final Map<String, String> files;

  /// The number of diagnostics of the client by code (`TOA201`).
  final Map<String, int> diagnostics;

  /// What the round trip of the client checked: the `examples` and the
  /// `synthetic` values that decoded, the `spec_defects` (examples that do
  /// not match their own schema) and the `failures` (values that did not
  /// come back equal, or that a synthetic value should have decoded): a
  /// known failure is a defect of the generator listed in the roadmap, and a
  /// new one changes the lock.
  final Map<String, int>? values;

  /// The hash of the whole output ([TreeHash] of [files]); null when the
  /// client is skipped.
  String? get output => files.isEmpty ? null : const TreeHash().combine(files);

  /// The record as JSON, keys sorted.
  Map<String, Object?> toJson() => {
    'diagnostics': _sorted(diagnostics),
    if (files.isNotEmpty) 'files': _sorted(files),
    'output': ?output,
    if (values case final values?) 'values': _sorted(values),
  };

  static Map<String, T> _sorted<T>(Map<String, T> map) => Map.fromEntries(
    map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}
