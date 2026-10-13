import 'expectation.dart';
import 'spec_source.dart';

/// One public spec of the corpus (`corpus.yaml`): where it is downloaded
/// from, the hash that pins it, its license and what generation is expected
/// to do with it.
final class CorpusSpec {
  /// Creates the entry [name].
  const CorpusSpec({
    required this.name,
    required this.source,
    required this.sha256,
    required this.license,
    required this.expectation,
  });

  /// The name of the entry, also the name of its client.
  final String name;

  /// Where the spec is downloaded from.
  final SpecSource source;

  /// The SHA-256 of the file, or of the tree of an archive (`TreeHash`).
  final String sha256;

  /// The SPDX identifier of the spec's license, or a sentence when the
  /// license is not stated.
  final String license;

  /// What generation does with the spec.
  final Expectation expectation;
}
