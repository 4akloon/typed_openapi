import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// A spec with [paths] (YAML under `paths:`) in OpenAPI 3.1.
String _spec(String paths, {String components = ''}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
$paths
${components.isEmpty ? '' : 'components:\n$components'}''';

/// The methods of the only group of [fixture] by name.
Map<String, OperationIr> _methods(IrFixture fixture) => {
  for (final group in fixture.build().groups)
    for (final o in group.operations) o.name: o,
};

const _jsonAndEvents = '''
  /f:
    get:
      operationId: f
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
''';

void main() {
  group('the name of the second method', () {
    test('says a reserved name is one Dart has (TOA550)', () {
      final fixture = IrFixture(
        _spec(_jsonAndEvents),
        generation: const GenerationConfig(streamSuffix: 'or'),
      );
      expect(_methods(fixture).keys, ['f', 'for_']);
      final report = fixture.reportedOf(DiagnosticCode.nameReserved).single;
      expect(report.message, contains('"for" is a name Dart already has'));
      expect(report.message, contains('"for_"'));
      expect(report.message, isNot(contains('Another method')));
    });

    test('is still a collision when another method has the name', () {
      final fixture = IrFixture(
        _spec('''
$_jsonAndEvents
  /fs:
    get:
      operationId: fStream
      responses:
        "200": {description: ok}
'''),
      );
      _methods(fixture);
      final report = fixture.reportedOf(DiagnosticCode.nameCollision).single;
      expect(report.message, contains('Another method of the group'));
    });

    test('of an operation named new is newStream', () {
      final fixture = IrFixture(
        _spec(_jsonAndEvents.replaceAll('operationId: f', 'operationId: new')),
      );
      expect(_methods(fixture).keys, ['newStream', 'new_']);
    });

    test('says what the body is when it is not JSON (TOA663)', () {
      final fixture = IrFixture(
        _spec('''
  /t:
    get:
      operationId: t
      responses:
        "200":
          description: ok
          content:
            text/plain: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
'''),
      );
      _methods(fixture);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamMethodAdded);
      expect(report.single.message, isNot(contains('JSON')));
      expect(report.single.message, contains('"t" returns the body'));
      expect(report.single.message, contains('"tStream" the events'));
    });
  });

  group('an event stream on an error status', () {
    test('of a method that does not return events is read as text', () {
      final fixture = IrFixture(
        _spec('''
  /e:
    get:
      operationId: e
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: string}}}}
        "404": {description: no, content: {text/event-stream: {schema: {type: string}}}}
        default: {description: bad, content: {text/event-stream: {schema: {type: string}}}}
'''),
      );
      _methods(fixture);
      final reports = fixture.reportedOf(DiagnosticCode.eventStreamErrorAsText);
      expect(
        [for (final d in reports) d.pointer?.value],
        [
          '#/paths/~1e/get/responses/404/content/text~1event-stream',
          '#/paths/~1e/get/responses/default/content/text~1event-stream',
        ],
      );
      expect(reports.first.message, contains('read as text'));
    });

    test('is reported once for the two methods of an operation', () {
      final fixture = IrFixture(
        _spec('''
  /e:
    get:
      operationId: e
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "500": {description: bad, content: {text/event-stream: {schema: {type: string}}}}
'''),
      );
      _methods(fixture);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamErrorAsText),
        hasLength(1),
      );
    });

    test('is not reported for a success', () {
      final fixture = IrFixture(_spec(_jsonAndEvents));
      _methods(fixture);
      expect(
        fixture.reportedOf(DiagnosticCode.eventStreamErrorAsText),
        isEmpty,
      );
    });
  });

  group('TOA654 says what is not generated', () {
    const different = '''
  /a:
    get:
      operationId: a
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: integer}}
''';

    test('the second method only, when the method of the body is', () {
      final fixture = IrFixture(_spec(different));
      expect(_methods(fixture).keys, ['a']);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report.single.message, contains('event-stream method'));
      expect(report.single.message, isNot(contains('operation is not')));
    });

    test('the operation, when it is only a stream', () {
      final fixture = IrFixture(
        _spec(
          different.replaceAll(
            'application/json: {schema: {type: string}}',
            '',
          ),
        ),
      );
      expect(_methods(fixture), isEmpty);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report.single.message, contains('operation is not generated'));
    });

    test('a stream next to one that offers a body too is not "others"', () {
      final fixture = IrFixture(
        _spec('''
  /third:
    get:
      operationId: third
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            text/event-stream: {schema: {type: string}}
'''),
      );
      expect(_methods(fixture), isEmpty);
      final report = fixture.reportedOf(DiagnosticCode.eventStreamNotGenerated);
      expect(report.single.message, contains('only an event stream'));
      expect(report.single.message, isNot(contains('a body that is not')));
    });
  });

  group('sse method only', () {
    test('reports the body it drops (TOA651)', () {
      final fixture = IrFixture(
        _spec('''
  /o:
    get:
      operationId: o
      responses:
        "200":
          description: ok
          content:
            application/octet-stream: {schema: {type: string, format: binary}}
            text/event-stream: {schema: {type: string}}
'''),
        overrides: 'operations:\n  o: {sse: {method: only}}\n',
      );
      expect(_methods(fixture).keys, ['o']);
      final report = fixture.reportedOf(DiagnosticCode.mediaTypesDropped);
      expect(report.single.message, contains('"application/octet-stream"'));
      expect(report.single.message, contains('sse.method'));
      expect(
        report.single.pointer?.value,
        '#/paths/~1o/get/responses/200/content',
      );
    });

    test('reports nothing for a stream alone', () {
      final fixture = IrFixture(
        _spec('''
  /o:
    get:
      operationId: o
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
'''),
        overrides: 'operations:\n  o: {sse: {method: only}}\n',
      );
      _methods(fixture);
      expect(fixture.reportedOf(DiagnosticCode.mediaTypesDropped), isEmpty);
    });
  });

  group('Accept of the method that returns the body', () {
    test('is the JSON type the response offers, +json included', () {
      final fixture = IrFixture(
        _spec('''
  /v:
    get:
      operationId: v
      responses:
        "200":
          description: ok
          content:
            application/vnd.api+json; charset=utf-8: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
'''),
      );
      expect(_methods(fixture)['v']!.accept, 'application/vnd.api+json');
    });

    test('lists the media type of every 2xx with a body', () {
      final fixture = IrFixture(
        _spec('''
  /m:
    get:
      operationId: m
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            text/plain: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "202":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "204": {description: none}
'''),
      );
      expect(
        _methods(fixture)['m']!.accept,
        'application/json, text/plain',
      );
    });

    test('is not sent when the stream method is not generated', () {
      final fixture = IrFixture(
        _spec('''
  /a:
    get:
      operationId: a
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: string}}
        "201":
          description: ok
          content:
            application/json: {schema: {type: string}}
            text/event-stream: {schema: {type: integer}}
'''),
      );
      final methods = _methods(fixture);
      expect(methods.keys, ['a']);
      expect(methods['a']!.accept, isNull);
    });
  });
}
