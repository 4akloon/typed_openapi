/// A file the tools download besides the specs (`schemas` of `corpus.yaml`):
/// a JSON schema that offline tests read from the cache, never from the
/// repository.
final class PinnedSchema {
  /// Creates the entry [name].
  const PinnedSchema({
    required this.name,
    required this.url,
    required this.sha256,
    required this.license,
  });

  /// The name of the entry, also the name of its cache directory.
  final String name;

  /// The URL, pinned to a commit.
  final Uri url;

  /// The SHA-256 of the file.
  final String sha256;

  /// The license or terms the file is under.
  final String license;
}
