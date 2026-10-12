import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

String _spec(String tags, {String servers = ''}) {
  final paths = [
    for (final (i, tag) in tags.split(',').indexed)
      '''
  /p$i:
    get:
      operationId: op$i
      tags: [$tag]
      responses: {"200": {description: ok}}''',
  ].join('\n');
  return '''
openapi: 3.1.0
info: {title: t, version: "1"}
$servers
paths:
$paths
''';
}

void main() {
  group('a group field or a server that gets another name', () {
    test('is reported: a group named server and a server', () {
      final fixture = IrFixture(
        _spec('server', servers: 'servers: [{url: "https://a.example"}]'),
      );
      final ir = fixture.build();
      expect([for (final g in ir.groups) g.field], ['server']);
      expect(ir.root.servers.single.name, 'server2');
      final [change] = fixture.reportedOf(.nameCollision);
      expect(change.message, contains('"server"'));
      expect(change.message, contains('"server2"'));
      expect(change.pointer?.value, '#/servers/0');
    });

    test('is reported: tags that give the same field', () {
      final fixture = IrFixture(_spec('HTTPServer,HttpServer'));
      final ir = fixture.build();
      expect(
        [for (final g in ir.groups) g.field],
        ['httpServer', 'httpServer2'],
      );
      final [change] = fixture.reportedOf(.nameCollision);
      expect(change.pointer?.value, startsWith('#/paths/'));
    });

    test('is reported: a group field named like a reserved word', () {
      final fixture = IrFixture(_spec('class'));
      expect(fixture.build().groups.single.field, 'class_');
      expect(fixture.reportedOf(.nameReserved), hasLength(1));
    });

    test('is not reported when nothing changes', () {
      final fixture = IrFixture(
        _spec('pets', servers: 'servers: [{url: "https://a.example"}]'),
      );
      fixture.build();
      expect(fixture.reportedOf(.nameCollision), isEmpty);
      expect(fixture.reportedOf(.nameReserved), isEmpty);
    });
  });

  group('the root client class', () {
    test('of a name with no ASCII letters is ApiClient with TOA559', () {
      final fixture = IrFixture(_spec('t'), clientName: 'мій-клієнт');
      expect(fixture.build().root.name, 'ApiClient');
      final [lost] = fixture.reportedOf(.nameLossy);
      expect(lost.message, contains('"мій-клієнт"'));
      expect(lost.fix, contains('naming.client'));
    });

    test('of a name that loses letters has TOA559', () {
      final fixture = IrFixture(_spec('t'), clientName: 'ünï-shop');
      expect(fixture.build().root.name, 'NShopClient');
      expect(fixture.reportedOf(.nameLossy), hasLength(1));
    });

    test('of a name with no letter or digit has TOA552', () {
      final fixture = IrFixture(_spec('t'), clientName: '---');
      expect(fixture.build().root.name, 'ApiClient');
      expect(fixture.reportedOf(.nameUnrepresentable), hasLength(1));
    });

    test('of a name that starts with a digit has a prefix, not a dollar', () {
      final fixture = IrFixture(_spec('t'), clientName: '1password');
      expect(fixture.build().root.name, 'Api1PasswordClient');
      expect(fixture.reportedOf(.nameLossy), isEmpty);
    });

    test('of an ordinary name has no report', () {
      final fixture = IrFixture(_spec('t'), clientName: 'pet-store');
      expect(fixture.build().root.name, 'PetStoreClient');
      expect(
        fixture.reported.where(
          (d) => d.code != DiagnosticCode.operationMultipleTags,
        ),
        isEmpty,
      );
    });
  });
}
