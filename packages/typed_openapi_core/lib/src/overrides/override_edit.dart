import '../normalize/spec_edit.dart';
import 'override_set.dart';

/// An edit an override makes, with the override it comes from.
final class OverrideEdit {
  /// Creates an override edit.
  const OverrideEdit(this.edit, this.sources);

  /// The change of the spec's plain tree.
  final SpecEdit edit;

  /// The entries and fields that ask for the change.
  final List<(OverrideEntry, String)> sources;
}
