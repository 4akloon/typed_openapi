import 'ir_context.dart';
import 'locked_names.dart';
import 'names.dart';
import 'spec_operation.dart';

/// Names the second method of an operation that returns a body or an
/// event stream (M10, TOA663): the one that returns the events.
final class StreamMethodNames {
  /// Creates the namer for the client of [_context].
  const StreamMethodNames(this._context);

  static final _reservedSuffix = RegExp(r'_+$');

  final IrContext _context;

  /// The name of the second method of an operation named [name] that also
  /// returns a body: [name] with `naming.stream_suffix`, claimed in the
  /// group's [methods] after every other method (TOA663, and TOA550 or
  /// TOA551 when taken), or the name the API lock keeps for it.
  String of(SpecOperation entry, String name, NameScope methods) {
    // A reserved word's suffix (`class_`) gives way to the stream suffix,
    // so the name stays lowerCamelCase (`classStream`).
    final base = name.replaceFirst(_reservedSuffix, '');
    final candidate =
        '${base.isEmpty ? name : base}${_context.config.streamSuffix}';
    final (claimed, change) = LockedNames(
      _context,
    ).claimMethod(methods, entry, candidate, isStream: true);
    final location = entry.operation.location;
    _context.report(
      .eventStreamMethodAdded,
      'This operation returns a body or an event stream; "$name" returns the '
      'body and "$claimed" the events.',
      location,
      fix: 'Set naming.stream_suffix in the config to name it otherwise.',
    );
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? '"$candidate" is a name Dart already has; the event-stream '
                  'method of ${entry.overrideKey} is named "$claimed".'
            : 'Another method of the group is named "$candidate"; the '
                  'event-stream method of ${entry.overrideKey} is named '
                  '"$claimed".',
        location,
        fix: 'Set naming.stream_suffix in the config, or rename the method.',
      );
    }
    return claimed;
  }
}
