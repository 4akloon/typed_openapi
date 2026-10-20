import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/spec_node.dart';
import 'dart_type.dart';

/// The names a client's API lock keeps (M12, decision 5): the name of each
/// declaration by its spec location and of each method by its operation,
/// so that a run keeps them whatever was added to the spec.
final class NameLock {
  /// Creates a lock of [types] and [methods], keyed against the spec whose
  /// root document is [root].
  const NameLock({
    this.root,
    this.types = const {},
    this.methods = const {},
  });

  /// No lock: every name is made from scratch.
  static const none = NameLock();

  /// The root document the keys of [types] are relative to; null for
  /// [none].
  final Uri? root;

  /// The name of each declaration, by [declarationKey].
  final Map<String, String> types;

  /// The name of each method, by [methodKey].
  final Map<String, String> methods;

  /// The identity of [location] in a spec whose root document is [root]:
  /// the file relative to the directory of the root document (empty for
  /// the root document itself), then the JSON pointer.
  static String locationKey(SpecLocation location, Uri root) {
    final document = location.document;
    final file = document == root
        ? ''
        : p.url.relative(document.path, from: p.url.dirname(root.path));
    return '$file${location.pointer.value}';
  }

  /// The identity of the declaration [id]: its location, with `@input` or
  /// `@patch` for the request models of a split schema.
  static String declarationKey(DeclId id, Uri root) => switch (id.variant) {
    .base => locationKey(id.location, root),
    .input => '${locationKey(id.location, root)}@input',
    .patch => '${locationKey(id.location, root)}@patch',
  };

  /// The identity of the method of the operation [method] [path]:
  /// `GET /pets`, with `#stream` for the method that returns its events
  /// next to one that returns its body.
  static String methodKey(
    String method,
    String path, {
    required bool isStream,
  }) => '${method.toUpperCase()} $path${isStream ? '#stream' : ''}';

  /// The identity of the declaration [id] in this lock; null for [none].
  String? typeKey(DeclId id) => switch (root) {
    final root? => declarationKey(id, root),
    null => null,
  };

  String get _key => jsonEncode([
    '${root ?? ''}',
    for (final names in [types, methods])
      [
        for (final key in names.keys.toList()..sort()) [key, names[key]],
      ],
  ]);

  @override
  bool operator ==(Object other) => other is NameLock && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}
