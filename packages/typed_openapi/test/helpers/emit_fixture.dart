import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/emit/model_library.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import 'ir_fixture.dart';

/// The model files of the fixture spec [name] in `test/emit/fixtures`.
Map<String, String> emitFixture(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
}) {
  final fixture = IrFixture(
    File(p.join('test', 'emit', 'fixtures', name)).readAsStringSync(),
    generation: generation,
  );
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return const ModelLibrary().files(ir);
}
