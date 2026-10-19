import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/test_platform.dart';

/// What the runtime does differently on the VM, dart2js and dart2wasm (the
/// M11 matrix rows of the roadmap). Each test pins the behaviour of every
/// platform, so a change on one of them is seen; the differences are
/// documented limitations, not defects.
void main() {
  test('a double 1.0 in a query is 1.0, but 1 in JavaScript', () {
    // dart2js has one number type: 1.0 is the int 1 and prints as "1".
    expect(
      const QueryParameter('x', 1.0).encode(),
      TestPlatform.isJavaScript ? 'x=1' : 'x=1.0',
    );
    expect(const QueryParameter('x', 1.5).encode(), 'x=1.5');
  });

  test('NaN equals itself in DeepEquality, but not in JavaScript', () {
    // DeepEquality starts with identical(), which compares the bits of a
    // double on the VM and on Wasm and is === in JavaScript. JSON has no
    // NaN, so a decoded value never holds one.
    const equality = DeepEquality();
    expect(
      equality.equals([double.nan], [double.nan]),
      !TestPlatform.isJavaScript,
    );
    expect(equality.equals([1.5], [1.5]), isTrue);
  });
}
