import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      parameters: [{name: limit, in: query, schema: {type: integer}}]
      responses: {"204": {description: ok}}
  /store/orders:
    get:
      operationId: listOrders
      tags: [store]
      parameters: [{name: limit, in: query, schema: {type: integer}}]
      responses: {"204": {description: ok}}
''';

const _storeOverride = '''
operations:
  GET /store/orders:
    name: orders
    parameters:
      limit: {spec: {description: How many.}}
''';

const _sharedSpec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses: {"204": {description: ok}}
  /store/orders:
    parameters: [{name: limit, in: query, schema: {type: integer}}]
    get:
      operationId: listOrders
      tags: [store]
      responses: {"204": {description: ok}}
''';

FilterPattern _pattern(String value, String pointer) =>
    FilterPattern(value, JsonPointer.parse(pointer));

IrFixture _fixture({
  GenerationConfig generation = const GenerationConfig(),
  String overrides = _storeOverride,
}) {
  final fixture = IrFixture(
    _spec,
    generation: generation,
    overrides: overrides,
  );
  IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return fixture;
}

GenerationConfig _including(String tag) => GenerationConfig(
  include: OperationFilter(tags: [_pattern(tag, '#/clients/a/include/tags/0')]),
);

void main() {
  test('an entry of an operation that include leaves out is reported once, '
      'at the entry', () {
    final fixture = _fixture(generation: _including('pets'));
    final dead = fixture.reported
        .where((d) => d.code == DiagnosticCode.overrideOperationNotGenerated)
        .toList();
    expect(dead, hasLength(1));
    expect(dead.single.file, 'o.yaml');
    expect(dead.single.pointer?.value, '#/operations/GET ~1store~1orders');
    expect(dead.single.span, isNotNull);
    expect(dead.single.message, contains('GET /store/orders'));
    expect(dead.single.message, contains('include'));
    expect(dead.single.message, contains('exclude'));
  });

  test('an entry of an operation that exclude leaves out is reported', () {
    final fixture = _fixture(
      generation: GenerationConfig(
        exclude: OperationFilter(
          tags: [_pattern('store', '#/clients/a/exclude/tags/0')],
        ),
      ),
    );
    expect(
      fixture.reported.map((d) => d.code),
      contains(DiagnosticCode.overrideOperationNotGenerated),
    );
  });

  test('an entry of a generated operation is not reported', () {
    final fixture = _fixture(generation: _including('store'));
    expect(
      fixture.reported.map((d) => d.code),
      isNot(contains(DiagnosticCode.overrideOperationNotGenerated)),
    );
  });

  test('an entry with its own exclude is not reported', () {
    final fixture = _fixture(
      generation: _including('pets'),
      overrides: 'operations:\n  GET /store/orders: {exclude: true}\n',
    );
    expect(fixture.reported, isEmpty);
  });

  List<Diagnostic> dead(IrFixture fixture) => fixture.reported
      .where((d) => d.code == DiagnosticCode.overrideOperationNotGenerated)
      .toList();

  test('removing the entry removes the diagnostic', () {
    const kept = 'operations:\n  listPets: {name: pets}\n';
    final withEntry = _fixture(
      generation: _including('pets'),
      overrides: '$kept  listOrders: {name: orders}\n',
    );
    final without = _fixture(generation: _including('pets'), overrides: kept);
    expect(dead(withEntry), hasLength(1));
    expect(dead(without), isEmpty);
  });

  test('an entry addressed by operationId is reported', () {
    final fixture = _fixture(
      generation: _including('pets'),
      overrides: 'operations:\n  listOrders: {name: orders}\n',
    );
    final found = dead(fixture);
    expect(found, hasLength(1));
    expect(found.single.pointer?.value, '#/operations/listOrders');
    expect(found.single.message, contains('listOrders'));
  });

  test('a shared path-level parameter override gives one report on the '
      'entry', () {
    final fixture = IrFixture(
      _sharedSpec,
      generation: _including('pets'),
      overrides:
          'operations:\n  GET /store/orders:\n    parameters:\n'
          '      limit: {spec: {description: How many.}}\n',
    );
    IrBuilder(
      fixture.diagnostics,
    ).build(fixture.context.spec, fixture.context.client);
    final found = dead(fixture);
    expect(found, hasLength(1));
    expect(found.single.pointer?.value, '#/operations/GET ~1store~1orders');
  });

  test('an entry that resolves to no operation is only TOA804', () {
    final fixture = _fixture(
      generation: _including('pets'),
      overrides: 'operations:\n  GET /missing: {name: gone}\n',
    );
    // The normalizer reports the missing target, before the IR is built.
    final codes = fixture.diagnostics.all.map((d) => d.code);
    expect(codes, contains(DiagnosticCode.overrideTargetNotFound));
    expect(
      codes,
      isNot(contains(DiagnosticCode.overrideOperationNotGenerated)),
    );
  });
}
