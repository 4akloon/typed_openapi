import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_document.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';

/// A spec normalized with overrides.
final class OverrideRun {
  /// Normalizes [spec] (or the file at [path]) with [overrides].
  OverrideRun(String spec, String overrides, {String? path}) {
    final SpecDocument document = path == null
        ? SpecLoader(bag).parse(spec, 'api.yaml')!
        : SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final version = OpenApiVersionDetector(bag).detect(document)!;
    final set = OverrideLoader(bag).parse(overrides, 'o.yaml')!;
    result = Normalizer(bag).normalize(document, version, overrides: set);
  }

  /// The start of an OpenAPI 3.0 document.
  static const header30 = '''
openapi: 3.0.3
info: {title: t, version: '1'}
''';

  /// The start of an OpenAPI 3.1 document.
  static const header31 = '''
openapi: 3.1.0
info: {title: t, version: '1'}
''';

  /// What the run reported.
  final DiagnosticBag bag = DiagnosticBag();

  /// The normalized spec.
  late final NormalizedSpec result;

  /// The value at [pointer] of the root document after normalizing.
  Object? at(String pointer) =>
      result.documents.root.valueAt(JsonPointer.parse(pointer))?.$1;

  /// The diagnostics about the overrides file.
  List<(DiagnosticCode, String?)> get overrideDiagnostics => [
    for (final d in bag.sorted)
      if (d.file == 'o.yaml') (d.code, d.pointer?.value),
  ];

  /// The codes of every diagnostic.
  List<DiagnosticCode> get codes => [for (final d in bag.sorted) d.code];
}
