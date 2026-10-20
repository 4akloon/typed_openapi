import 'key_spec.dart';

/// The kind of value a config key holds, as the JSON Schema of the config
/// and the tests that compare it with the loader see it.
sealed class KeyType {
  const KeyType();
}

/// `true` or `false`.
final class BooleanKey extends KeyType {
  /// Creates the type.
  const BooleanKey();
}

/// A string; empty only when [allowsEmpty].
final class StringKey extends KeyType {
  /// Creates the type; [pattern] is a regular expression the whole string
  /// matches.
  const StringKey({this.pattern, this.allowsEmpty = false});

  /// The regular expression the string matches, if any.
  final String? pattern;

  /// Whether the empty string is a value.
  final bool allowsEmpty;
}

/// A whole number of at least [minimum].
final class IntegerKey extends KeyType {
  /// Creates the type.
  const IntegerKey({required this.minimum});

  /// The smallest value.
  final int minimum;
}

/// One of a fixed list of strings.
final class ChoiceKey extends KeyType {
  /// Creates the type.
  const ChoiceKey(this.values);

  /// The strings allowed.
  final List<String> values;
}

/// A list whose items are all [item].
final class ListKey extends KeyType {
  /// Creates the type.
  const ListKey(this.item, {this.minItems = 0});

  /// The type of every item.
  final KeyType item;

  /// The fewest items.
  final int minItems;
}

/// A mapping with the fixed [keys] and nothing else.
final class ObjectKey extends KeyType {
  /// Creates the type.
  const ObjectKey(this.keys);

  /// The keys the mapping may have.
  final List<KeySpec> keys;
}

/// A mapping with any keys whose values are all [value].
final class MapKey extends KeyType {
  /// Creates the type; [keyPattern] is what every key matches, and
  /// [invalidKeys] are keys it rejects (for the tests).
  const MapKey(
    this.value, {
    this.minProperties = 0,
    this.keyPattern,
    this.invalidKeys = const [],
  });

  /// The type of every value.
  final KeyType value;

  /// The fewest entries.
  final int minProperties;

  /// The regular expression every key matches, if any.
  final String? keyPattern;

  /// Keys [keyPattern] rejects.
  final List<String> invalidKeys;
}

/// Diagnostic codes, by id or by name, mapped to the level they get.
final class CodeLevelsKey extends KeyType {
  /// Creates the type.
  const CodeLevelsKey();
}

/// Normalizer rule names mapped to whether they run.
final class RuleFlagsKey extends KeyType {
  /// Creates the type.
  const RuleFlagsKey();
}

/// [inner] or `null`.
final class NullableKey extends KeyType {
  /// Creates the type.
  const NullableKey(this.inner);

  /// The type of a value that is not null.
  final KeyType inner;
}

/// Exactly one of [options].
final class OneOfKey extends KeyType {
  /// Creates the type.
  const OneOfKey(this.options);

  /// The types, of which a value matches one.
  final List<KeyType> options;
}

/// A mapping whose keys and values the schema does not describe.
final class FreeObjectKey extends KeyType {
  /// Creates the type.
  const FreeObjectKey();
}

/// Any JSON value.
final class AnyKey extends KeyType {
  /// Creates the type.
  const AnyKey();
}
