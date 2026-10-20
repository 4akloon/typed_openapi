import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';
import 'array_without_items.dart';

/// `format` on an array without `items` (C-50): the format belongs to the
/// elements.
final class FormatOnArray extends NormalizerRule {
  /// Creates the rule.
  const FormatOnArray();

  @override
  String get name => 'format-on-array';

  @override
  List<DiagnosticCode> get codes => const [.formatOnArray];

  /// The element type each known format implies: the number formats of the
  /// OpenAPI format registry and the string formats of OpenAPI and JSON
  /// Schema. Another format gives no override, because its type is unknown.
  static final _elementTypes = {
    'int32': 'integer',
    'int64': 'integer',
    'float': 'number',
    'double': 'number',
    for (final format in [
      'binary',
      'byte',
      'date',
      'date-time',
      'duration',
      'email',
      'hostname',
      'idn-email',
      'idn-hostname',
      'ipv4',
      'ipv6',
      'iri',
      'iri-reference',
      'json-pointer',
      'password',
      'regex',
      'relative-json-pointer',
      'time',
      'uri',
      'uri-reference',
      'uri-template',
      'uuid',
    ])
      format: 'string',
  };

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final format = schema.format;
      if (format == null ||
          !schema.types.contains(SchemaType.array) ||
          schema.items != null ||
          ArrayWithoutItems.hasItemsKey(context, schema)) {
        continue;
      }
      final type = _elementTypes[format];
      const move = 'Move it into the elements at the source; until then, ';
      yield context.finding(
        .formatOnArray,
        '"format: $format" is on the array, which has no "items", not on its '
        'elements.',
        schema.location.child('format'),
        fix: type == null
            ? '${move}override "items" of this schema with the element schema '
                  'and remove its "format".'
            : context.withOverride(
                '${move}override "items" of this schema with {type: $type, '
                'format: $format} and remove its "format".',
                schema.location,
                {
                  'format': null,
                  'items': {'type': type, 'format': format},
                },
              ),
        backendFix:
            'Move "format" into the elements of the array at the source and '
            'remove it from the array.',
      );
    }
  }
}
