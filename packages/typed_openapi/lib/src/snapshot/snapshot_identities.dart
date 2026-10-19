import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../ir/dart_type.dart';
import '../ir/ir.dart';
import '../model/spec_node.dart';

/// The stable identities of a client's API (M12, decision 1): what an entry
/// of the snapshot is keyed by, so that it is the same entry in the next
/// run whatever its Dart name.
///
/// A declaration is its spec location, with the file relative to the
/// directory of the root document (empty for the root document itself) and
/// `@input` or `@patch` for the request models of a split schema. An
/// operation is its `operationId` when no other operation of the client
/// has it, else `METHOD /path`; the method that returns its events adds
/// `#stream`.
final class SnapshotIdentities {
  /// Creates the identities of [_ir], whose spec's root document is
  /// [_root].
  SnapshotIdentities(this._ir, this._root)
    : _sharedIds = _repeatedIds(_ir.groups);

  final ClientIr _ir;
  final Uri _root;
  final Set<String> _sharedIds;

  /// The identity of a location in the spec.
  String location(SpecLocation location) {
    final document = location.document;
    final file = document == _root
        ? ''
        : p.url.relative(document.path, from: p.url.dirname(_root.path));
    return '$file${location.pointer.value}';
  }

  /// The identity of the declaration [id].
  String declaration(DeclId id) => switch (id.variant) {
    .base => location(id.location),
    .input => '${location(id.location)}@input',
    .patch => '${location(id.location)}@patch',
  };

  /// The identity of the operation of [operation], without the `#stream`
  /// of its event-stream method.
  String operation(OperationIr operation) {
    final id = operation.operationId;
    return id != null && !_sharedIds.contains(id)
        ? id
        : '${operation.method.toUpperCase()} ${operation.path}';
  }

  /// The identity of the method of [operation].
  String method(OperationIr operation) =>
      '${this.operation(operation)}${operation.events == null ? '' : '#stream'}';

  /// [type] as Dart code: what the generated code declares.
  String text(DartType type) => type.code(_ir.nameOf);

  /// [type] with declarations by identity: equal in two runs when the type
  /// is the same, whatever the declarations are named.
  String key(DartType type) => type.code(declaration);

  /// The fingerprint of documentation [texts]: the first 12 hex digits of
  /// their SHA-256; null without any.
  static String? doc(List<String?> texts) {
    final present = texts.nonNulls.toList();
    if (present.isEmpty) return null;
    final digest = sha256.convert(utf8.encode(jsonEncode(present)));
    return '$digest'.substring(0, 12);
  }

  /// The `operationId`s that more than one operation of [groups] has.
  static Set<String> _repeatedIds(List<GroupIr> groups) {
    final routes = <String, Set<String>>{};
    for (final group in groups) {
      for (final operation in group.operations) {
        if (operation.operationId case final id?) {
          (routes[id] ??= {}).add('${operation.method} ${operation.path}');
        }
      }
    }
    return {
      for (final MapEntry(:key, :value) in routes.entries)
        if (value.length > 1) key,
    };
  }
}
