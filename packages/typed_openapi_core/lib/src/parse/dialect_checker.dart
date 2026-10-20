import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reports constructs that the version a document declares does not have.
///
/// The dialect of a document is decided by its content: the parser reads
/// every construct, and this check says where the content and the declared
/// `openapi` version disagree. Each construct is reported once, at its first
/// use, with the number of uses.
final class DialectChecker {
  /// Creates a checker that reports to [_diagnostics].
  const DialectChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reports the [uses] that [version] does not define.
  void check(List<FeatureUse> uses, OpenApiVersion version) {
    final byFeature = <SpecFeature, List<FeatureUse>>{};
    for (final use in uses) {
      byFeature.putIfAbsent(use.feature, () => []).add(use);
    }
    for (final MapEntry(key: feature, value: found) in byFeature.entries) {
      final first = found.first;
      final count = found.length == 1
          ? ''
          : ' It is used in ${found.length} places; this is the first.';
      final declared = 'the document declares ${version.label}';
      final since = feature.since;
      final until = feature.until;
      if (since != null && version.index < since.index) {
        final is31 = since == .v31;
        _diagnostics.report(
          is31 ? .openApi31InOpenApi30 : .openApi32InOlder,
          is31
              ? '${feature.label} is OpenAPI 3.1 (JSON Schema 2020-12), but '
                    '$declared; it is read as 3.1.$count'
              : '${feature.label} is OpenAPI 3.2, but $declared; it is read '
                    'anyway.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix:
              'Declare "openapi: ${since.label}.0" if the backend emits '
              '${since.label}; otherwise remove the construct.',
        );
      } else if (until != null && version.index >= until.index) {
        _diagnostics.report(
          .nullableAfterOpenApi30,
          '${feature.label} exists only in OpenAPI 3.0, but $declared; it '
          'is read as in 3.0.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix: 'Write type: [<type>, "null"] instead of nullable: true.',
        );
      }
    }
  }
}
