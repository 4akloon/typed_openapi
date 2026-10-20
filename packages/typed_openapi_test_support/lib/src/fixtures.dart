import 'dart:io';
import 'dart:isolate';

/// The OpenAPI fixture specs under `lib/fixtures/` of this package.
///
/// Works on the VM only: it resolves a package URI and reads files.
final class Fixtures {
  const Fixtures._();

  /// The text of the fixture [name], for example `petstore.yaml`.
  static String read(String name) => File(path(name)).readAsStringSync();

  /// The absolute path of the fixture [name].
  ///
  /// Throws a [StateError] when this package is not a dependency of the
  /// running program.
  static String path(String name) {
    final uri = Isolate.resolvePackageUriSync(
      Uri.parse('package:typed_openapi_test_support/fixtures/$name'),
    );
    if (uri == null) {
      throw StateError('typed_openapi_test_support is not a dependency.');
    }
    return uri.toFilePath();
  }
}
