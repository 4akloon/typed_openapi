import 'package:typed_openapi_core/src/check/spec_checker.dart';
import 'package:typed_openapi_core/src/config/config_loader.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/display_paths.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// One `check` of a spec with the clients of a config, for the tests of the
/// findings outside the generated API.
final class OutsideApiRun {
  /// Writes [spec] as `api.yaml` and the [files], and checks the [clients]
  /// (the body of `clients:`).
  factory OutsideApiRun(
    String spec,
    String clients, {
    Map<String, String> files = const {},
  }) {
    final dir = TempDir();
    dir.write('api.yaml', spec);
    for (final MapEntry(:key, :value) in files.entries) {
      dir.write(key, value);
    }
    final path = dir.write('typed_openapi.yaml', 'clients:\n$clients');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    final checks = SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    return OutsideApiRun._(checks, bag);
  }

  OutsideApiRun._(this.checks, this.bag);

  /// What each client found.
  final List<ClientCheck> checks;

  /// Everything reported.
  final DiagnosticBag bag;

  /// The reported diagnostics with [code].
  List<Diagnostic> of(DiagnosticCode code) => [
    for (final d in bag.all)
      if (d.code == code) d,
  ];
}
