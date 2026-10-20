import 'dart:io';

import 'package:typed_openapi_tool/src/docs/docs_cli.dart';

/// Writes or checks the docs generated from the code; see `lib/src/docs`.
Future<void> main(List<String> args) async {
  exitCode = await DocsCli().run(args);
}
