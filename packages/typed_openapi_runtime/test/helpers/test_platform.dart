/// Facts about the platform a test runs on.
abstract final class TestPlatform {
  /// Whether the test runs in a browser, compiled by dart2js or dart2wasm.
  static const bool isWeb = bool.fromEnvironment('dart.library.js_interop');

  /// Whether the test is compiled to JavaScript, where `0` and `0.0` are the
  /// same value (dart2wasm keeps them apart).
  static const bool isJavaScript = identical(0, 0.0);
}
