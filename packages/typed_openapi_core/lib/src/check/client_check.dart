import '../baseline/anchor_index.dart';
import '../baseline/fingerprints.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/severity.dart';
import '../ir/ir.dart';
import '../ir/ir_json.dart';

/// What checking one client found.
final class ClientCheck {
  /// Creates the result for [client].
  const ClientCheck(
    this.client,
    this.diagnostics,
    this.anchors, {
    this.ir,
    this.irJson,
    this.sources = const [],
    this.errors = 0,
  });

  /// The client.
  final ClientConfig client;

  /// The diagnostics of the client's spec with the client's levels; codes
  /// the client turns off are gone.
  final List<Diagnostic> diagnostics;

  /// The logical addresses of the client's spec, for baseline anchors.
  final AnchorIndex anchors;

  /// The semantic IR of the client; null when its spec could not be read.
  final ClientIr? ir;

  /// Writes [ir] as JSON, naming files as the diagnostics do.
  final IrJson? irJson;

  /// The files the run read, by absolute path: the documents of the spec,
  /// then the overrides file; what the generated code is made from besides
  /// the config.
  final List<String> sources;

  /// The errors the client reports after its levels and its baseline;
  /// `generate` skips a client that has any (M8).
  final int errors;

  /// The errors that say the spec, or a file it is read with, could not be
  /// read (diagnostics of [DiagnosticCode.fixedCodes]). Without them the
  /// run found too little: no entry of a baseline may be called stale, and
  /// no baseline may be rewritten from it.
  List<Diagnostic> get readErrors => [
    for (final d in diagnostics)
      if (d.severity == Severity.error &&
          DiagnosticCode.fixedCodes.contains(d.code))
        d,
  ];

  /// This result with [errors] reported errors.
  ClientCheck withErrors(int errors) => ClientCheck(
    client,
    diagnostics,
    anchors,
    ir: ir,
    irJson: irJson,
    sources: sources,
    errors: errors,
  );

  /// The fingerprints of [diagnostics] for the client's baseline file at
  /// [baselineFile]; [paths] reads the file names of the diagnostics.
  Fingerprints fingerprints(String baselineFile, DisplayPaths paths) =>
      Fingerprints(anchors, baselineFile, paths);
}
