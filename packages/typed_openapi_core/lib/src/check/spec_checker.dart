import 'package:path/path.dart' as p;

import '../baseline/anchor_index.dart';
import '../baseline/baseline.dart';
import '../baseline/baseline_loader.dart';
import '../config/generation_config.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../ir/ir_builder.dart';
import '../ir/ir_json.dart';
import '../ir/name_lock.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_loader.dart';
import '../snapshot/api_lock_names.dart';
import 'client_check.dart';
import 'outside_generated_api.dart';

export 'client_check.dart';

/// What one run of [SpecChecker] checks: a spec file with a preset, the
/// disabled rules, an overrides file, generation settings, the root
/// client's name and the names of the API lock.
typedef _RunKey = (String, Preset?, String, String?, String, String?, NameLock);

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics]; [_paths] names files
  /// in diagnostics.
  const SpecChecker(this._diagnostics, [this._paths = const DisplayPaths()])
    : _hasFreshNames = false;

  /// Creates a checker as [SpecChecker.new] does that names types and
  /// methods from scratch, without the names `typed_openapi.lock` keeps
  /// (`generate --fresh-names`).
  const SpecChecker.freshNames(
    this._diagnostics, [
    this._paths = const DisplayPaths(),
  ]) : _hasFreshNames = true;

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final bool _hasFreshNames;

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
    final results = <ClientCheck>[];
    for (final result in checks) {
      final client = result.client;
      final path = client.baseline;
      var errors = 0;
      void add(Diagnostic diagnostic) {
        if (diagnostic.severity == .error) errors++;
        _diagnostics.add(diagnostic);
      }

      if (path == null) {
        result.diagnostics.forEach(add);
        results.add(result.withErrors(errors));
        continue;
      }
      final problems = DiagnosticBag();
      final baseline = BaselineLoader(
        problems,
      ).load(path, displayPath: _paths.of(path));
      if (baseline == null) {
        result.diagnostics.forEach(add);
      } else {
        final match = baseline.match(
          result.diagnostics,
          result.fingerprints(path, _paths),
        );
        match.shown.forEach(add);
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
        if (reported != null) add(reported);
      }
      results.add(result.withErrors(errors));
    }
    return results;
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
  /// relative to the working directory (see [DisplayPaths]). Types and
  /// methods keep the names `typed_openapi.lock` next to the config has
  /// for the client (M12), so they are part of the run too.
  List<ClientCheck> checkClients(
    ProjectConfig config, {
    Set<String> only = const {},
  }) {
    final locked = _hasFreshNames
        ? const <String, NameLock>{}
        : ApiLockNames(_diagnostics, _paths).of(config);
    // A run is a file with a preset, a set of disabled rules, overrides and
    // generation settings.
    // The root client is named after the client unless naming.client
    // names it, so the name is part of the run.
    final runs = <_RunKey, ClientCheck>{};
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
              client.generation.clientClass == null ? client.name : null,
              _namesOf(locked, client),
            )] ??= _run(
              client,
              _namesOf(locked, client),
            ),
          ),
    ];
  }

  NameLock _namesOf(Map<String, NameLock> locked, ClientConfig client) =>
      locked[client.name] ?? NameLock.none;

  ClientCheck _withLevels(ClientConfig client, ClientCheck run) => ClientCheck(
    client,
    [
      for (final diagnostic in run.diagnostics)
        ?client.severity.apply(diagnostic),
    ],
    run.anchors,
    ir: run.ir,
    irJson: run.irJson,
    sources: run.sources,
  );

  /// Checks the spec of [client] and builds its IR; returns what the run
  /// found, with default levels.
  ClientCheck _run(ClientConfig client, NameLock names) {
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
    final ir = IrBuilder(found, names: names).build(normalized, client);
    return ClientCheck(
      client,
      OutsideGeneratedApi(normalized, client, names).apply(found.all),
      AnchorIndex(normalized.model, normalized.documents),
      ir: ir,
      irJson: IrJson(normalized.documents.displayPath),
      sources: [
        for (final document in normalized.documents.loaded)
          if (document.uri.scheme == 'file') p.fromUri(document.uri),
        ?overridesPath,
      ],
    );
  }
}
