import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/resolve/ref_target.dart';

void main() {
  final base = Uri.parse('file:///project/specs/api.yaml');

  String target(String ref) => switch (RefTarget.parse(ref, base)) {
    ResolvableRef(:final location) => '$location',
    BrokenRef(:final code) => code.id,
  };

  test('a local pointer stays in the same document', () {
    expect(
      target('#/components/schemas/Pet'),
      'file:///project/specs/api.yaml#/components/schemas/Pet',
    );
  });

  test('a relative file resolves against the document', () {
    expect(
      target('../common/errors.yaml#/Error'),
      'file:///project/common/errors.yaml#/Error',
    );
    expect(target('./pet.yaml'), 'file:///project/specs/pet.yaml#');
  });

  test('the fragment is percent-decoded and keeps ~ escapes', () {
    expect(
      target('#/paths/~1pets~1%7Bid%7D/get'),
      'file:///project/specs/api.yaml#/paths/~1pets~1{id}/get',
    );
  });

  test('remote documents are not read', () {
    expect(target('https://example.com/api.yaml#/A'), 'TOA102');
    expect(target('urn:example:pet'), 'TOA102');
  });

  test('empty, truncated and malformed references are invalid', () {
    for (final ref in [
      '',
      '#/components/schemas/',
      '#/',
      '#/components/schemas',
      '#/components',
      '#Pet',
      '#/a/%zz',
      '#/a~2b',
      'http://[bad#/a',
    ]) {
      expect(target(ref), 'TOA100', reason: ref);
    }
  });

  test('a broken reference says why', () {
    final broken = RefTarget.parse('#/components/schemas/', base) as BrokenRef;
    expect(broken.code, DiagnosticCode.invalidRef);
    expect(
      broken.reason,
      '"#/components/schemas/" ends with "/", so the name of the target is '
      'missing.',
    );
  });
}
