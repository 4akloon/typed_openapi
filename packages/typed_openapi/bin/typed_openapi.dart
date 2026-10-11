import 'dart:io';

import 'package:typed_openapi/src/cli/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await TypedOpenApiCli().run(args);
}
