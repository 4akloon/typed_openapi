import '../model/operation.dart';
import '../overrides/sse_override.dart';
import 'event_agreement.dart';
import 'event_data.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'names.dart';
import 'response_statuses.dart';
import 'schema_mapper.dart';
import 'spec_operation.dart';
import 'sse_override_checks.dart';
import 'stream_successes.dart';
import 'written_streams.dart';

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
      _written = WrittenStreams(_context),
      _checks = SseOverrideChecks(_context);

  static final _reservedSuffix = RegExp(r'_+$');

  final IrContext _context;
  final ResponseStatuses _statuses;
  final EventData _data;
  final EventAgreement _agreement;
  final WrittenStreams _written;
  final SseOverrideChecks _checks;

  /// How the successes of [operation] use event streams; [StreamShape.mixed]
  /// is reported (TOA654).
  StreamShape shapeOf(Operation operation) {
    final successes = StreamSuccesses.of(_context, operation);
    final (streams, alone, others) = (
      successes.streams.length,
      successes.alone.length,
      successes.others.length,
    );
    if (streams == 0) {
      if (_sse(operation) case final sse?) _checks.withoutStream(sse);
      return .none;
    }
    if (others == 0 && (alone == streams || alone == 0)) {
      return switch ((alone == streams, _sse(operation)?.method)) {
        (true, .none) => .excluded,
        (true, _) => .only,
        (false, .only) => _onlyEvents(operation),
        (false, .none) => .none,
        (false, _) => .both,
      };
    }
    _context.report(
      .eventStreamNotGenerated,
      others > 0
          ? 'Some successes of this operation are event streams and others '
                'have a body that is not, so neither a method that returns '
                'the body nor one that returns the events covers them; the '
                'operation is not generated.'
          : 'Some successes of this operation are only an event stream and '
                'others offer a body next to it, so no one method returns '
                'what every success offers; the operation is not generated.',
      operation.location.child('responses'),
      fix: 'Offer text/event-stream on every success with a body.',
    );
    return .mixed;
  }

  SseOverride? _sse(Operation operation) =>
      _context.overrides.operationAt(operation.location)?.sse;

  /// [StreamShape.only] for an operation that also offers bodies, which
  /// `sse.method: only` drops: reported (TOA651).
  StreamShape _onlyEvents(Operation operation) {
    for (final (status, written) in _statuses.of(operation)) {
      final response = _context.model.resolve(written);
      if (!status.startsWith('2') || response == null) continue;
      final dropped = [
        for (final type in response.content.keys)
          if (MediaTypePicker.kindOf(type) != .eventStream) '"$type"',
      ];
      if (dropped.isEmpty) continue;
      _context.report(
        .mediaTypesDropped,
        'sse.method: only returns the events of the response; '
        '${dropped.join(', ')} ${dropped.length == 1 ? 'is' : 'are'} '
        'dropped.',
        response.location.child('content'),
        fix: 'Remove sse.method: only to keep the body in a method too.',
      );
    }
    return .only;
  }

  /// The name of the second method of an operation named [name] that also
  /// returns a body: [name] with `naming.stream_suffix`, claimed in the
  /// group's [methods] after every other method (TOA663, and TOA550 or
  /// TOA551 when taken).
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

  /// Whether the event-stream successes of [picked] (their media types are
  /// `text/event-stream`) describe their events alike; not, reported
  /// (TOA654), the stream is not generated: the operation of [shape]
  /// [StreamShape.only], only its event-stream method of [StreamShape.both].
  /// Decided from the spec, so nothing is declared or named for a stream
  /// that is not generated. A shared response that `sse.data` or
  /// `sse.events` left alone is named in the report.
  bool agree(
    SpecOperation entry,
    List<PickedResponse> picked,
    StreamShape shape,
  ) {
    final streams = _streamsOf(picked);
    final shared = _written.leftAlone(entry, _sse(entry.operation), streams);
    if (_agreement.agree([for (final (_, _, media) in streams) media])) {
      return true;
    }
    _context.report(
      .eventStreamNotGenerated,
      'The event-stream successes of this operation have different event '
      'types, so one stream cannot hold them; '
      '${shape == .both ? 'its event-stream method' : 'the operation'} is '
      'not generated.'
      '${shared.isEmpty ? '' : ' The shared response of status '
                '${shared.join(', ')} was not overridden: sse.data and '
                'sse.events change only responses written in the operation.'}',
      entry.operation.location.child('responses'),
      fix: shared.isEmpty
          ? 'Give every event-stream success the same schema at the source.'
          : 'Override the schema the shared response uses by its component '
                'name, or write the response in the operation.',
    );
    return false;
  }

  /// The successes of [picked] that are event streams, with where each
  /// media type is.
  List<StreamSuccess> _streamsOf(List<PickedResponse> picked) => [
    for (final (status, response, (contentType, media)) in picked)
      if (status.startsWith('2') && contentType != null)
        (
          status,
          response.location.child('content').child(contentType),
          media,
        ),
  ];

  /// The events of the stream successes of [picked], which [agree]: those of
  /// the first, or, when `sse.data` or `sse.events` change the ones written
  /// in the operation, of the first of those; named after [prefix].
  EventStreamIr events(
    SpecOperation entry,
    List<PickedResponse> picked,
    String prefix,
  ) {
    final sse = _sse(entry.operation);
    final streams = _streamsOf(picked);
    final written = [
      for (final stream in streams)
        if (_written.isWritten(entry, stream.$2)) stream,
    ];
    final first = WrittenStreams.writes(sse) && written.isNotEmpty
        ? written.first
        : streams.firstOrNull;
    final shape = first == null
        ? null
        : _data.of(
            first.$3,
            first.$2,
            prefix,
            sse: _written.isWritten(entry, first.$2) ? sse : null,
          );
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

  /// How the stream of [entry] reconnects: a GET when the call asks, or
  /// unless it says no with `sse.reconnect` in the config; any other method
  /// never, reported (TOA665) only when the config asks for reconnection,
  /// since it does not apply there. The `sse.reconnect` override of the
  /// operation ([enabled], when it has one) wins over both.
  StreamReconnection _reconnection(SpecOperation entry, bool? enabled) {
    if (enabled != null) return enabled ? .on : .off;
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
