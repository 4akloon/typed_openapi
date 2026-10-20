import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'check_command.dart';

/// `typed_openapi ir`: prints the semantic IR of clients as JSON, to see
/// the names and types the generator will emit and to write overrides
/// before code generation exists.
///
/// The JSON is alone on stdout. The errors and warnings of the run, as
/// `check` finds them, go to stderr as text, with the count of the infos
/// (`check` lists them), and the exit code is the one `check` gives.
/// The command is hidden: its output is for inspection and may change in any
/// release.
final class IrCommand extends Command<int> {
  /// Creates the command; the IR is written to [_out], diagnostics to
  /// [_err], and files are named as [_paths] does.
  IrCommand(this._out, this._err, [this._paths = const DisplayPaths()]) {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'typed_openapi.yaml',
      help: 'Path to the config file.',
    );
  }

  final StringSink _out;
  final StringSink _err;
  final DisplayPaths _paths;

  @override
  String get name => 'ir';

  @override
  bool get hidden => true;

  @override
  String get description =>
      'Print the semantic IR of clients as JSON (for debugging).';

  @override
  String get invocation => '${runner!.executableName} ir [options] [client...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final diagnostics = DiagnosticBag();
    final config = ConfigLoader(
      diagnostics,
      _paths,
    ).load(results.option('config')!);
    if (config == null) {
      _err.writeln(const TextReporter().format(diagnostics));
      return ExitCode.config.code;
    }
    final only = results.rest.toSet();
    final unknown = only.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final checks = SpecChecker(diagnostics, _paths).check(config, only: only);
    final json = {
      for (final ClientCheck(:client, :ir, :irJson) in checks)
        client.name: ir == null || irJson == null ? null : irJson.toJson(ir),
    };
    _out.writeln(const JsonEncoder.withIndent('  ').convert(json));
    _printDiagnostics(diagnostics);
    for (final MapEntry(:key, :value) in json.entries) {
      if (value == null) {
        _err.writeln(
          'Client $key has no IR: its spec could not be read (see the '
          'errors above).',
        );
      }
    }
    return json.values.contains(null) || diagnostics.hasErrors
        ? CheckCommand.exitHasErrors
        : ExitCode.success.code;
  }

  /// Writes the errors and warnings of [diagnostics] to stderr, then the
  /// summary of all of them and how many infos are not listed.
  void _printDiagnostics(DiagnosticBag diagnostics) {
    if (diagnostics.all.isEmpty) return;
    final shown = DiagnosticBag();
    var infos = 0;
    for (final diagnostic in diagnostics.all) {
      if (diagnostic.severity == .info) {
        infos++;
      } else {
        shown.add(diagnostic);
      }
    }
    const reporter = TextReporter();
    final listing = reporter.format(shown);
    final summary = TextReporter.summary(shown);
    _err.write(listing.substring(0, listing.length - summary.length));
    _err.writeln(TextReporter.summary(diagnostics));
    if (infos > 0) {
      _err.writeln(
        '$infos info diagnostic${infos == 1 ? '' : 's'} not shown; run '
        '`check` to see ${infos == 1 ? 'it' : 'them'}.',
      );
    }
  }
}
