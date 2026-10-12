import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose only operation has [security] (YAML, or none) under a
/// document with [global] security and the schemes `bearer` and `key`.
IrFixture specOf({String? security, String? global}) => IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
${global == null ? '' : 'security: $global'}
paths:
  /a:
    get:
      operationId: read
      tags: [t]
${security == null ? '' : '      security: $security'}
      responses: {"200": {description: ok}}
components:
  securitySchemes:
    bearer: {type: http, scheme: bearer}
    key: {type: apiKey, name: X-Key, in: header}
    typeless: {description: no type}
''');

/// The requirements of the operation as `name:kind:scopes` per alternative.
List<List<String>> requirements(IrFixture fixture) {
  final ir = IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);
  return [
    for (final alternative in ir.groups.single.operations.single.security)
      [
        for (final use in alternative)
          '${use.scheme.name}:${use.scheme.kind.name}:${use.scopes.join(',')}',
      ],
  ];
}

List<Diagnostic> unknown(IrFixture fixture) => [
  for (final d in fixture.reported)
    if (d.code == DiagnosticCode.securitySchemeUnknown) d,
];

void main() {
  group('a security scheme that is not defined', () {
    test('never makes an operation optional or open', () {
      final fixture = specOf(security: '[{nope: [read]}]');
      expect(requirements(fixture), [
        ['nope:unknown:read'],
      ]);
      expect(
        unknown(fixture).single.pointer?.value,
        '#/paths/~1a/get/security/0',
      );
    });

    test('drops the alternatives that name it when another one is usable', () {
      final fixture = specOf(security: '[{nope: []}, {bearer: []}]');
      expect(requirements(fixture), [
        ['bearer:http:'],
      ]);
      expect(
        unknown(fixture).single.pointer?.value,
        '#/paths/~1a/get/security/0',
      );
    });

    test('drops an alternative as a whole, with its known schemes', () {
      final fixture = specOf(security: '[{nope: [], bearer: []}, {key: []}]');
      expect(requirements(fixture), [
        ['key:apiKey:'],
      ]);
      expect(unknown(fixture), hasLength(1));
    });

    test('keeps the known schemes next to it when nothing else is usable', () {
      final fixture = specOf(security: '[{nope: [], bearer: [a]}]');
      expect(requirements(fixture), [
        ['nope:unknown:', 'bearer:http:a'],
      ]);
    });

    test('keeps every alternative when none is usable', () {
      final fixture = specOf(security: '[{nope: []}, {other: [x]}]');
      expect(requirements(fixture), [
        ['nope:unknown:'],
        ['other:unknown:x'],
      ]);
      expect(unknown(fixture), hasLength(2));
    });

    test('leaves an optional alternative optional', () {
      final fixture = specOf(security: '[{nope: []}, {}]');
      expect(requirements(fixture), [<String>[]]);
      expect(unknown(fixture), hasLength(1));
    });

    test('is the same for a scheme that has no type', () {
      final fixture = specOf(security: '[{typeless: []}]');
      expect(requirements(fixture), [
        ['typeless:unknown:'],
      ]);
    });

    test('is the same when the document gives the requirement', () {
      final fixture = specOf(global: '[{nope: []}]');
      expect(requirements(fixture), [
        ['nope:unknown:'],
      ]);
      expect(unknown(fixture).single.pointer?.value, '#/security/0');
    });
  });

  group('security that the spec defines', () {
    test('an optional alternative stays optional, without a report', () {
      final fixture = specOf(security: '[{}]');
      expect(requirements(fixture), [<String>[]]);
      expect(fixture.reported, isEmpty);
    });

    test('an operation can turn off the security of the document', () {
      final fixture = specOf(security: '[]', global: '[{bearer: []}]');
      expect(requirements(fixture), isEmpty);
      expect(fixture.reported, isEmpty);
    });

    test('an operation inherits the security of the document', () {
      final fixture = specOf(global: '[{bearer: []}]');
      expect(requirements(fixture), [
        ['bearer:http:'],
      ]);
      expect(fixture.reported, isEmpty);
    });
  });
}
