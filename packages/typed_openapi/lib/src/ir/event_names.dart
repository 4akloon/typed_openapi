import '../diagnostics/message_text.dart';

/// Which event names an SSE `event:` line can carry.
final class EventNames {
  const EventNames._();

  /// Why no event can have the [name], as the start of a sentence; null
  /// when one can. An empty `event:` is read as `message`, and a name
  /// cannot hold a line break, which ends the line.
  static String? unreachable(String name) {
    if (name.isEmpty) {
      return 'The event name is empty, and an empty "event:" is read as '
          '"message"';
    }
    if (name.contains('\n') || name.contains('\r')) {
      return 'The event name ${MessageText.quote(name)} has a line break, '
          'which ends the "event:" line';
    }
    return null;
  }

  /// The report text of an event named [name] that [reason] makes
  /// unreachable: its variant is left out.
  static String message(String reason) =>
      '$reason, so no event can select this variant; it is left out.';

  /// What to do about an unreachable event name.
  static const fix =
      'Name the event with a non-empty name without line '
      'breaks at the source.';
}
