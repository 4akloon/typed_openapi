import '../model/operation.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';
import 'operation_index.dart';
import 'override_set.dart';
import 'override_target.dart';
import 'override_target_reporter.dart';

/// Finds the operation an [OperationOverride] names, and the parameters,
/// request body and responses inside it its entries name.
final class OperationTargetFinder {
  /// Creates a finder that reports to [_reporter].
  const OperationTargetFinder(this._reporter);

  final OverrideTargetReporter _reporter;

  /// The operation [entry] names, with its path item; null, after a report,
  /// when there is none or several.
  (Operation, PathItem?)? operation(
    OperationOverride entry,
    OperationIndex index,
  ) {
    if (entry.operationId case final id?) return _byId(entry, id, index);
    final method = entry.method!;
    final path = entry.path!;
    final item = index.items[path];
    final operation = item?.operations[method];
    if (operation == null) {
      _reporter.notFound(
        entry,
        item == null
            ? 'The path $path is not in "paths".'
            : 'The path $path has no ${method.toUpperCase()} operation.',
      );
      return null;
    }
    return (operation, item);
  }

  /// The operation with the `operationId` [id], or null after a report when
  /// there is none or several.
  (Operation, PathItem?)? _byId(
    OperationOverride entry,
    String id,
    OperationIndex index,
  ) {
    final matches = index.byId[id] ?? const [];
    if (matches.length > 1) {
      final addresses = [
        for (final (_, method, path) in matches)
          '${method.toUpperCase()} $path',
      ];
      _reporter.report(
        .overrideTargetAmbiguous,
        entry,
        'operationId "$id" names ${matches.length} operations; this '
        'override is not applied.',
        fix: 'Address the operation as METHOD /path: ${addresses.join(', ')}.',
      );
      return null;
    }
    if (matches.isEmpty) {
      _reporter.notFound(entry, 'No operation has operationId "$id".');
      return null;
    }
    final (operation, _, path) = matches.single;
    return (operation, index.items[path]);
  }

  /// The targets inside an operation override: parameters, request body,
  /// responses.
  List<OverrideTarget> inside(
    OperationOverride entry,
    (Operation, PathItem?) found,
    SpecModel model,
  ) {
    final (operation, item) = found;
    return [
      for (final parameter in entry.parameters)
        ?_parameter(parameter, entry, operation, item, model),
      if (entry.requestBody case final body?)
        ?_content(
          body,
          operation.requestBody,
          model,
          'Operation ${entry.key} has no request body.',
        ),
      for (final response in entry.responses)
        ?_content(
          response,
          operation.responses[response.key],
          model,
          'Operation ${entry.key} has no response "${response.key}".',
        ),
    ];
  }

  /// The request body or response [value] for [entry], or null after
  /// reporting [missing].
  ContentTarget? _content(
    OverrideEntry entry,
    RefOr<SpecNode>? value,
    SpecModel model,
    String missing,
  ) {
    final node = value == null ? null : model.resolve(value);
    if (node != null) return ContentTarget(entry, node);
    _reporter.notFound(entry, missing);
    return null;
  }

  ParameterTarget? _parameter(
    ParameterOverride entry,
    OperationOverride parent,
    Operation operation,
    PathItem? item,
    SpecModel model,
  ) {
    final matches = [
      for (final p in _parametersOf(operation, item, model))
        if (p.name == entry.parameterName &&
            (entry.placement == null || p.placement == entry.placement))
          p,
    ];
    if (matches.isEmpty) {
      final where = entry.placement == null
          ? ''
          : ' in ${entry.placement!.name}';
      _reporter.notFound(
        entry,
        'Operation ${parent.key} has no parameter '
        '"${entry.parameterName}"$where.',
      );
      return null;
    }
    if (matches.length > 1) {
      _ambiguousParameter(entry, parent, matches);
      return null;
    }
    return ParameterTarget(entry, matches.single);
  }

  /// The parameters of [operation], then those of its path item that the
  /// operation does not define again.
  List<Parameter> _parametersOf(
    Operation operation,
    PathItem? item,
    SpecModel model,
  ) {
    final own = [
      for (final p in operation.parameters) ?model.resolve(p),
    ];
    final shared = [
      for (final p in item?.parameters ?? const <RefOr<Parameter>>[])
        if (model.resolve(p) case final resolved?)
          if (!own.any(
            (o) => o.name == resolved.name && o.placement == resolved.placement,
          ))
            resolved,
    ];
    return [...own, ...shared];
  }

  void _ambiguousParameter(
    ParameterOverride entry,
    OperationOverride parent,
    List<Parameter> matches,
  ) {
    final keys = {
      for (final p in matches)
        '${p.placement?.name ?? '?'}:${entry.parameterName}',
    }.toList()..sort();
    _reporter.report(
      .overrideTargetAmbiguous,
      entry,
      'Operation ${parent.key} has ${matches.length} parameters named '
      '"${entry.parameterName}"; this override is not applied.',
      fix: 'Write the key as in:name: ${keys.join(', ')}.',
    );
  }
}
