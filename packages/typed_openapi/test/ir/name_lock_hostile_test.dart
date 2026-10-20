import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/name_lock.dart';

import '../helpers/ir_fixture.dart';

const _spec = r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /animals:
    get:
      operationId: listAll
      responses:
        '200': {description: ok}
  /pets:
    get:
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet'}
            text/event-stream:
              schema: {type: string}
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''';

/// A stream-only operation `chat` and another operation named `chatStream`.
const _only = '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /chat:
    get:
      operationId: chat
      responses:
        '200':
          description: ok
          content:
            text/event-stream:
              schema: {type: string}
  /other:
    get:
      operationId: chatStream
      responses:
        '200': {description: ok}
''';

const _inline = '#/components/schemas/Pet/properties/status';

String _typeAt(ClientIr ir, String pointer) => ir.declarations
    .firstWhere((d) => d.id.location.pointer.value == pointer)
    .name;

Iterable<String> _methods(ClientIr ir) =>
    ir.groups.expand((g) => g.operations).map((o) => o.name);

NameLock _locking(
  IrFixture fixture, {
  Map<String, String> types = const {},
  Map<String, String> methods = const {},
}) => NameLock(
  root: fixture.context.spec.model.document.location.document,
  types: types,
  methods: methods,
);

void main() {
  const hostile = [
    'class', // a reserved word
    'String', // a name the library has
    'Object',
    'a b', // not an identifier
    'X(); injected()',
    'pet', // a method name for a type
  ];

  for (final name in hostile) {
    test('a type name "$name" read from the lock is not used', () {
      final fixture = IrFixture(_spec);
      final ir = fixture.build(
        names: _locking(fixture, types: {_inline: name}),
      );
      expect(_typeAt(ir, _inline), 'PetStatus');
      final taken = fixture.reportedOf(DiagnosticCode.lockedNameTaken);
      expect(taken, hasLength(1));
      expect(taken.single.pointer?.value, _inline);
    });
  }

  for (final name in [
    'class',
    'toString',
    'jsonEncode',
    'a b',
    'injected(); x',
    'Pet', // a type name for a method
  ]) {
    test('a method name "$name" read from the lock is not used', () {
      final fixture = IrFixture(_spec);
      final ir = fixture.build(
        names: _locking(fixture, methods: {'GET /animals': name}),
      );
      expect(_methods(ir), contains('listAll'));
      expect(_methods(ir), isNot(contains(name)));
      expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), hasLength(1));
    });
  }

  test('a name of the lock is quoted in the message', () {
    final fixture = IrFixture(_spec);
    fixture.build(names: _locking(fixture, types: {_inline: 'a"\nb'}));
    expect(
      fixture.reportedOf(DiagnosticCode.lockedNameTaken).single.message,
      contains(r'"a\"\nb"'),
    );
  });

  test('a method name the lock keeps is TOA570', () {
    final fixture = IrFixture(_spec);
    final ir = fixture.build(
      names: _locking(fixture, methods: {'GET /animals': 'everything'}),
    );
    expect(_methods(ir), contains('everything'));
    expect(
      fixture.reportedOf(DiagnosticCode.lockedNameKept).single.message,
      contains('"everything" of the method of listAll'),
    );
  });

  test('an override that takes a kept method name is TOA569', () {
    final fixture = IrFixture(
      _spec,
      overrides: 'operations:\n  GET /pets:\n    name: everything\n',
    );
    final ir = fixture.build(
      names: _locking(fixture, methods: {'GET /animals': 'everything'}),
    );
    expect(_methods(ir), contains('everything'));
    expect(_methods(ir), contains('listAll'));
    expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), hasLength(1));
  });

  test('the lock keeps the name of the event-stream method', () {
    final fixture = IrFixture(_spec);
    final ir = fixture.build(
      names: _locking(
        fixture,
        methods: {'GET /pets': 'fetch', 'GET /pets#stream': 'watch'},
      ),
    );
    expect(_methods(ir), containsAll(['fetch', 'watch']));
  });

  test('the lock of a client with two methods per operation names both', () {
    final fixture = IrFixture(_spec);
    final lock = fixture.lockOf(fixture.build());
    expect(lock.methods.keys, containsAll(['GET /pets', 'GET /pets#stream']));
    expect(lock.methods['GET /pets#stream'], 'getPetsStream');
  });

  test('an event-stream name of an operation without one is free', () {
    final fixture = IrFixture(_spec);
    final ir = fixture.build(
      names: _locking(fixture, methods: {'GET /animals#stream': 'getPets'}),
    );
    expect(_methods(ir), contains('getPets'));
  });

  test('a stale event-stream name of a stream-only operation is free', () {
    final fixture = IrFixture(_only);
    final ir = fixture.build(
      names: _locking(fixture, methods: {'GET /chat#stream': 'chatStream'}),
    );
    expect(_methods(ir), containsAll(['chat', 'chatStream']));
    expect(_methods(ir), isNot(contains('chatStream2')));
  });

  for (final name in ['class', 'a b', 'X(); injected()', 'Pet']) {
    test('a hostile event-stream name "$name" is not used', () {
      final fixture = IrFixture(_spec);
      final ir = fixture.build(
        names: _locking(fixture, methods: {'GET /pets#stream': name}),
      );
      expect(_methods(ir), isNot(contains(name)));
      expect(_methods(ir), contains('getPetsStream'));
      expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), hasLength(1));
    });
  }

  test('an explicit name frees the name the identity had', () {
    final fixture = IrFixture(
      _spec,
      overrides: 'schemas:\n  Pet:\n    name: Animal\n',
    );
    final ir = fixture.build(
      names: _locking(
        fixture,
        types: {'#/components/schemas/Pet': 'Pet', _inline: 'Pet2'},
      ),
    );
    expect(_typeAt(ir, '#/components/schemas/Pet'), 'Animal');
    expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), isEmpty);
  });
}
