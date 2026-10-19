import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/snapshot/api_snapshot.dart';
import 'package:typed_openapi/src/snapshot/snapshot_builder.dart';

import 'ir_fixture.dart';

/// The API snapshot of the spec [text] for a client configured by
/// [generation] and [overrides] (the text of an overrides file).
ApiSnapshot snapshotOf(
  String text, {
  GenerationConfig generation = const GenerationConfig(),
  String? overrides,
}) {
  final fixture = IrFixture(text, generation: generation, overrides: overrides);
  final root = fixture.context.model.document.location.document;
  return SnapshotBuilder(root).build(fixture.build());
}

/// The API snapshot of the fixture spec [name] in `test/emit/fixtures`.
ApiSnapshot snapshotOfFixture(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
}) => snapshotOf(
  File(p.join('test', 'emit', 'fixtures', name)).readAsStringSync(),
  generation: generation,
);
