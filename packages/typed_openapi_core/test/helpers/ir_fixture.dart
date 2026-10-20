import 'package:typed_openapi_core/src/ir/ir_context.dart';
import 'package:typed_openapi_core/src/snapshot/snapshot_name_lock.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// A [NormalizedFixture] with the [IrContext] the IR builder's parts take.
final class IrFixture extends NormalizedFixture {
  /// Loads [text] as `api.yaml`; see [NormalizedFixture.new].
  IrFixture(
    super.text, {
    super.generation,
    super.overrides,
    super.preset,
    super.clientName,
  }) {
    context = IrContext(diagnostics, spec, client);
  }

  /// The context for building the IR.
  // Set in the constructor body, after `spec` and `client`.
  late final IrContext context;

  /// The names the API lock of [ir], an IR of this spec, keeps.
  NameLock lockOf(ClientIr ir) {
    final root = context.spec.model.document.location.document;
    return SnapshotNameLock.of(SnapshotBuilder(root).build(ir), root);
  }
}
