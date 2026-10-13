import '../model/operation.dart';
import '../model/spec_node.dart';
import 'event_agreement.dart';
import 'event_data.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'names.dart';
import 'operation_builder.dart';
import 'response_statuses.dart';
import 'schema_mapper.dart';
import 'sse_override_checks.dart';

/// How the successes of an operation use `text/event-stream`.
enum StreamShape {
  /// No success is an event stream.
  none,

  /// Every success with a body is only an event stream: one method that
  /// returns the events.
  only,

  /// Every success with an event stream offers another body too: the
  /// operation's method and a second one that returns the events.
  both,

  /// Some successes are event streams and others have a body that is not
  /// (TOA654): not generated.
  mixed,

  /// Every success is only an event stream and the override says
  /// `sse.method: none`: not generated.
  excluded,
}

/// Decides how an operation's event streams are generated (decisions 1, 3
/// and 5 of M10): its [StreamShape], the name of a second method, the type
/// of the events and how the stream reconnects.
final class EventStreams {
  /// Creates the decisions; types are mapped with [mapper].
  EventStreams(this._context, SchemaMapper mapper)
    : _statuses = ResponseStatuses(_context),
      _data = EventData(_context, mapper),
      _agreement = EventAgreement(_context),
      _checks = SseOverrideChecks(_context);

  static final _reservedSuffix = RegExp(r'_+$');

  final IrContext _context;
  final ResponseStatuses _statuses;
  final EventData _data;
  final EventAgreement _agreement;
  final SseOverrideChecks _checks;

  /// How the successes of [operation] use event streams; [StreamShape.mixed]
  /// is reported (TOA654).
  StreamShape shapeOf(Operation operation) {
    final (:streams, :alone, :others) = _count(operation);
    if (streams == 0) {
      if (_context.overrides.operationAt(operation.location)?.sse
          case final sse?) {
        _checks.withoutStream(sse);
      }
      return .none;
    }
    if (others == 0 && (alone == streams || alone == 0)) {
      final method = _context.overrides.operationAt(operation.location)?.sse;
      return switch ((alone == streams, method?.method)) {
        (true, .none) => .excluded,
        (true, _) => .only,
        (false, .only) => .only,
        (false, .none) => .none,
        (false, _) => .both,
      };
    }
    _context.report(
      .eventStreamNotGenerated,
      'Some successes of this operation are event streams and others have '
      'a body that is not, so neither a method that returns the body nor '
      'one that returns the events covers them; the operation is not '
      'generated.',
      operation.location.child('responses'),
      fix: 'Offer text/event-stream on every success with a body.',
    );
    return .mixed;
  }

  /// How many 2xx successes of [operation] offer an event stream, how many
  /// of those offer nothing else, and how many have a body without one.
  ({int streams, int alone, int others}) _count(Operation operation) {
    var streams = 0;
    var alone = 0;
    var others = 0;
    for (final (status, written) in _statuses.of(operation)) {
      final response = _context.model.resolve(written);
      if (!status.startsWith('2') || response == null) continue;
      final kinds = {
        for (final type in response.content.keys) MediaTypePicker.kindOf(type),
      };
      if (!kinds.contains(BodyKind.eventStream)) {
        if (kinds.isNotEmpty) others++;
        continue;
      }
      streams++;
      if (kinds.length == 1) alone++;
    }
    return (streams: streams, alone: alone, others: others);
  }

  /// The name of the second method of an operation named [name] that also
  /// returns JSON: [name] with `naming.stream_suffix`, claimed in the group's
  /// [methods] after every other method (TOA663, and TOA551 when taken).
  String methodName(SpecOperation entry, String name, NameScope methods) {
    // A reserved word's suffix (`class_`) gives way to the stream suffix,
    // so the name stays lowerCamelCase (`classStream`).
    final base = name.replaceFirst(_reservedSuffix, '');
    final candidate =
        '${base.isEmpty ? name : base}${_context.config.streamSuffix}';
    final (claimed, change) = methods.claim(candidate);
    final location = entry.operation.location;
    _context.report(
      .eventStreamMethodAdded,
      'This operation returns JSON or an event stream; "$name" returns the '
      'JSON and "$claimed" the events.',
      location,
      fix: 'Set naming.stream_suffix in the config to name it otherwise.',
    );
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        'Another method of the group is named "$candidate"; the event-stream '
        'method of ${entry.overrideKey} is named "$claimed".',
        location,
        fix: 'Set naming.stream_suffix in the config, or rename the method.',
      );
    }
    return claimed;
  }

  /// Whether the event-stream successes of [picked] (their media types are
  /// `text/event-stream`) describe their events alike; not, reported
  /// (TOA654), the operation's stream is not generated. Decided from the
  /// spec, so nothing is declared or named for a stream that is not
  /// generated.
  bool agree(SpecOperation entry, List<PickedResponse> picked) {
    final medias = [
      for (final (status, _, (contentType, media)) in picked)
        if (status.startsWith('2') && contentType != null) media,
    ];
    if (_agreement.agree(medias)) return true;
    _context.report(
      .eventStreamNotGenerated,
      'The event-stream successes of this operation have different event '
      'types, so one stream cannot hold them; the operation is not '
      'generated.',
      entry.operation.location.child('responses'),
      fix: 'Give every event-stream success the same schema at the source.',
    );
    return false;
  }

  /// The events of the stream successes of [picked], which [agree]: those of
  /// the first, named after [prefix].
  EventStreamIr events(
    SpecOperation entry,
    List<PickedResponse> picked,
    String prefix,
  ) {
    final sse = _context.overrides.operationAt(entry.operation.location)?.sse;
    EventShape? shape;
    for (final (status, response, (contentType, media)) in picked) {
      if (!status.startsWith('2') || contentType == null) continue;
      final at = response.location.child('content').child(contentType);
      shape = _data.of(
        media,
        at,
        prefix,
        sse: _isWritten(entry, at) ? sse : null,
      );
      break;
    }
    final keep = sse?.keepUnknown;
    if (sse != null && keep != null && shape?.union == null) {
      _checks.unknownWithoutUnion(sse);
    }
    return EventStreamIr(
      data: shape?.data,
      union: keep == null
          ? shape?.union
          : shape?.union?.keeping(keepUnknown: keep),
      reconnection: _reconnection(entry, sse?.reconnect),
    );
  }

  /// Whether [at] is written in the operation of [entry], not in a response
  /// it refers to: `data` and `events` of an `sse` override are only written
  /// there.
  bool _isWritten(SpecOperation entry, SpecLocation at) {
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

  /// How the stream of [entry] reconnects: a GET when the call asks, or
  /// unless it says no with `sse.reconnect` in the config; any other method
  /// never, reported (TOA665) only when the config asks for reconnection,
  /// since it does not apply there. The `sse.reconnect` override of the
  /// operation ([override]) wins over both.
  StreamReconnection _reconnection(SpecOperation entry, bool? override) {
    if (override != null) return override ? .on : .off;
    final config = _context.config.streamReconnect;
    if (entry.method == 'get') return config ? .on : .onRequest;
    if (config) {
      _context.report(
        .eventStreamReconnectOff,
        'sse.reconnect in the config applies to GET event streams only, so '
        'this ${entry.method.toUpperCase()} operation does not reconnect: '
        'repeating the request may not be safe.',
        entry.operation.location,
        fix: 'Enable it for this operation if the request can be repeated.',
        override: _context.overrideAt(
          ['operations', entry.overrideKey],
          {
            'sse': {'reconnect': true},
          },
        ),
      );
    }
    return .off;
  }
}
