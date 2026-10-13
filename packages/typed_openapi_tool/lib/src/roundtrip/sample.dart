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

  /// The sample as JSON, as the round-trip program reads it.
  Map<String, Object?> toJson() => {
    'type': type,
    'example': isExample,
    'value': value,
  };
}
