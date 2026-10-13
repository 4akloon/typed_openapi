/// What [OutputWriter.write] did to an output directory.
final class OutputChanges {
  /// Creates the counts.
  const OutputChanges({
    required this.written,
    required this.unchanged,
    required this.deleted,
    this.forced = 0,
  });

  /// Files written because they are new or their content changed.
  final int written;

  /// Files whose content was already the generated one.
  final int unchanged;

  /// Files deleted because the generator no longer writes them.
  final int deleted;

  /// How many of the files written over or deleted were not the generator's
  /// own or had changed since it wrote them, and went only because of
  /// `force`.
  final int forced;
}
