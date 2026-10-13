/// One JSON value the round trip decodes as the generated class [type]:
/// an example of the spec, or a synthetic value built from the IR.
final class Sample {
  /// Creates the sample of [value] for [type].
  const Sample(this.type, this.value, {required this.isExample});

  /// The name of the generated class (a declaration of the IR).
  final String type;

  /// The JSON value.
  final Object? value;

  /// Whether the value is an example of the spec; a spec example that does
  /// not decode is a defect of the spec, a synthetic value one of the tool
  /// or the generator.
  final bool isExample;

  /// Whether [value] is JSON that `jsonEncode` writes: `null`, booleans,
  /// strings, finite numbers, lists, and maps with string keys. A spec can
  /// carry more (`.nan`, `.inf`, a timestamp), which is a defect of the
  /// spec, not a reason to stop the run.
  bool get isEncodable => _isEncodable(value);

  static bool _isEncodable(Object? value) => switch (value) {
    null || bool() || String() || int() => true,
    double() => value.isFinite,
    List<Object?>() => value.every(_isEncodable),
    Map<Object?, Object?>() =>
      value.keys.every((key) => key is String) &&
          value.values.every(_isEncodable),
    _ => false,
  };

  /// The sample as JSON, as the round-trip program reads it.
  Map<String, Object?> toJson() => {
    'type': type,
    'example': isExample,
    'value': value,
  };
}
