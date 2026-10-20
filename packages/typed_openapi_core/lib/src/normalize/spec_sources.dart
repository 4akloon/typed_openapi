import '../load/spec_document.dart';
import '../resolve/spec_documents.dart';

/// The files of a spec between two reads: the root and the other files the
/// last read loaded, each with the edits applied so far.
final class SpecSources {
  /// Creates sources from the [root] and the [others] already loaded.
  const SpecSources(this.root, this.others);

  /// The sources after [edited] (documents by URI) replaced the files of
  /// [documents] they name; [root] says which file is the root.
  factory SpecSources.edited(
    SpecDocument root,
    SpecDocuments documents,
    Map<Uri, SpecDocument> edited,
  ) {
    final editedRoot = edited[root.uri] ?? root;
    return SpecSources(editedRoot, [
      for (final loaded in documents.loaded)
        if (loaded.uri != editedRoot.uri) edited[loaded.uri] ?? loaded,
    ]);
  }

  /// The document the spec starts from.
  final SpecDocument root;

  /// The files the root refers to, as far as they were loaded.
  final List<SpecDocument> others;
}
