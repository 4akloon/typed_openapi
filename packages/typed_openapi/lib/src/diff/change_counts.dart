import 'api_change.dart';

/// The number of changes in each [ChangeCategory]: what `generate` prints
/// for a client and what `diff --fail-on` decides by (M12, decision 4).
final class ChangeCounts {
  /// Counts [changes] by category.
  ChangeCounts(Iterable<ApiChange> changes)
    : _counts = {
        for (final category in ChangeCategory.values)
          category: changes.where((c) => c.category == category).length,
      };

  final Map<ChangeCategory, int> _counts;

  /// The number of changes of [category].
  int of(ChangeCategory category) => _counts[category]!;

  /// Whether there is no change at all.
  bool get isEmpty => _counts.values.every((count) => count == 0);

  /// Every category with its count, in the order of [ChangeCategory]:
  /// `1 breaking, 0 switch-breaking, 0 wire, 2 additive, 0 docs`.
  @override
  String toString() => [
    for (final category in ChangeCategory.values)
      '${of(category)} ${category.label}',
  ].join(', ');
}
