import '../overrides/override_set.dart';
import 'dart_type.dart';

/// Builds the types that stand for a custom Dart type (R6.8).
final class CustomTypes {
  const CustomTypes._();

  /// The custom type [custom] that reads and writes [json], the type of the
  /// JSON value it replaces.
  static CustomType of(DartTypeOverride custom, DartType json) => CustomType(
    type: custom.type,
    import: custom.import,
    converter: custom.converter,
    json: json.withNullable(false),
    nullable: json.nullable,
  );
}
