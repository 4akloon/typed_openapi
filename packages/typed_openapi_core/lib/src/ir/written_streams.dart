import '../model/media_type.dart';
import '../model/spec_node.dart';
import '../overrides/sse_override.dart';
import 'ir_context.dart';
import 'spec_operation.dart';

/// An event-stream success of an operation: its status, where its media
/// type is and the media type.
typedef StreamSuccess = (String, SpecLocation, MediaType?);

/// Tells which event-stream successes of an operation are written in it and
/// which are shared (a `$ref`'d response): the `data` and `events` of an
/// `sse` override change only the written ones (decision 6 of M10).
final class WrittenStreams {
  /// Creates the check; it reports through [_context].
  const WrittenStreams(this._context);

  final IrContext _context;

  /// Whether [at] is written in the operation of [entry], not in a response
  /// it refers to.
  bool isWritten(SpecOperation entry, SpecLocation at) {
    final operation = entry.operation.location;
    if (at.document != operation.document) return false;
    final own = operation.pointer.tokens;
    final tokens = at.pointer.tokens;
    if (tokens.length < own.length) return false;
    for (final (index, token) in own.indexed) {
      if (tokens[index] != token) return false;
    }
    return true;
  }

  /// Whether [sse] writes the media types of the event streams: it has
  /// `data` or `events`.
  static bool writes(SseOverride? sse) =>
      sse != null && (sse.data != null || sse.events != null);

  /// The statuses of the [streams] of [entry] that [sse] leaves alone
  /// because they are shared, when it changes at least one written stream;
  /// reported (TOA669). Empty when there is none, or no written stream (the
  /// override applier reports that).
  List<String> leftAlone(
    SpecOperation entry,
    SseOverride? sse,
    List<StreamSuccess> streams,
  ) {
    if (sse == null || !writes(sse)) return const [];
    final shared = [
      for (final (status, at, _) in streams)
        if (!isWritten(entry, at)) status,
    ];
    if (shared.isEmpty || shared.length == streams.length) return const [];
    final part = sse.data != null ? 'data' : 'events';
    _context.reportAtPointer(
      .sseOverrideNotApplied,
      'The "$part" of "sse" is not applied to the shared response of '
      '${_statuses(shared)}, which is a reference to a response of the '
      'spec: only responses written in the operation are changed.',
      sse.pointer,
      fix:
          'Override the schema the shared response uses by its component '
          'name, or write the response in this operation.',
    );
    return shared;
  }

  static String _statuses(List<String> statuses) => statuses.length == 1
      ? 'status ${statuses.single}'
      : 'statuses ${statuses.join(', ')}';
}
