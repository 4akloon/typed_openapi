import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/parse/object_reader.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (ObjectReader, SpecFixture) read(String yaml) {
    final fixture = SpecFixture(yaml);
    final reader = ObjectReader(
      fixture.context,
      fixture.document.root,
      JsonPointer.root,
    );
    return (reader, fixture);
  }

  test('reads typed fields', () {
    final (r, fixture) = read(
      'name: id\nrequired: true\nmin: 1.5\nsize: 3.0\nstyle: form\n',
    );
    expect(r.string('name'), 'id');
    expect(r.boolean('required'), isTrue);
    expect(r.number('min'), 1.5);
    expect(r.count('size'), 3);
    expect(r.choice('style', {'form': 1, 'simple': 2}), 1);
    expect(r.string('absent'), isNull);
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('a value of the wrong type is reported and read as missing', () {
    final (r, fixture) = read('name: 5\nrequired: "yes"\nsize: -1\n');
    expect(r.string('name'), isNull);
    expect(r.boolean('required'), isNull);
    expect(r.count('size'), isNull);
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, ['#/name', '#/required', '#/size']);
    expect(
      fixture.diagnostics.all.first.message,
      '"name" must be a string, not the number 5; it is ignored.',
    );
    expect(fixture.diagnostics.all.first.severity, Severity.warning);
  });

  test('a value outside a choice is reported', () {
    final (r, fixture) = read('in: body\n');
    expect(r.choice('in', {'query': 1, 'path': 2}), isNull);
    expect(
      fixture.diagnostics.all.single.message,
      '"in" must be one of query, path, not "body".',
    );
  });

  test('reads lists and maps; bad items are reported and skipped', () {
    final (r, fixture) = read(
      'tags: [a, 1, b]\nscopes: {read: Read, write: 2}\nenum: [a, null]\n',
    );
    expect(r.strings('tags'), ['a', 'b']);
    expect(r.stringMap('scopes'), {'read': 'Read'});
    expect(r.rawList('enum'), ['a', null]);
    expect(fixture.pointers, ['#/tags/1', '#/scopes/write']);
  });

  test('map can skip x- keys that are not entries', () {
    final (r, _) = read('paths: {/a: 1, x-internal: 2}\n');
    expect(r.map('paths', (raw, _) => raw, skipExtensions: true), {'/a': 1});
  });

  test('a missing required field is reported at the object', () {
    final (r, fixture) = read('summary: s\n');
    expect(r.requiredString('name'), isNull);
    expect(fixture.codes, [DiagnosticCode.missingRequiredField]);
    expect(fixture.pointers, ['#']);
  });

  test('keeps x- keys and reports unknown keys after reading', () {
    final (r, fixture) = read(
      'name: a\nx-order: 1\nnmae: typo\nexternalDocs: {}\n',
    );
    r
      ..string('name')
      ..accept(['externalDocs']);
    expect(r.extensions, {'x-order': 1});
    expect(r.unknownKeys(), {'nmae': 'typo'});
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
    expect(fixture.pointers, ['#/nmae']);
    expect(fixture.diagnostics.all.single.line, 3);
  });

  test('value tells an explicit null from a missing key', () {
    final (r, _) = read('default: null\n');
    expect(r.value('default'), (null,));
    expect(r.value('example'), isNull);
  });
}
