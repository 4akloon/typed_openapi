import 'package:typed_openapi_core/typed_openapi_core.dart';

/// A hundred of codes that the diagnostics reference groups under one
/// heading.
enum DiagnosticArea {
  /// `TOA0xx`.
  load(
    0,
    'Load',
    'Reading the spec files: JSON/YAML syntax, versions and limits.',
  ),

  /// `TOA1xx`.
  parse(
    1,
    'Parse and resolve',
    r'Reading the OpenAPI objects and following `$ref`s.',
  ),

  /// `TOA2xx`.
  normalize(
    2,
    'Normalizer and schema mapping',
    'Schema problems that the normalizer repairs or the mapper has to work '
        'around.',
  ),

  /// `TOA3xx`.
  enums(3, 'Enums', 'Enum values and their names.'),

  /// `TOA4xx`.
  unions(
    4,
    'Discriminators and unions',
    'How `oneOf`/`anyOf` and discriminators become Dart types.',
  ),

  /// `TOA5xx`.
  naming(
    5,
    'Paths, naming and operations',
    'Operation ids, parameters, groups and Dart names.',
  ),

  /// `TOA6xx`.
  media(
    6,
    'Media types, errors and event streams',
    'Bodies, responses, defaults and Server-Sent Events.',
  ),

  /// `TOA8xx`.
  fixes(
    8,
    'Fixes, overrides, baseline and generate',
    'Applying fixes and overrides, baselines, and writing the output.',
  ),

  /// `TOA9xx`.
  config(9, 'Config', 'Reading `typed_openapi.yaml`.');

  const DiagnosticArea(this.hundred, this.title, this.summary);

  /// The hundreds digit of the ids in the area.
  final int hundred;

  /// The name of the area.
  final String title;

  /// One sentence on what the area covers.
  final String summary;

  /// The heading of the area, such as `Load (TOA0xx)`.
  String get heading => '$title (TOA${hundred}xx)';

  /// The area that holds [code].
  static DiagnosticArea of(DiagnosticCode code) {
    final hundred = int.parse(code.id[3]);
    return values.singleWhere((area) => area.hundred == hundred);
  }
}
