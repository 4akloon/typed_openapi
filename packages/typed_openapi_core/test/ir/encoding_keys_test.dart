import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/model/parameter.dart';

import '../helpers/ir_fixture.dart';

String _spec(String media, String encoding, {String schema = _object}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          $media:
            schema: $schema
            encoding: $encoding
      responses: {"204": {description: ok}}
components:
  schemas:
    Base: {type: object, properties: {base: {type: string}}}
    Free: {type: object}
''';

const _object = '''
{type: object, properties: {file: {type: string, format: binary}, tag: {type: string}}}''';

List<String> _keys(ClientIr ir) => [
  for (final e in ir.groups.single.operations.single.body!.encoding) e.property,
];

void main() {
  group('an encoding key that names no property', () {
    for (final media in [
      'multipart/form-data',
      'application/x-www-form-urlencoded',
    ]) {
      test('is reported and ignored in $media', () {
        final fixture = IrFixture(
          _spec(
            media,
            '{tag: {contentType: text/plain}, nope: {contentType: image/png}}',
          ),
        );
        final ir = fixture.build();
        expect(_keys(ir), ['tag']);
        final [warning] = fixture.reportedOf(.encodingKeyUnknown);
        expect(warning.severity, Severity.warning);
        expect(warning.message, contains('"nope"'));
        expect(
          warning.pointer?.value,
          '#/paths/~1a/post/requestBody/content/${media.replaceAll('/', '~1')}/encoding/nope',
        );
      });
    }

    test(
      'is not reported for a property of a ref, an allOf part or a oneOf',
      () {
        final fixture = IrFixture(
          _spec(
            'multipart/form-data',
            '{base: {contentType: text/plain}, extra: {contentType: text/csv}, '
                'one: {contentType: text/csv}}',
            schema:
                r'{allOf: [{$ref: "#/components/schemas/Base"}, '
                '{type: object, properties: {extra: {type: string}}}], '
                'oneOf: [{type: object, properties: {one: {type: string}}}]}',
          ),
        );
        fixture.build();
        expect(fixture.reportedOf(.encodingKeyUnknown), isEmpty);
      },
    );

    test('is reported when the body has no schema', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            encoding: {a: {contentType: text/plain}}
      responses: {"204": {description: ok}}
''',
      );
      expect(_keys(fixture.build()), isEmpty);
      expect(fixture.reportedOf(.encodingKeyUnknown), hasLength(1));
    });

    test('is not reported for a free-form object, and the entry is kept', () {
      final fixture = IrFixture(
        _spec(
          'application/x-www-form-urlencoded',
          '{meta: {style: deepObject, explode: true}}',
          schema: '{type: object}',
        ),
      );
      final ir = fixture.build();
      expect(_keys(ir), ['meta']);
      final [encoding] = ir.groups.single.operations.single.body!.encoding;
      expect(encoding.style, ParameterStyle.deepObject);
      expect(encoding.explode, isTrue);
      expect(fixture.reportedOf(.encodingKeyUnknown), isEmpty);
    });

    test('is not reported for a schema with no properties in its parts', () {
      final fixture = IrFixture(
        _spec(
          'application/x-www-form-urlencoded',
          '{meta: {contentType: text/plain}}',
          schema:
              r'{allOf: [{type: object}, {$ref: "#/components/schemas/Free"}]}',
        ),
      );
      expect(_keys(fixture.build()), ['meta']);
      expect(fixture.reportedOf(.encodingKeyUnknown), isEmpty);
    });

    test('is not reported when every key names a property', () {
      final fixture = IrFixture(
        _spec('multipart/form-data', '{file: {contentType: image/png}}'),
      );
      expect(_keys(fixture.build()), ['file']);
      expect(fixture.reportedOf(.encodingKeyUnknown), isEmpty);
    });
  });

  group('encoding headers', () {
    test('of a form property are reported as a form property', () {
      final fixture = IrFixture(
        _spec(
          'application/x-www-form-urlencoded',
          '{tag: {headers: {X-A: {schema: {type: string}}}}}',
        ),
      );
      fixture.build();
      final [info] = fixture.reportedOf(.encodingHeadersIgnored);
      expect(info.message, contains('form property "tag"'));
      expect(info.message, isNot(contains('part')));
    });

    test('of a multipart part are reported as a part', () {
      final fixture = IrFixture(
        _spec(
          'multipart/form-data',
          '{tag: {headers: {X-A: {schema: {type: string}}}}}',
        ),
      );
      fixture.build();
      final [info] = fixture.reportedOf(.encodingHeadersIgnored);
      expect(info.message, contains('part "tag"'));
    });

    test('are reported once even when a style is wrong too', () {
      final fixture = IrFixture(
        _spec(
          'application/x-www-form-urlencoded',
          '{tag: {style: matrix, headers: {X-A: {schema: {type: string}}}}}',
        ),
      );
      fixture.build();
      expect(fixture.reportedOf(.encodingHeadersIgnored), hasLength(1));
      expect(fixture.reportedOf(.parameterStyleInvalid), hasLength(1));
    });
  });
}
