import '../overrides/override_set.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';

/// The result of normalizing a spec.
final class NormalizedSpec {
  /// Creates a result.
  const NormalizedSpec(this.model, this.documents, {this.overrides});

  /// The model of the last pass.
  final SpecModel model;

  /// The files of the last pass, with every fix applied.
  final SpecDocuments documents;

  /// The client's overrides, whose spec fields are applied; their
  /// generation fields are for the generator.
  final OverrideSet? overrides;
}
