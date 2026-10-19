import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'ir_context.dart';
import 'operation_builder.dart';
import 'response_statuses.dart';

/// Reports what an operation has that the client does not generate (M9):
/// a missing 2xx, servers of a path item or an operation, callbacks and the
/// document's webhooks.
final class OperationChecks {
  /// Creates the checks; they report through [_context].
  const OperationChecks(this._context);

  final IrContext _context;

  /// Reports an operation without a 2xx response (TOA653); a 2xx response
  /// that cannot be resolved is reported already.
  void successes(Operation operation) {
    if (operation.responses.keys.any(
      (key) => ResponseStatuses.isGenerated(key) && key.startsWith('2'),
    )) {
      return;
    }
    _context.report(
      .successUndocumented,
      'No 2xx response is documented, so any 2xx is a success whose value '
      'is the body as JsonValue.',
      operation.location.child('responses'),
      fix: 'Document the success response at the source.',
    );
  }

  /// Reports `servers` of the path item and of the operation (TOA566): the
  /// client sends every request to the base URL of its transport.
  void servers(SpecOperation entry) {
    for (final (node, servers, what) in [
      (entry.item, entry.item.servers, 'path item'),
      (entry.operation, entry.operation.servers, 'operation'),
    ]) {
      if (servers.isEmpty) continue;
      _context.report(
        .operationServersIgnored,
        'The $what has servers of its own; the client sends its requests to '
        'the base URL of its transport.',
        node.location.child('servers'),
        fix:
            'Send these requests through a transport with that base URL, or move '
            'the servers to the document.',
      );
    }
  }

  /// Reports `callbacks` (TOA567): requests the server makes.
  void callbacks(Operation operation) {
    final at = operation.location.child('callbacks');
    final value = _context.documents[at.document]?.valueAt(at.pointer);
    if (value case (
      final Map<String, Object?> callbacks,
    ) when callbacks.isNotEmpty) {
      _context.report(
        .callbacksNotGenerated,
        'The operation has callbacks (${callbacks.keys.join(', ')}): requests '
        'the server makes, which the client does not generate.',
        at,
      );
    }
  }

  /// Reports the document's `webhooks` (TOA567): requests the server
  /// makes, which the client does not generate.
  void webhooks() {
    final webhooks = _context.model.document.webhooks;
    if (webhooks.isEmpty) return;
    _context.report(
      .callbacksNotGenerated,
      'The document has webhooks (${webhooks.keys.join(', ')}): requests the '
      'server makes, which the client does not generate.',
      SpecLocation(
        _context.model.document.location.document,
        JsonPointer.root.child('webhooks'),
      ),
    );
  }
}
