import 'dart:convert';

import 'api_snapshot.dart';

/// Reads and writes the snapshots of clients as the text of
/// `typed_openapi.lock` (M12, decision 6): JSON with sorted keys, a type's
/// lines apart and each member on one line, so a change of the API is a
/// readable change of the file.
final class SnapshotJson {
  /// Creates the codec.
  const SnapshotJson();

  /// The version of the format.
  static const version = 1;

  /// The text of [clients], by client name.
  String encode(Map<String, ApiSnapshot> clients) {
    final out = StringBuffer('{\n  "version": $version,\n  "clients": {');
    final names = clients.keys.toList()..sort();
    for (final (i, name) in names.indexed) {
      out.write('${i == 0 ? '' : ','}\n    ${jsonEncode(name)}: {');
      final types = clients[name]!.types;
      final ids = types.keys.toList()..sort();
      for (final (j, id) in ids.indexed) {
        out
          ..write('${j == 0 ? '' : ','}\n      ${jsonEncode(id)}: ')
          ..write(_type(types[id]!));
      }
      out.write(ids.isEmpty ? '}' : '\n    }');
    }
    out.write(names.isEmpty ? '}\n}\n' : '\n  }\n}\n');
    return '$out';
  }

  String _type(SnapshotType type) {
    final lines = [
      '"name": ${jsonEncode(type.name)}',
      '"kind": ${jsonEncode(type.kind.name)}',
      if (!type.exhaustive) '"exhaustive": false',
      if (type.facts.isNotEmpty) '"facts": ${jsonEncode(_sorted(type.facts))}',
      if (type.members.isNotEmpty) '"members": ${_members(type.members)}',
    ];
    return '{\n        ${lines.join(',\n        ')}\n      }';
  }

  String _members(Map<String, SnapshotMember> members) {
    final ids = members.keys.toList()..sort();
    final lines = [
      for (final id in ids)
        '${jsonEncode(id)}: ${jsonEncode(_member(members[id]!))}',
    ];
    return '{\n          ${lines.join(',\n          ')}\n        }';
  }

  static Map<String, Object?> _member(SnapshotMember member) => {
    'name': member.name,
    'kind': member.kind.name,
    'owner': ?member.owner,
    if (member.facts.isNotEmpty) 'facts': _sorted(member.facts),
  };

  static Map<String, String> _sorted(Map<String, String> facts) => {
    for (final key in facts.keys.toList()..sort()) key: facts[key]!,
  };

  /// The snapshots of [text] by client name.
  ///
  /// Throws a [FormatException] when [text] is not JSON of this format.
  Map<String, ApiSnapshot> decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('not JSON: ${e.message}');
    }
    if (json case {
      'version': version,
      'clients': final Map<String, Object?> clients,
    }) {
      return {
        for (final MapEntry(:key, :value) in clients.entries)
          key: ApiSnapshot(_types(_map(value, key))),
      };
    }
    throw const FormatException(
      'expected an object with "version": $version and "clients"',
    );
  }

  static Map<String, SnapshotType> _types(Map<String, Object?> json) => {
    for (final MapEntry(:key, :value) in json.entries)
      key: switch (value) {
        {
              'name': final String name,
              'kind': final String kind,
            } &&
            final Map<String, Object?> type =>
          SnapshotType(
            name,
            _enum(TypeKind.values, kind, key),
            exhaustive: type['exhaustive'] != false,
            facts: _facts(type['facts'], key),
            members: {
              for (final MapEntry(key: id, :value) in _map(
                type['members'],
                key,
              ).entries)
                id: _memberOf(value, '$key $id'),
            },
          ),
        _ => throw FormatException('type "$key" has no name or kind'),
      },
  };

  static SnapshotMember _memberOf(Object? json, String at) => switch (json) {
    {'name': final String name, 'kind': final String kind} &&
        final Map<String, Object?> member =>
      SnapshotMember(
        name,
        _enum(MemberKind.values, kind, at),
        owner: switch (member['owner']) {
          final String owner => owner,
          null => null,
          _ => throw FormatException('member "$at" has an owner not a string'),
        },
        facts: _facts(member['facts'], at),
      ),
    _ => throw FormatException('member "$at" has no name or kind'),
  };

  static Map<String, String> _facts(Object? json, String at) => {
    for (final MapEntry(:key, :value) in _map(json, at).entries)
      key: value is String
          ? value
          : throw FormatException('fact "$key" of "$at" is not a string'),
  };

  /// [json] as an object; an absent one is empty.
  static Map<String, Object?> _map(Object? json, String at) => switch (json) {
    null => const {},
    final Map<String, Object?> map => map,
    _ => throw FormatException('"$at" is not an object'),
  };

  static T _enum<T extends Enum>(List<T> values, String name, String at) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('"$at" has an unknown kind "$name"');
  }
}
