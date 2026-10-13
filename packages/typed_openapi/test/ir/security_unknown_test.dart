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

    test('says a scheme is defined but unusable when it has no type', () {
      final typeless = specOf(security: '[{typeless: []}]');
      requirements(typeless);
      expect(unknown(typeless).single.message, contains('no usable type'));
      expect(
        unknown(typeless).single.message,
        isNot(contains('does not define')),
      );
      final missing = specOf(security: '[{nope: []}]');
      requirements(missing);
      expect(unknown(missing).single.message, contains('does not define'));
    });

    test('is the same when the document gives the requirement', () {
      final fixture = specOf(global: '[{nope: []}]');
      expect(requirements(fixture), [
        ['nope:unknown:'],
      ]);
      expect(unknown(fixture).single.pointer?.value, '#/security/0');
    });
  });

  group('a security requirement that is not an object', () {
    for (final (entry, name) in [
      ('"bearer"', 'bearer'),
      ('null', ''),
      ('7', ''),
    ]) {
      test('$entry is an unknown scheme, never an open operation', () {
        final fixture = specOf(security: '[$entry]');
        expect(requirements(fixture), [
          ['$name:unknown:'],
        ]);
        expect(
          unknown(fixture).single.pointer?.value,
          '#/paths/~1a/get/security/0',
        );
        expect(unknown(fixture).single.message, contains('not an object'));
        expect(
          fixture.diagnostics.all.map((d) => d.code),
          contains(DiagnosticCode.invalidValue),
        );
      });
    }

    test('is dropped when another alternative can be described', () {
      final fixture = specOf(security: '["bearer", {key: []}]');
      expect(requirements(fixture), [
        ['key:apiKey:'],
      ]);
      expect(unknown(fixture), hasLength(1));
    });

    test('keeps every alternative when none can be described', () {
      final fixture = specOf(security: '[null, {nope: []}]');
      expect(requirements(fixture), [
        [':unknown:'],
        ['nope:unknown:'],
      ]);
      expect(unknown(fixture), hasLength(2));
    });

    test('in the document is inherited as an unknown scheme', () {
      final fixture = specOf(global: '["bearer"]');
      expect(requirements(fixture), [
        ['bearer:unknown:'],
      ]);
      expect(unknown(fixture).single.pointer?.value, '#/security/0');
    });
  });

  group('a security field that is not a list', () {
    for (final (value, name) in [
      ('{bearer: []}', ''),
      ('"bearer"', 'bearer'),
      ('7', ''),
    ]) {
      for (final (level, pointer) in [
        ('operation', '#/paths/~1a/get/security'),
        ('document', '#/security'),
      ]) {
        test('$value at the $level is an unknown scheme, not an open call', () {
          final fixture = level == 'operation'
              ? specOf(security: value)
              : specOf(global: value);
          expect(requirements(fixture), [
            ['$name:unknown:'],
          ]);
          final report = unknown(fixture).single;
          expect(report.pointer?.value, pointer);
          expect(report.message, contains('not a list'));
          expect(
            [
              for (final d in fixture.diagnostics.all)
                if (d.code == DiagnosticCode.invalidValue) d.pointer?.value,
            ],
            [pointer],
          );
        });
      }
    }

    test('in an operation replaces the security of the document', () {
      final fixture = specOf(security: '7', global: '[{bearer: []}]');
      expect(requirements(fixture), [
        [':unknown:'],
      ]);
      expect(unknown(fixture), hasLength(1));
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
