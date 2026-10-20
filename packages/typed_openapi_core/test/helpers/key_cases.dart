import 'package:typed_openapi_core/src/schema/key_spec.dart';
import 'package:typed_openapi_core/src/schema/key_type.dart';

/// One document a schema and the loader are both asked about.
final class KeyCase {
  /// Creates a case.
  const KeyCase(this.name, this.document, {required this.isValid});

  /// What the case checks, unique within a [KeyCases].
  final String name;

  /// The whole document, decoded JSON.
  final Map<String, Object?> document;

  /// Whether the document is valid.
  final bool isValid;
}

/// The documents that probe every key of one container of a config or
/// overrides file: a valid example of each key, an unknown key, a missing
/// required key, and for every key reached inside it the values it allows
/// and the ones it must reject.
final class KeyCases {
  /// Creates the cases of the container [place] with the [keys] it allows;
  /// [base] is what it needs to be valid and [wrap] puts a container into a
  /// whole document.
  const KeyCases({
    required this.place,
    required this.keys,
    required this.base,
    required this.wrap,
  });

  /// The name of the container, which starts every case name.
  final String place;

  /// The keys the container allows.
  final List<KeySpec> keys;

  /// What the container has in every case.
  final Map<String, Object?> base;

  /// Puts a container into a whole document.
  final Map<String, Object?> Function(Map<String, Object?> container) wrap;

  /// The cases, each name once.
  Iterable<KeyCase> all() {
    final seen = <String>{};
    return [
      for (final probe in _probes())
        if (seen.add(probe.name)) probe,
    ];
  }

  Iterable<KeyCase> _probes() sync* {
    for (final key in keys) {
      final container = {...base, key.name: key.example};
      yield _case('${key.name} example', container, isValid: true);
      for (final variant in _Variants.of(key.type, key.example, key)) {
        yield _case(
          '${key.name}${variant.path.map((p) => '.$p').join()} '
          '${variant.label}',
          _setAt(container, [key.name, ...variant.path], variant.value)
              as Map<String, Object?>,
          isValid: variant.isValid,
        );
      }
    }
    yield _case('unknown key', {...base, 'bogus': 1}, isValid: false);
    for (final name in base.keys) {
      yield _case(
        'without $name',
        {...base}..remove(name),
        isValid: false,
      );
    }
  }

  KeyCase _case(
    String name,
    Map<String, Object?> container, {
    required bool isValid,
  }) => KeyCase('$place $name', wrap(container), isValid: isValid);

  static Object? _setAt(Object? node, List<Object> path, Object? value) {
    if (path.isEmpty) return value;
    final rest = path.sublist(1);
    return switch (node) {
      final Map<String, Object?> map => <String, Object?>{
        ...map,
        '${path.first}': _setAt(map['${path.first}'], rest, value),
      },
      final List<Object?> list => [
        for (final (i, item) in list.indexed)
          if (i == path.first) _setAt(item, rest, value) else item,
      ],
      _ => value,
    };
  }
}

/// A value put in place of a key's example, and whether it is valid there.
final class _Variant {
  const _Variant(this.path, this.label, this.value, {required this.isValid});

  final List<Object> path;
  final String label;
  final Object? value;
  final bool isValid;
}

/// The variants of the value of one key, found by walking its type.
final class _Variants {
  const _Variants._();

  static Iterable<_Variant> of(
    KeyType type,
    Object? example,
    KeySpec spec, [
    List<Object> path = const [],
  ]) sync* {
    _Variant at(String label, Object? value, {required bool isValid}) =>
        _Variant(path, label, value, isValid: isValid);
    switch (type) {
      case BooleanKey():
        yield at('is text', 'text', isValid: false);
        if (example case final bool flag) {
          yield at('is ${!flag}', !flag, isValid: true);
        }
      case StringKey(:final allowsEmpty):
        yield at('is a number', 1, isValid: false);
        if (!allowsEmpty) yield at('is empty', '', isValid: false);
        for (final bad in spec.invalidExamples) {
          yield at('is "$bad"', bad, isValid: false);
        }
      case IntegerKey(:final minimum):
        yield at('is text', 'text', isValid: false);
        yield at('is ${minimum - 1}', minimum - 1, isValid: false);
        yield at('is $minimum', minimum, isValid: true);
      case ChoiceKey(:final values):
        for (final value in values) {
          yield at('is $value', value, isValid: true);
        }
        yield at('is an unknown choice', 'bogus', isValid: false);
        yield at('is a number', 1, isValid: false);
      case ListKey(:final item, :final minItems):
        yield at('is text', 'text', isValid: false);
        yield at('is empty', <Object?>[], isValid: minItems == 0);
        if (example case [final first, ...]) {
          yield* of(item, first, spec, [...path, 0]);
        }
      case ObjectKey(:final keys):
        yield* _object(keys, example, spec, path);
      case MapKey():
        yield* _map(type, example, spec, path);
      case CodeLevelsKey() || RuleFlagsKey():
        yield at('is text', 'text', isValid: false);
        yield at('is empty', <String, Object?>{}, isValid: true);
      case NullableKey() || OneOfKey() || FreeObjectKey() || AnyKey():
        break;
    }
  }

  static Iterable<_Variant> _object(
    List<KeySpec> keys,
    Object? example,
    KeySpec spec,
    List<Object> path,
  ) sync* {
    if (example is! Map<String, Object?>) return;
    _Variant at(String label, Object? value, {required bool isValid}) =>
        _Variant(path, label, value, isValid: isValid);
    yield at('is text', 'text', isValid: false);
    yield at('has an unknown key', {...example, 'bogus': 1}, isValid: false);
    final required = keys.where((key) => key.isRequired).toList();
    if (required.isEmpty) {
      yield at('is empty', <String, Object?>{}, isValid: true);
    }
    for (final key in required) {
      yield at(
        'without ${key.name}',
        {...example}..remove(key.name),
        isValid: false,
      );
    }
    for (final key in keys) {
      yield* of(key.type, example[key.name], key, [...path, key.name]);
    }
  }

  static Iterable<_Variant> _map(
    MapKey type,
    Object? example,
    KeySpec spec,
    List<Object> path,
  ) sync* {
    if (example is! Map<String, Object?>) return;
    _Variant at(String label, Object? value, {required bool isValid}) =>
        _Variant(path, label, value, isValid: isValid);
    yield at('is text', 'text', isValid: false);
    yield at('is empty', <String, Object?>{}, isValid: type.minProperties == 0);
    if (example.entries.firstOrNull case final first?) {
      for (final bad in type.invalidKeys) {
        yield at('has the key "$bad"', {
          ...example,
          bad: first.value,
        }, isValid: false);
      }
      yield* of(type.value, first.value, spec, [...path, first.key]);
    }
  }
}
