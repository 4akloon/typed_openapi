import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/load/spec_document.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';
import 'package:typed_openapi_core/src/parse/parse_context.dart';

/// A spec parsed from text, with a parse context and the diagnostics so far.
final class SpecFixture {
  /// Parses [text] as the file [file]; the text must load without errors.
  SpecFixture(String text, {String file = 'api.yaml'})
    : this._(DiagnosticBag(), text, file);

  SpecFixture._(this.diagnostics, String text, String file)
    : document = SpecLoader(diagnostics).parse(text, file)!;

  /// Where every diagnostic goes.
  final DiagnosticBag diagnostics;

  /// The loaded document.
  final SpecDocument document;

  /// What the parsers record.
  final SpecIndex index = SpecIndex();

  /// A context for parsing [document].
  late final ParseContext context = ParseContext(
    diagnostics,
    document,
    index,
  );

  /// The codes reported so far, in report order.
  List<DiagnosticCode> get codes => [
    for (final d in diagnostics.all) d.code,
  ];

  /// The pointers reported so far, in report order.
  List<String?> get pointers => [
    for (final d in diagnostics.all) d.pointer?.value,
  ];
}
