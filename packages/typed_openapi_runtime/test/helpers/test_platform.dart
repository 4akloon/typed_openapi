/// Facts about the platform a test runs on.
abstract final class TestPlatform {
  /// Whether the test runs in a browser, compiled by dart2js or dart2wasm.
  static const bool isWeb = bool.fromEnvironment('dart.library.js_interop');
}
