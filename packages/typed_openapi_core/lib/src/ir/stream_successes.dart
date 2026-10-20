import '../model/operation.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'response_statuses.dart';

/// The 2xx successes of an operation by how they use `text/event-stream`,
/// as statuses in the order of the spec.
final class StreamSuccesses {
  const StreamSuccesses._({
    required this.streams,
    required this.alone,
    required this.others,
  });

  /// Counts the successes of [operation] that [context] resolves.
  factory StreamSuccesses.of(IrContext context, Operation operation) {
    final streams = <String>[];
    final alone = <String>[];
    final others = <String>[];
    for (final (status, written) in ResponseStatuses(context).of(operation)) {
      final response = context.model.resolve(written);
      if (!status.startsWith('2') || response == null) continue;
      final kinds = {
        for (final type in response.content.keys) MediaTypePicker.kindOf(type),
      };
      if (!kinds.contains(BodyKind.eventStream)) {
        if (kinds.isNotEmpty) others.add(status);
        continue;
      }
      streams.add(status);
      if (kinds.length == 1) alone.add(status);
    }
    return StreamSuccesses._(streams: streams, alone: alone, others: others);
  }

  /// The successes that offer an event stream.
  final List<String> streams;

  /// The [streams] that offer nothing else.
  final List<String> alone;

  /// The successes that have a body and no event stream.
  final List<String> others;
}
