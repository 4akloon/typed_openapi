import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';

import '../helpers/outside_api_run.dart';

const _bad = r"{$ref: '#/components/schemas/'}";

String _op(String path, String schema) =>
    '''
  $path:
    get:
      operationId: op${path.replaceAll('/', '_')}
      responses:
        '200':
          description: ok
          content: {application/json: {schema: $schema}}
''';

String _ref(String name) => '{\$ref: \'#/components/schemas/$name\'}';

String _spec(String paths, String schemas) =>
    '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
$paths
components:
  schemas:
$schemas
''';

const _gen = '''
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/gen]}
''';

const _pet =
    '    Pet: {type: object, required: [kind], properties: {kind: {type: string}}, discriminator: {propertyName: kind}}\n';

void _expectBlocks(OutsideApiRun run) {
  expect(run.checks.single.errors, 1);
  expect(
    run.of(DiagnosticCode.invalidRef).single.severity,
    Severity.error,
  );
}

void main() {
  group('a subtype of a generated union keeps its level', () {
    final paths = _op('/gen', _ref('Pet')) + _op('/ex', _ref('Leaf'));
    String leaf(String parent) =>
        '    Leaf: {allOf: [${_ref(parent)}, {type: object, properties: {bad: $_bad}}]}\n';

    test('two levels down', () {
      final run = OutsideApiRun(
        _spec(
          paths,
          '$_pet    Dog: {allOf: [${_ref('Pet')}]}\n${leaf('Dog')}',
        ),
        _gen,
      );
      _expectBlocks(run);
    });

    test('through an alias of the base', () {
      final run = OutsideApiRun(
        _spec(paths, '$_pet    Alias: ${_ref('Pet')}\n${leaf('Alias')}'),
        _gen,
      );
      _expectBlocks(run);
    });

    test('through an alias and a level', () {
      final run = OutsideApiRun(
        _spec(
          paths,
          '$_pet    Alias: ${_ref('Pet')}\n'
          '    Dog: {allOf: [${_ref('Alias')}]}\n'
          '    Alias2: ${_ref('Dog')}\n${leaf('Alias2')}',
        ),
        _gen,
      );
      _expectBlocks(run);
    });

    test('a cycle of allOf ends, and lowers what no union holds', () {
      final run = OutsideApiRun(
        _spec(
          _op('/gen', '{type: string}') + _op('/ex', _ref('A')),
          '    A: {allOf: [${_ref('B')}, {type: object, properties: {bad: $_bad}}]}\n'
          '    B: {allOf: [${_ref('A')}]}\n',
        ),
        _gen,
      );
      expect(run.checks.single.errors, 0);
    });
  });

  test('the default error schema keeps its level', () {
    final run = OutsideApiRun(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /gen:
    get:
      operationId: gen
      responses:
        '404': {description: nf}
        '200':
          description: ok
          content: {application/json: {schema: {type: string}}}
${_op('/ex', _ref('C'))}
components:
  schemas:
    C: {type: object, properties: {bad: $_bad}}
''',
      '$_gen    errors: {default_schema: C}\n',
    );
    _expectBlocks(run);
  });

  group('a ref from outside the region into a left out operation', () {
    const spec = r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /gen:
    get:
      operationId: gen
      responses:
        '200': {$ref: '#/paths/~1ex/get/responses/200'}
  /ex:
    get:
      operationId: ex
      responses:
        '200':
          description: ok
          content: {application/json: {schema: {type: object, properties: {bad: {$ref: '#/components/schemas/'}}}}}
        '400':
          description: bad
          content: {application/json: {schema: {type: object, properties: {worse: {$ref: '#/components/schemas/'}}}}}
''';

    test('keeps the referenced node and lowers the rest', () {
      final run = OutsideApiRun(spec, _gen);
      final byPointer = {
        for (final d in run.of(DiagnosticCode.invalidRef))
          d.pointer!.value: d.severity,
      };
      expect(
        byPointer.entries.singleWhere((e) => e.key.contains('/200/')).value,
        Severity.error,
      );
      expect(
        byPointer.entries.singleWhere((e) => e.key.contains('/400/')).value,
        Severity.info,
      );
    });
  });

  test('a bare mapping name is read in the root document', () {
    final run = OutsideApiRun(
      _spec(
        _op('/gen', r"{$ref: 'other.yaml#/Base'}") + _op('/ex', _ref('Cat')),
        '    Cat: {type: object, properties: {bad: $_bad}}\n',
      ),
      _gen,
      files: {
        'other.yaml':
            'Base: {type: object, properties: {kind: {type: string}}, '
            'discriminator: {propertyName: kind, mapping: {c: Cat}}}\n',
      },
    );
    _expectBlocks(run);
  });

  test('a severity in the config sets the level after the lowering', () {
    final run = OutsideApiRun(
      _spec(_op('/gen', '{type: string}') + _op('/ex', _bad), ''),
      '$_gen    severity: {TOA100: error}\n',
    );
    _expectBlocks(run);
  });

  group('a left out operation that refers into a generated one', () {
    const badSchema =
        r"{type: object, properties: {bad: {$ref: '#/components/schemas/'}}}";
    String paths(String generated, String excluded) =>
        '  /gen:\n$generated  /ex:\n$excluded';

    void expectKept(String spec) => _expectBlocks(OutsideApiRun(spec, _gen));

    test('to its response', () {
      expectKept(
        _spec(
          paths(
            '    get:\n      operationId: gen\n      responses:\n'
                "        '200':\n          description: ok\n"
                '          content: {application/json: {schema: $badSchema}}\n',
            '    get:\n      operationId: ex\n      responses:\n'
                r"        '200': {$ref: '#/paths/~1gen/get/responses/200'}"
                '\n',
          ),
          '',
        ),
      );
    });

    test('to a parameter of its path item', () {
      expectKept(
        _spec(
          paths(
            '    parameters: [{name: q, in: query, schema: $badSchema}]\n'
                '    get:\n      operationId: gen\n'
                "      responses: {'204': {description: ok}}\n",
            '    get:\n      operationId: ex\n'
                r"      parameters: [{$ref: '#/paths/~1gen/parameters/0'}]"
                "\n      responses: {'204': {description: ok}}\n",
          ),
          '',
        ),
      );
    });

    test('to its path item, from a callback', () {
      expectKept(
        _spec(
          paths(
            '    post:\n      operationId: gen\n'
                '      requestBody: {content: {application/json: '
                '{schema: $badSchema}}}\n'
                "      responses: {'204': {description: ok}}\n",
            '    post:\n      operationId: ex\n      callbacks:\n'
                '        cb:\n'
                r"          '{$request.body#/u}': {$ref: '#/paths/~1gen'}"
                "\n      responses: {'204': {description: ok}}\n",
          ),
          '',
        ),
      );
    });

    test('to the whole document', () {
      expectKept(
        _spec(
          paths(
            '    post:\n      operationId: gen\n'
                '      requestBody: {content: {application/json: '
                '{schema: $badSchema}}}\n'
                "      responses: {'204': {description: ok}}\n",
            '    get:\n      operationId: ex\n      responses:\n'
                "        '200': {description: ok, content: "
                r"{application/json: {schema: {$ref: '#'}}}}"
                '\n',
          ),
          '',
        ),
      );
    });
  });
}
