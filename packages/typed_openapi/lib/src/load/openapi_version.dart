import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import 'spec_document.dart';

/// The OpenAPI line a document declares in its `openapi` field.
enum OpenApiVersion {
  /// OpenAPI 3.0.x.
  v30,

  /// OpenAPI 3.1.x.
  v31,

  /// OpenAPI 3.2.x.
  v32,
}

/// Reads the OpenAPI version of a [SpecDocument].
///
/// Problems go to the [DiagnosticBag] given to the constructor.
final class OpenApiVersionDetector {
  /// Creates a detector that reports to [_diagnostics].
  const OpenApiVersionDetector(this._diagnostics);

  static final _version = RegExp(r'^3\.(\d+)(?:\.\d+)?$');

  final DiagnosticBag _diagnostics;

  /// Reads the `openapi` field of [document].
  ///
  /// Reports a diagnostic and returns null when the field is missing or the
  /// document is not OpenAPI 3. A minor version above 3.2 is read as 3.2,
  /// with a warning.
  OpenApiVersion? detect(SpecDocument document) {
    final declared = document.root['openapi'];
    if (declared == null) {
      _reportMissing(document);
      return null;
    }
    final pointer = JsonPointer.root.child('openapi');
    final match = _version.firstMatch('$declared');
    if (match == null) {
      _diagnostics.report(
        .unsupportedOpenApiVersion,
        'OpenAPI "$declared" is not supported; only 3.0, 3.1 and 3.2 are.',
        file: document.file,
        pointer: pointer,
        span: document.spanOf(pointer),
      );
      return null;
    }
    switch (int.parse(match.group(1)!)) {
      case 0:
        return .v30;
      case 1:
        return .v31;
      case 2:
        return .v32;
      case final minor:
        _diagnostics.report(
          .unknownOpenApiMinorVersion,
          'OpenAPI 3.$minor is newer than this tool knows; reading it as 3.2.',
          file: document.file,
          pointer: pointer,
          span: document.spanOf(pointer),
        );
        return .v32;
    }
  }

  void _reportMissing(SpecDocument document) {
    final swagger = document.root['swagger'];
    if (swagger == null) {
      _diagnostics.report(
        .missingOpenApiVersion,
        'The document has no "openapi" field.',
        file: document.file,
        pointer: .root,
        fix: 'Add the version the backend emits, for example "openapi: 3.0.3".',
      );
      return;
    }
    final pointer = JsonPointer.root.child('swagger');
    _diagnostics.report(
      .unsupportedOpenApiVersion,
      'Swagger $swagger is not supported; only OpenAPI 3.0, 3.1 and 3.2 are.',
      file: document.file,
      pointer: pointer,
      span: document.spanOf(pointer),
      fix: 'Have the backend emit OpenAPI 3, or convert the document.',
    );
  }
}
