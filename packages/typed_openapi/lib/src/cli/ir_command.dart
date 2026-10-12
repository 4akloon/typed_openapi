import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';

/// `typed_openapi ir`: prints the semantic IR of clients as JSON, to see
/// the names and types the generator will emit and to write overrides
/// before code generation exists.
///
/// The command is hidden: its output is for inspection and may change in
/// any release.
final class IrCommand extends Command<int> {
  /// Creates the command; the IR is written to [_out] and files are named
  /// as [_paths] does.
  IrCommand(this._out, [this._paths = const DisplayPaths()]) {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'typed_openapi.yaml',
      help: 'Path to the config file.',
    );
  }

  final StringSink _out;
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
      _out.writeln(const TextReporter().format(diagnostics));
      return ExitCode.config.code;
    }
    final only = results.rest.toSet();
    final unknown = only.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final checks = SpecChecker(
      diagnostics,
      _paths,
    ).checkClients(config, only: only);
    final json = {
      for (final ClientCheck(:client, :ir, :irJson) in checks)
        client.name: ir == null || irJson == null ? null : irJson.toJson(ir),
    };
    _out.writeln(const JsonEncoder.withIndent('  ').convert(json));
    return json.values.contains(null) ? 1 : ExitCode.success.code;
  }
}
