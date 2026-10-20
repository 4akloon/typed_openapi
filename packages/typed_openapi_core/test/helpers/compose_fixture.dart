import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/load/yaml_composer.dart';

/// Composes texts as the file `api.yaml` (or `api.json`).
final class ComposeFixture {
  /// Creates the fixture.
  const ComposeFixture();

  /// Composes [text] as `api.yaml` (or `api.json` with [json]).
  (ComposedYaml?, DiagnosticBag) compose(String text, {bool json = false}) {
    final bag = DiagnosticBag();
    final result = YamlComposer(bag).compose(
      text,
      file: json ? 'api.json' : 'api.yaml',
      uri: Uri.file('/specs/api.yaml'),
      json: json,
    );
    return (result, bag);
  }

  /// The plain tree of [text]; it must compose without diagnostics.
  Object? plain(String text) {
    final (result, bag) = compose(text);
    expect(bag.all, isEmpty, reason: text);
    expect(result?.syntaxError, isNull, reason: text);
    return result!.root;
  }
}
