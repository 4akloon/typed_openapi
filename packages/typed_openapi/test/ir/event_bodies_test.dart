import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

/// The methods of the only group of [ir] by name.
Map<String, OperationIr> _methods(ClientIr ir) => {
  for (final o in ir.groups.single.operations) o.name: o,
};

/// The kind of the only success of [operation].
BodyKind _kind(OperationIr operation) => operation.successes.single.kind;

void main() {
  final fixture = IrFixture(
    File(
      p.join('test', 'emit', 'fixtures', 'event_bodies.yaml'),
    ).readAsStringSync(),
  );
  final ir = fixture.build();
  final methods = _methods(ir);

  group('an operation that offers a body and an event stream', () {
    test('gets the body from the method and the events from a second', () {
      expect(methods.keys, [
        'download',
        'downloadStream',
        'note',
        'noteStream',
        'report',
        'reportStream',
        'status',
        'statusStream',
      ]);
      for (final name in ['download', 'note', 'report', 'status']) {
        expect(methods[name]!.events, isNull, reason: name);
        expect(methods['${name}Stream']!.events, isNotNull, reason: name);
        expect(
          _kind(methods['${name}Stream']!),
          BodyKind.eventStream,
          reason: name,
        );
      }
    });

    test('keeps application/octet-stream as bytes', () {
      expect(_kind(methods['download']!), BodyKind.bytes);
      expect(
        methods['download']!.successes.single.type,
        const CoreType(.binary),
      );
      expect(methods['downloadStream']!.events!.data, isNull);
    });

    test('keeps application/xml as bytes', () {
      expect(_kind(methods['report']!), BodyKind.bytes);
      expect(methods['report']!.successes.single.type, const CoreType(.binary));
      expect(
        methods['reportStream']!.events!.data?.code(ir.nameOf),
        'Tick',
      );
    });

    test('keeps text/plain as text', () {
      expect(_kind(methods['note']!), BodyKind.text);
      expect(methods['note']!.successes.single.type, const CoreType(.string));
    });

    test('keeps JSON as JSON', () {
      expect(_kind(methods['status']!), BodyKind.json);
      expect(methods['status']!.successes.single.type?.code(ir.nameOf), 'Tick');
    });

    test('reports each added method, and drops nothing silently', () {
      expect(fixture.reportedOf(.eventStreamMethodAdded), hasLength(4));
      expect(fixture.reportedOf(.mediaTypesDropped), isEmpty);
      final asBytes = fixture.reportedOf(.mediaTypeAsBytes);
      expect(asBytes, isEmpty, reason: 'the schemas are plain strings');
      expect(fixture.reportedOf(.eventStreamNotGenerated), isEmpty);
    });
  });

  test('sse method none keeps the bytes of an operation that offers both', () {
    final none = IrFixture(
      File(
        p.join('test', 'emit', 'fixtures', 'event_bodies.yaml'),
      ).readAsStringSync(),
      overrides: 'operations:\n  download: {sse: {method: none}}\n',
    );
    final download = _methods(none.build())['download']!;
    expect(download.events, isNull);
    expect(_kind(download), BodyKind.bytes);
    expect(none.reportedOf(.mediaTypesDropped), hasLength(1));
  });

  test('the method that returns the body asks for it with Accept', () {
    expect(
      {
        for (final MapEntry(:key, :value) in methods.entries) key: value.accept,
      },
      {
        'download': 'application/octet-stream',
        'downloadStream': null,
        'note': 'text/plain',
        'noteStream': null,
        'report': 'application/xml',
        'reportStream': null,
        'status': 'application/json',
        'statusStream': null,
      },
    );
  });
}
