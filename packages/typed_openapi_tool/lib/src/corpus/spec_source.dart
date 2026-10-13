/// Where a corpus spec is downloaded from.
sealed class SpecSource {
  /// Creates the source at [url].
  const SpecSource(this.url);

  /// The URL, pinned to a commit or a tag.
  final Uri url;

  /// The path of the spec file in the spec's cache directory.
  String get entry;
}

/// A spec that is one file, saved under the last segment of its URL (empty
/// when the URL has none; the reader refuses that).
final class FileSource extends SpecSource {
  /// Creates the source at [url].
  const FileSource(super.url);

  @override
  String get entry => url.pathSegments.lastOrNull ?? '';
}

/// A spec of several files: a `.tar.gz` archive whose top directory holds
/// [root]; only [root] is kept, and [entry] is the spec file in it.
final class ArchiveSource extends SpecSource {
  /// Creates the source at [url].
  const ArchiveSource(super.url, {required this.root, required this.entry});

  /// The directory of the archive, below its top directory, that is kept.
  final String root;

  @override
  final String entry;
}
