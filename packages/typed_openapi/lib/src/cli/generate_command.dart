import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:io/io.dart' show ExitCode;

import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';
import '../emit/model_library.dart';
import '../generate/output_writer.dart';
import '../generate/real_paths.dart';
import 'check_command.dart';

/// `typed_openapi generate`: checks every client as `check` does and
/// writes the models of each client without errors into its output
/// directory (M8; operations come with M9).
///
/// A client whose check reports an error, including an overrides file that
/// cannot be used, is skipped; so is one whose output directory the
/// generator may not own (TOA830), which includes a directory that holds a
/// file the config makes any client read. The report and a line per client go to
/// stdout, and the exit code is the one `check` gives.
final class GenerateCommand extends Command<int> {
  /// Creates the command; reports go to [_out], and files are named as
  /// [_paths] does.
  GenerateCommand(this._out, [this._paths = const DisplayPaths()]) {
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
  String get name => 'generate';

  @override
  String get description =>
      'Check specs and generate the models of clients without errors.';

  @override
  String get invocation =>
      '${runner!.executableName} generate [options] [client...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final diagnostics = DiagnosticBag();
    final configPath = results.option('config')!;
    final config = ConfigLoader(diagnostics, _paths).load(configPath);
    final lines = <String>[];
    if (config != null) {
      final only = results.rest.toSet();
      final unknown = only.difference(config.declaredClients);
      if (unknown.isNotEmpty) {
        usageException(
          'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
        );
      }
      final checks = SpecChecker(diagnostics, _paths).check(config, only: only);
      final writer = OutputWriter(diagnostics, _paths);
      final overlapping = _overlapping(config.clients);
      // Every file any client of the config reads, also one that is not run:
      // an output directory must not hold one, or the run would delete it.
      final protected = {
        _paths.absolute(configPath),
        for (final client in config.clients) ...[
          client.input,
          ?client.overrides,
          ?client.baseline,
        ],
        for (final check in checks) ...check.sources,
      }.toList()..sort();
      for (final check in checks) {
        final client = check.client;
        final ir = check.ir;
        if (ir == null || check.errors > 0) {
          lines.add(
            'Skipped ${client.name}: its check reports errors; fix them and '
            'run generate again.',
          );
          continue;
        }
        if (overlapping.contains(client.name)) {
          lines.add(
            'Skipped ${client.name}: its output overlaps the output of '
            'another client (TOA904).',
          );
          continue;
        }
        final files = ModelLibrary(width: client.lineWidth).files(ir);
        final changes = writer.write(
          client,
          files,
          inputs: inputsOf(check),
          protected: protected,
        );
        lines.add(
          changes == null
              ? 'Skipped ${client.name}: see the error above.'
              : 'Generated ${client.name} in ${_paths.of(client.output)}: '
                    '${files.length} files, ${changes.written} written, '
                    '${changes.deleted} deleted.',
        );
      }
    }
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    if (config == null) return ExitCode.config.code;
    return diagnostics.hasErrors
        ? CheckCommand.exitHasErrors
        : ExitCode.success.code;
  }

  /// The names of the clients whose output directory is, or is inside, that
  /// of another client, also through symbolic links or a different case.
  static Set<String> _overlapping(List<ClientConfig> clients) => {
    for (var i = 0; i < clients.length; i++)
      for (var j = i + 1; j < clients.length; j++)
        if (RealPaths.overlap(clients[i].output, clients[j].output)) ...[
          clients[i].name,
          clients[j].name,
        ],
  };

  /// The hash of what the code of [check]'s client is generated from: the
  /// content of every file the run read, the client's settings that change
  /// the code, and the generator. The same inputs give the same hash on
  /// any machine: paths are not part of it.
  static String inputsOf(ClientCheck check) {
    final client = check.client;
    String hashOf(String path) {
      try {
        return sha256.convert(File(path).readAsBytesSync()).toString();
      } on FileSystemException {
        return 'unreadable';
      }
    }

    return sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'generator': OutputWriter.generator,
              'files': [for (final path in check.sources) hashOf(path)],
              'generation': client.generation.key,
              'line_width': client.lineWidth,
              'preset': client.preset?.name,
              'rules': client.disabledRules.toList()..sort(),
            }),
          ),
        )
        .toString();
  }
}
