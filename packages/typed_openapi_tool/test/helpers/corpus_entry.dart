import 'package:path/path.dart' as p;
import 'package:typed_openapi_tool/src/corpus/corpus_spec.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/spec_source.dart';

/// An entry named [name] with the expectation [expectation].
CorpusSpec entry(String name, Expectation expectation) => CorpusSpec(
  name: name,
  source: FileSource(Uri.parse('https://example.com/$name.yaml')),
  sha256: '',
  license: 'MIT',
  expectation: expectation,
);

/// The directory of `typed_openapi_client`, from the tool package.
String runtimeDirectory() =>
    p.normalize(p.absolute(p.join('..', 'typed_openapi_client')));
