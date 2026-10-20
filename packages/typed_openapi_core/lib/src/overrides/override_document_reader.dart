import '../diagnostics/diagnostic_bag.dart';
import '../load/spec_document.dart';
import 'generation_field_reader.dart';
import 'operation_override_reader.dart';
import 'override_field_reader.dart';
import 'override_set.dart';
import 'schema_override_reader.dart';

/// One read of an overrides document: its `operations` and `schemas`
/// sections.
final class OverrideDocumentReader {
  /// Creates a reader of [document] that reports to [diagnostics].
  OverrideDocumentReader(DiagnosticBag diagnostics, SpecDocument document)
    : this._(document, OverrideFieldReader(diagnostics, document));

  OverrideDocumentReader._(this._document, OverrideFieldReader fields)
    : _fields = fields,
      _operations = OperationOverrideReader(
        fields,
        GenerationFieldReader(fields),
      ),
      _schemas = SchemaOverrideReader(fields, GenerationFieldReader(fields));

  static const _sections = {'operations', 'schemas'};

  final SpecDocument _document;
  final OverrideFieldReader _fields;
  final OperationOverrideReader _operations;
  final SchemaOverrideReader _schemas;

  /// The overrides of the document.
  OverrideSet read() {
    final root = _document.root;
    _fields.checkKeys(root, _sections, .root);
    return OverrideSet(
      _document,
      operations: [
        for (final (key, entry, at) in _fields.entries(
          root,
          'operations',
          .root,
        ))
          ?_operations.operation(key, entry, at),
      ],
      schemas: [
        for (final (key, entry, at) in _fields.entries(root, 'schemas', .root))
          _schemas.schema(key, entry, at),
      ],
    );
  }
}
