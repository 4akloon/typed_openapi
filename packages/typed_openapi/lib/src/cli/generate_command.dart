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
import '../emit/api_library.dart';
import '../generate/output_writer.dart';
import '../generate/real_paths.dart';
import '../ir/ir.dart';
import 'check_command.dart';

/// `typed_openapi generate`: checks every client as `check` does and
/// writes the whole client of each client without errors into its output
/// directory: the models, the API classes and the root client (M8, M9).
///
/// A client whose check reports an error, including an overrides file that
/// cannot be used, is skipped; so is one whose output directory the
/// generator may not replace (TOA830): a directory that holds a package, a
/// file the config makes any client read, or a file the generator did not
/// write or that changed since it did (`--force` replaces those and lists
/// each, never the others; `--break-lock` only takes over a lock). The report
/// and a line per client go to stdout, and the exit code is the one `check`
/// gives.
final class GenerateCommand extends Command<int> {
  /// Creates the command; reports go to [_out], and files are named as
  /// [_paths] does.
  GenerateCommand(this._out, [this._paths = const DisplayPaths()]) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'typed_openapi.yaml',
        help: 'Path to the config file.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Replace files in an output directory that typed_openapi did not '
            'write or that changed since it wrote them; each is listed.',
      )
      ..addFlag(
        'break-lock',
        negatable: false,
        help:
            'Take over the lock of an output when it cannot be told whether '
            'the run that holds it is still going. Replaces no file.',
      );
  }

  final StringSink _out;
  final DisplayPaths _paths;

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Check specs and generate the clients without errors.';

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
        final files = _files(client, ir);
        final changes = writer.write(
          client,
          files,
          inputs: inputsOf(check),
          protected: protected,
          force: results.flag('force'),
          breakLock: results.flag('break-lock'),
        );
        lines.add(
          changes == null
              ? 'Skipped ${client.name}: see the error above.'
              : 'Generated ${client.name} in ${_paths.of(client.output)}: '
                    '${files.length} files, ${changes.written} written, '
                    '${changes.deleted} deleted.'
                    '${changes.forced == 0 ? '' : ' --force replaced '
                              '${changes.forced} foreign or modified '
                              '${changes.forced == 1 ? 'file' : 'files'}.'}',
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

  /// The files of the whole client [client] with the IR [ir].
  static Map<String, String> _files(ClientConfig client, ClientIr ir) =>
      ApiLibrary(width: client.lineWidth).files(ir, client: client.name);

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
