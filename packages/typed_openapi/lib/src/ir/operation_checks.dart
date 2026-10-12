import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'operation_builder.dart';
import 'response_statuses.dart';

/// Reports what an operation has that the client does not generate (M9):
/// event streams (until M10), a missing 2xx, servers of a path item or an
/// operation, callbacks and the document's webhooks.
final class OperationChecks {
  /// Creates the checks; they report through [_context].
  const OperationChecks(this._context);

  final IrContext _context;

  /// Whether a success of [responses] is an event stream, which is
  /// reported (TOA654): such an operation is generated from M10.
  bool isEventStream(List<ResponseIr> responses) {
    final stream = responses
        .where((r) => r.isSuccess && r.kind == .eventStream)
        .firstOrNull;
    if (stream == null) return false;
    _context.report(
      .eventStreamNotGenerated,
      'The ${stream.status} response is "${stream.contentType}": event '
      'streams are generated from M10, so the operation is not generated.',
      stream.location,
      fix: 'Leave it out with exclude until then.',
    );
    return true;
  }

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
  /// client sends every request to the Dio base URL.
  void servers(SpecOperation entry) {
    for (final (node, servers, what) in [
      (entry.item, entry.item.servers, 'path item'),
      (entry.operation, entry.operation.servers, 'operation'),
    ]) {
      if (servers.isEmpty) continue;
      _context.report(
        .operationServersIgnored,
        'The $what has servers of its own; the client sends its requests to '
        'the base URL of your Dio.',
        node.location.child('servers'),
        fix:
            'Set the base URL for these requests in an interceptor, or move '
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
