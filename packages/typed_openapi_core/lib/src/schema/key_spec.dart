import 'key_type.dart';

/// One key of a config or overrides file: its name, the kind of value it
/// holds and what it does. The JSON Schema and the tests are made from it.
final class KeySpec {
  /// Creates a key; [example] is a value that is valid and [invalidExamples]
  /// are strings its type accepts but the loader rejects.
  const KeySpec(
    this.name,
    this.type, {
    required this.description,
    required this.example,
    this.defaultValue,
    this.isRequired = false,
    this.invalidExamples = const [],
  });

  /// Creates a key that holds a mapping with [keys]; its example is made
  /// from theirs.
  KeySpec.object(
    this.name,
    List<KeySpec> keys, {
    required this.description,
    this.isRequired = false,
  }) : type = ObjectKey(keys),
       example = {for (final key in keys) key.name: key.example},
       defaultValue = null,
       invalidExamples = const [];

  /// The key as written in the file.
  final String name;

  /// The kind of value.
  final KeyType type;

  /// What the key does.
  final String description;

  /// A valid value, written as decoded JSON.
  final Object? example;

  /// The value used when the key is absent, if there is one to document.
  final Object? defaultValue;

  /// Whether the file is invalid without the key.
  final bool isRequired;

  /// Strings that break the pattern of [type] or a rule it cannot say.
  final List<String> invalidExamples;
}
