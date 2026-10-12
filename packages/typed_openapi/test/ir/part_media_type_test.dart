import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

String _spec(String properties, String encoding, {String required = '[]'}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              required: $required
              properties: $properties
            encoding: $encoding
      responses: {"204": {description: ok}}
''';

const _pointer =
    '#/paths/~1a/post/requestBody/content/multipart~1form-data/encoding';

/// The parts of the one operation as `name: type, media type`.
List<String> _parts(IrFixture fixture, ClientIr ir) => [
  for (final p in ir.groups.single.operations.single.body!.parts!)
    '${p.name}: ${p.type.code(ir.nameOf)}, ${p.contentType}',
];

void main() {
  group('the media type of a multipart part', () {
    test('a list on a file takes the first type (the OAS profile image)', () {
      final fixture = IrFixture(
        _spec(
          '{avatar: {type: string, format: binary}}',
          '{avatar: {contentType: "image/png, image/jpeg"}}',
        ),
      );
      final ir = fixture.build();
      expect(_parts(fixture, ir), ['avatar: Uint8List?, image/png']);
      final [info] = fixture.reportedOf(.partMediaTypeChosen);
      expect(info.severity, Severity.info);
      expect(info.pointer?.value, '$_pointer/avatar/contentType');
      expect(info.message, contains('"image/png, image/jpeg"'));
      expect(info.message, contains('"image/png"'));
    });

    test('a wildcard on a file is the file\'s own type or bytes', () {
      final fixture = IrFixture(
        _spec(
          '{photo: {type: string, format: binary}, '
              'all: {type: array, items: {type: string, format: binary}}}',
          '{photo: {contentType: "image/*"}, all: {contentType: "*/*"}}',
        ),
      );
      final ir = fixture.build();
      expect(_parts(fixture, ir), [
        'photo: Uint8List?, application/octet-stream',
        'all: List<Uint8List>?, application/octet-stream',
      ]);
      expect(fixture.reportedOf(.partMediaTypeChosen), hasLength(2));
    });

    test('a wildcard first in a list is skipped on a file', () {
      final fixture = IrFixture(
        _spec(
          '{photo: {type: string, format: binary}}',
          '{photo: {contentType: "image/*, image/webp"}}',
        ),
      );
      expect(_parts(fixture, fixture.build()), [
        'photo: Uint8List?, image/webp',
      ]);
    });

    test('a text part takes the first concrete type, or none', () {
      final fixture = IrFixture(
        _spec(
          '{rows: {type: string}, note: {type: string}}',
          '{rows: {contentType: "text/csv, text/plain"}, '
              'note: {contentType: "text/*"}}',
        ),
      );
      expect(_parts(fixture, fixture.build()), [
        'rows: String?, text/csv',
        'note: String?, null',
      ]);
      expect(fixture.reportedOf(.partMediaTypeChosen), hasLength(2));
    });

    test('an object part takes the first JSON type of a list', () {
      final fixture = IrFixture(
        _spec(
          '{meta: {type: object, properties: {a: {type: string}}}}',
          '{meta: {contentType: "application/xml, application/json"}}',
        ),
      );
      expect(_parts(fixture, fixture.build()), [
        'meta: UploadRequestMeta?, application/json',
      ]);
      expect(fixture.reportedOf(.partMediaTypeChosen), hasLength(1));
      expect(fixture.reportedOf(.partMediaTypeNotJson), isEmpty);
    });

    test('an object part with a wildcard of JSON is JSON', () {
      final fixture = IrFixture(
        _spec(
          '{meta: {type: object, properties: {a: {type: string}}}}',
          '{meta: {contentType: "application/*"}}',
        ),
      );
      expect(_parts(fixture, fixture.build()), [
        'meta: UploadRequestMeta?, application/json',
      ]);
    });

    test('an XML object part is text the caller supplies (the OAS history)', () {
      final fixture = IrFixture(
        _spec(
          '{history: {type: object, properties: {a: {type: string}}}, '
              'items: {type: array, items: {type: object, properties: {b: {type: string}}}}}',
          '{history: {contentType: "application/xml; charset=utf-8"}, '
              'items: {contentType: application/xml}}',
          required: '[history]',
        ),
      );
      final ir = fixture.build();
      expect(_parts(fixture, ir), [
        'history: String, application/xml; charset=utf-8',
        'items: List<String>?, application/xml',
      ]);
      // No model is made for a schema that is sent as text.
      expect(ir.declarations, isEmpty);
      final warnings = fixture.reportedOf(.partMediaTypeNotJson);
      expect(
        [for (final w in warnings) w.severity],
        [
          Severity.warning,
          Severity.warning,
        ],
      );
      expect(
        [for (final w in warnings) w.pointer?.value],
        [
          '$_pointer/history/contentType',
          '$_pointer/items/contentType',
        ],
      );
      expect(fixture.reportedOf(.partMediaTypeChosen), isEmpty);
    });

    test('a single concrete type is kept without a report', () {
      final fixture = IrFixture(
        _spec(
          '{avatar: {type: string, format: binary}, '
              'meta: {type: object, properties: {a: {type: string}}}, '
              'note: {type: string}}',
          '{avatar: {contentType: image/png}, '
              'meta: {contentType: "application/vnd.x+json; v=1"}, '
              'note: {contentType: text/plain}}',
        ),
      );
      final ir = fixture.build();
      expect(_parts(fixture, ir), [
        'avatar: Uint8List?, image/png',
        'meta: UploadRequestMeta?, application/vnd.x+json; v=1',
        'note: String?, text/plain',
      ]);
      expect(fixture.reported, isEmpty);
    });

    test('a value that is no media type is chosen around like a wildcard', () {
      final fixture = IrFixture(
        _spec(
          '{avatar: {type: string, format: binary}}',
          '{avatar: {contentType: "png"}}',
        ),
      );
      expect(_parts(fixture, fixture.build()), [
        'avatar: Uint8List?, application/octet-stream',
      ]);
      expect(fixture.reportedOf(.partMediaTypeChosen), hasLength(1));
    });
  });
}
