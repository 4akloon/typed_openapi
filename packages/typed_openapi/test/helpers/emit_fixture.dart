import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi/src/emit/model_library.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// The model files of the fixture spec [name] in `typed_openapi_test_support/lib/fixtures`.
Map<String, String> emitFixture(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
}) {
  final fixture = NormalizedFixture(
    Fixtures.read(name),
    generation: generation,
  );
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.spec, fixture.client);
  return const ModelLibrary().files(ir);
}

/// The files of the whole client of the fixture spec [name] in
/// `typed_openapi_test_support/lib/fixtures`: models, API and the root, for the client `api`;
/// [overrides] names an overrides file there.
Map<String, String> emitClient(
  String name, {
  GenerationConfig generation = const GenerationConfig(),
  String? overrides,
}) {
  final fixture = NormalizedFixture(
    Fixtures.read(name),
    generation: generation,
    overrides: overrides == null ? null : Fixtures.read(overrides),
  );
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.spec, fixture.client);
  return const ApiLibrary().files(ir, client: fixture.client.name);
}
