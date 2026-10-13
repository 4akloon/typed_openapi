import 'dart:io';

import 'package:typed_openapi_tool/src/fuzz/fuzz_cli.dart';

/// Runs the escaping fuzz; see `dart run bin/fuzz.dart --help`.
Future<void> main(List<String> args) async {
  exitCode = await FuzzCli().run(args);
}
