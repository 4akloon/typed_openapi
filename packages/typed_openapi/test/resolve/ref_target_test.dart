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

  test('a document with a query or a host is not a local file', () {
    expect(target('x.yaml?q#/A'), 'TOA100');
    expect(target('//host/x.yaml#/A'), 'TOA102');
    expect(target('file://host/x.yaml#/A'), 'TOA102');
    expect(target('file:///abs/x.yaml#/A'), 'file:///abs/x.yaml#/A');
  });

  test('a file name that is not UTF-8 after percent-decoding is invalid', () {
    for (final ref in ['%FF.yaml#/A', 'caf%E9.yaml', '../%C0%AF/x.yaml#/A']) {
      final broken = RefTarget.parse(ref, base) as BrokenRef;
      expect(broken.code, DiagnosticCode.invalidRef, reason: ref);
      expect(
        broken.reason,
        '"$ref" has a file name that is not valid UTF-8 after '
        'percent-decoding.',
      );
    }
    expect(
      target('caf%C3%A9.yaml#/A'),
      'file:///project/specs/caf%C3%A9.yaml#/A',
    );
    expect(
      target('my%20spec.yaml#/A'),
      'file:///project/specs/my%20spec.yaml#/A',
    );
  });

  test('a bad fragment says what is wrong with it', () {
    String reason(String ref) =>
        (RefTarget.parse(ref, base) as BrokenRef).reason;

    expect(
      reason('#/a/%zz'),
      '"#/a/%zz" has an invalid percent-escape in the fragment.',
    );
    expect(
      reason('#/a~2b'),
      '"#/a~2b" has a "~" that is not followed by 0 or 1.',
    );
    expect(
      reason('#/a%7E'),
      '"#/a%7E" has a "~" that is not followed by 0 or 1.',
    );
    expect(
      reason('#Pet'),
      '"#Pet" does not end with a JSON pointer such as '
      '"#/components/schemas/Name".',
    );
    expect(
      reason('x.yaml?q#/A'),
      '"x.yaml?q#/A" has a query string, which a local file cannot have.',
    );
  });
}
