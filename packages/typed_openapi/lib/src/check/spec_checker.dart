import 'package:path/path.dart' as p;

import '../baseline/anchor_index.dart';
import '../baseline/baseline.dart';
import '../baseline/baseline_loader.dart';
import '../baseline/fingerprints.dart';
import '../config/generation_config.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/severity.dart';
import '../ir/ir.dart';
import '../ir/ir_builder.dart';
import '../ir/ir_json.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_loader.dart';

/// What checking one client found.
final class ClientCheck {
  /// Creates the result for [client].
  const ClientCheck(
    this.client,
    this.diagnostics,
    this.anchors, {
    this.ir,
    this.irJson,
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

  /// The fingerprints of [diagnostics] for the client's baseline file at
  /// [baselineFile]; [paths] reads the file names of the diagnostics.
  Fingerprints fingerprints(String baselineFile, DisplayPaths paths) =>
      Fingerprints(anchors, baselineFile, paths);
}

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics]; [_paths] names files
  /// in diagnostics.
  const SpecChecker(this._diagnostics, [this._paths = const DisplayPaths()]);

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// Checks the spec of every client in [config] and reports what each
  /// client's baseline does not accept; returns what each client found, as
  /// [checkClients] does.
  ///
  /// See [checkClients] for how specs are checked. A client with a
  /// `baseline` reports only the diagnostics its baseline does not accept;
  /// the accepted ones go to [DiagnosticBag.addBaselined]. An entry that
  /// accepts more than the check finds is `baseline-entry-stale`: a warning,
  /// or an error with [strictBaseline]. A baseline file that cannot be read
  /// is reported, and every diagnostic of the client is shown. Stale entries
  /// are not reported for a client whose spec could not be read: the read
  /// error says what is wrong. [strictBaseline] applies after the client's
  /// levels, so it makes a stale entry an error even if the config lowered or
  /// turned off `baseline-entry-stale`.
  List<ClientCheck> check(
    ProjectConfig config, {
    Set<String> only = const {},
    bool strictBaseline = false,
  }) {
    final checks = checkClients(config, only: only);
    for (final result in checks) {
      final client = result.client;
      final path = client.baseline;
      if (path == null) {
        result.diagnostics.forEach(_diagnostics.add);
        continue;
      }
      final problems = DiagnosticBag();
      final baseline = BaselineLoader(
        problems,
      ).load(path, displayPath: _paths.of(path));
      if (baseline == null) {
        result.diagnostics.forEach(_diagnostics.add);
      } else {
        final match = baseline.match(
          result.diagnostics,
          result.fingerprints(path, _paths),
        );
        match.shown.forEach(_diagnostics.add);
        match.baselined.forEach(_diagnostics.addBaselined);
        for (final (entry, found)
            in result.readErrors.isEmpty
                ? match.stale
                : const <(BaselineEntry, int)>[]) {
          final what =
              '${entry.code ?? 'A diagnostic'} at '
              '${entry.anchor ?? entry.fingerprint}';
          problems.report(
            .baselineEntryStale,
            found == 0
                ? 'No diagnostic matches this entry ($what); the problem '
                      'is gone.'
                : 'This entry accepts ${entry.count} diagnostics ($what), '
                      'but the check finds $found.',
            file: baseline.file,
            pointer: entry.pointer,
            span: baseline.spanOf(entry.pointer),
            fix: 'Run `typed_openapi baseline prune` to update the baseline.',
          );
        }
      }
      for (final problem in problems.all) {
        final reported = strictBaseline && problem.code == .baselineEntryStale
            ? problem.withSeverity(.error)
            : client.severity.apply(problem);
        if (reported != null) _diagnostics.add(reported);
      }
    }
    return checks;
  }

  /// Checks the spec of every client in [config]; returns what each client
  /// found, in client order. Only problems of the config itself go to the
  /// bag; the rest are in the results.
  ///
  /// Each spec is loaded, its OpenAPI version detected, and then it is read
  /// into the model with its `$ref`s resolved, changed by the client's
  /// overrides and normalized with the client's rules and preset. An
  /// overrides file that cannot be used is reported and the spec is checked
  /// without it. Then the client's IR is built (M6), which reports naming,
  /// mapping and filter problems. [only] limits the run to clients with these
  /// names; empty means all. A file shared by several clients is checked once
  /// per distinct preset, set of disabled rules, overrides file and
  /// [GenerationConfig.key]; each client then gives the diagnostics of that
  /// run its own levels ([ClientConfig.severity]), because levels change how
  /// a finding is reported, not what a run finds. Diagnostics name files
  /// relative to the working directory (see [DisplayPaths]).
  List<ClientCheck> checkClients(
    ProjectConfig config, {
    Set<String> only = const {},
  }) {
    // A run is a file with a preset, a set of disabled rules, overrides and
    // generation settings.
    final runs = <(String, Preset?, String, String?, String), ClientCheck>{};
    return [
      for (final client in config.clients)
        if (only.isEmpty || only.contains(client.name))
          _withLevels(
            client,
            runs[(
              p.absolute(client.input),
              client.preset,
              (client.disabledRules.toList()..sort()).join(','),
              client.overrides,
              client.generation.key,
            )] ??= _run(
              client,
            ),
          ),
    ];
  }

  ClientCheck _withLevels(ClientConfig client, ClientCheck run) => ClientCheck(
    client,
    [
      for (final diagnostic in run.diagnostics)
        ?client.severity.apply(diagnostic),
    ],
    run.anchors,
    ir: run.ir,
    irJson: run.irJson,
  );

  /// Checks the spec of [client] and builds its IR; returns what the run
  /// found, with default levels.
  ClientCheck _run(ClientConfig client) {
    final found = DiagnosticBag();
    ClientCheck result([AnchorIndex? anchors]) =>
        ClientCheck(client, found.all, anchors ?? AnchorIndex.none());
    final document = SpecLoader(
      found,
    ).load(client.input, displayPath: _paths.of(client.input));
    if (document == null) return result();
    final version = OpenApiVersionDetector(found).detect(document);
    if (version == null) return result();
    final overridesPath = client.overrides;
    final overrides = overridesPath == null
        ? null
        : OverrideLoader(
            found,
          ).load(overridesPath, displayPath: _paths.of(overridesPath));
    final normalized = Normalizer(
      found,
      disabled: client.disabledRules,
      preset: client.preset,
    ).normalize(document, version, overrides: overrides);
    final ir = IrBuilder(found).build(normalized, client);
    return ClientCheck(
      client,
      found.all,
      AnchorIndex(normalized.model, normalized.documents),
      ir: ir,
      irJson: IrJson(normalized.documents.displayPath),
    );
  }
}
