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
  /// for an operation that returns JSON or an event stream also one that
  /// returns the events, named in the group's [methods] (TOA663). Empty when
  /// its event streams cannot be expressed (TOA654).
  List<OperationIr> of(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters,
    NameScope methods,
  ) {
    final shape = _streams.shapeOf(entry.operation);
    final main = switch (shape) {
      .none || .both => _operation(
        entry,
        name,
        parameters,
        _responses.pick(entry.operation, hasStreamMethod: shape == .both),
      ),
      .only || .mixed => null,
    };
    final stream = switch (shape) {
      .only => _streamOperation(entry, name, parameters),
      .both => _streamOperation(
        entry,
        _streams.methodName(entry, name, methods),
        parameters,
      ),
      .none || .mixed => null,
    };
    return [?main, ?stream];
  }

  /// The method of [entry] that returns its events, or null (TOA654).
  OperationIr? _streamOperation(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters,
  ) {
    final picked = _responses.pick(entry.operation, events: true);
    final events = _streams.events(
      entry,
      picked,
      _names.pascal(name) ?? name,
    );
    if (events == null) return null;
    return _operation(entry, name, parameters, picked, events: events);
  }

  OperationIr _operation(
    SpecOperation entry,
    String name,
    List<ParameterIr> parameters,
    List<PickedResponse> picked, {
    EventStreamIr? events,
  }) {
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
    );
  }
}
