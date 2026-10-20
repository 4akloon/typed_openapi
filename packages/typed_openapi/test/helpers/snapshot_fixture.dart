import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/snapshot/api_snapshot.dart';
import 'package:typed_openapi/src/snapshot/snapshot_builder.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

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

/// The API snapshot of the fixture spec [name] in `typed_openapi_test_support/lib/fixtures`.
ApiSnapshot snapshotOfFixture(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
}) => snapshotOf(
  Fixtures.read(name),
  generation: generation,
);
