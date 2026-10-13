import '../model/media_type_name.dart';
import 'event_streams.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'names.dart';
import 'operation_checks.dart';
import 'request_body_builder.dart';
import 'response_builder.dart';
import 'schema_mapper.dart';
import 'security_builder.dart';
import 'spec_operation.dart';

/// Builds the methods of one operation: the method that returns its body
/// and, when it offers an event stream, the one that returns the events
/// (decision 5 of M10), with their responses, body, errors and security.
final class MethodBuilder {
  /// Creates a builder that maps types with [mapper].
  MethodBuilder(IrContext context, SchemaMapper mapper)
    : _checks = OperationChecks(context),
      _security = SecurityBuilder(context),
      _bodies = RequestBodyBuilder(context, mapper),
      _responses = ResponseBuilder(context, mapper),
      _streams = EventStreams(context, mapper);

  static const _names = DartNames();

  final OperationChecks _checks;
  final SecurityBuilder _security;
  final RequestBodyBuilder _bodies;
  final ResponseBuilder _responses;
  final EventStreams _streams;

  /// The methods of [entry] with [parameters]: the one named [name], and
  /// for an operation that returns a body or an event stream also one that
  /// returns the events, named in the group's [methods] (TOA663). Empty when
  /// its event streams cannot be expressed (TOA654).
  List<OperationIr> of(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters,
    NameScope methods,
  ) {
    final shape = _streams.shapeOf(entry.operation);
    final streamPicked = switch (shape) {
      .only || .both => _responses.pick(entry.operation, events: true),
      .none || .mixed || .excluded => const <PickedResponse>[],
    };
    final hasStream =
        streamPicked.isNotEmpty && _streams.agree(entry, streamPicked, shape);
    final main = switch (shape) {
      .none => _operation(
        entry,
        _Method(name, parameters, _responses.pick(entry.operation)),
      ),
      .both => _bodyOperation(entry, name, parameters, hasStream: hasStream),
      .only || .mixed || .excluded => null,
    };
    final stream = !hasStream
        ? null
        : _streamOperation(
            entry,
            name,
            parameters,
            streamPicked,
            methods: shape == .both ? methods : null,
          );
    return [?main, ?stream];
  }

  /// The method of [entry] that returns its body, next to the one that
  /// returns its events when [hasStream]: it asks for the body's media
  /// types with `Accept`.
  OperationIr _bodyOperation(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters, {
    required bool hasStream,
  }) {
    final picked = _responses.pick(entry.operation, hasStreamMethod: true);
    return _operation(
      entry,
      _Method(
        name,
        parameters,
        picked,
        accept: hasStream ? _accept(picked) : null,
      ),
    );
  }

  /// The `Accept` of a method that returns the bodies of [picked]: the media
  /// types of its 2xx successes with a body, each once, in order.
  static String? _accept(List<PickedResponse> picked) {
    final types = {
      for (final (status, _, (contentType, _)) in picked)
        if (status.startsWith('2') && contentType != null)
          MediaTypeName(contentType).base,
    };
    return types.isEmpty ? null : types.join(', ');
  }

  /// The method of [entry] that returns its events, from the [picked]
  /// responses that agree. With the group's [methods] it is a second method,
  /// named after [name] in them (TOA663).
  OperationIr _streamOperation(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters,
    List<PickedResponse> picked, {
    NameScope? methods,
  }) {
    final named = methods == null
        ? name
        : _streams.methodName(entry, name, methods);
    final events = _streams.events(
      entry,
      picked,
      _names.pascal(named) ?? named,
    );
    return _operation(
      entry,
      _Method(named, parameters, picked, events: events),
    );
  }

  OperationIr _operation(SpecOperation entry, _Method method) {
    final _Method(:name, :parameters, :picked, :events, :accept) = method;
    final operation = entry.operation;
    final prefix = _names.pascal(name) ?? name;
    final responses = _responses.of(picked, prefix);
    _checks.successes(operation);
    _checks.servers(entry);
    _checks.callbacks(operation);
    return OperationIr(
      location: operation.location,
      name: name,
      method: entry.method.toUpperCase(),
      path: entry.path,
      operationId: operation.operationId,
      tags: operation.tags,
      summary: operation.summary,
      description: operation.description,
      deprecated: operation.deprecated,
      parameters: parameters,
      body: _bodies.of(operation, entry.method, prefix),
      responses: responses,
      errors: _responses.errors(responses),
      security: _security.of(operation),
      events: events,
      accept: accept,
    );
  }
}

/// What sets one method of an operation apart from the operation's other
/// method: its [name], the [parameters] and the [picked] responses it uses,
/// the [events] it returns and the `Accept` it sends.
final class _Method {
  const _Method(
    this.name,
    this.parameters,
    this.picked, {
    this.events,
    this.accept,
  });

  final String name;
  final List<ParameterIr> parameters;
  final List<PickedResponse> picked;
  final EventStreamIr? events;
  final String? accept;
}
