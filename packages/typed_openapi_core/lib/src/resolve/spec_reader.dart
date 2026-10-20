import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../parse/dialect_checker.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_resolver.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Reads a loaded spec into a [SpecModel]: parses it, follows its `$ref`s
/// and reports constructs its declared version does not have.
///
/// Problems go to the [DiagnosticBag] given to the constructor.
final class SpecReader {
  /// Creates a reader that reports to [_diagnostics].
  const SpecReader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads [document], which declares [version].
  ///
  /// Other files come from [documents], whose root is [document]; by
  /// default they are loaded on demand, reporting to this reader's bag.
  SpecModel read(
    SpecDocument document,
    OpenApiVersion version, {
    SpecDocuments? documents,
  }) {
    final index = SpecIndex();
    final parsed = OpenApiParser(_diagnostics, document, index).parse(version);
    final model = RefResolver(_diagnostics).resolve(
      parsed,
      index,
      documents ?? SpecDocuments(SpecLoader(_diagnostics), document),
    );
    DialectChecker(_diagnostics).check(index.features, version);
    return model;
  }
}
