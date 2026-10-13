import 'dart:io';

import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

/// Runs the corpus tool; see `dart run bin/corpus.dart help`.
Future<void> main(List<String> args) async {
  exitCode = await CorpusCli().run(args);
}
