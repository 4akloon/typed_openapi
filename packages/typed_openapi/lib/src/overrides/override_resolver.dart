import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'override_set.dart';

/// An override entry and the node of the spec model it names.
sealed class OverrideTarget {
  /// Creates a target.
  const OverrideTarget();

  /// The entry of the overrides file.
  OverrideEntry get entry;

  /// The node the entry changes.
  SpecNode get node;
}

/// An operation an [OperationOverride] names.
final class OperationTarget extends OverrideTarget {
  /// Creates a target.
  const OperationTarget(this.entry, this.node);

  @override
  final OperationOverride entry;

  @override
  final Operation node;
}

/// A parameter of an operation; a shared parameter (path-level or `$ref`)
/// is the node where it is defined.
final class ParameterTarget extends OverrideTarget {
  /// Creates a target.
  const ParameterTarget(this.entry, this.node);

  @override
  final ParameterOverride entry;

  @override
  final Parameter node;
}

/// A request body or a response, with the media types of its `content`.
final class ContentTarget extends OverrideTarget {
  /// Creates a target.
  const ContentTarget(this.entry, this.node);

  /// A [BodyOverride] or a [ResponseOverride].
  @override
  final OverrideEntry entry;

  /// A [RequestBody] or a [Response].
  @override
  final SpecNode node;
}

/// A schema in `components.schemas`: the schema its `$ref` chain ends at.
final class SchemaTarget extends OverrideTarget {
  /// Creates a target.
  const SchemaTarget(this.entry, this.node);

  @override
  final SchemaOverride entry;

  @override
  final SchemaObject node;
}

/// A property of a schema: the property schema as written, not where its
/// `$ref` points, so that only this property changes.
final class PropertyTarget extends OverrideTarget {
  /// Creates a target.
  const PropertyTarget(this.entry, this.owner, this.node);

  @override
  final PropertyOverride entry;

  /// The object schema that has the property.
  final SchemaObject owner;

  @override
  final Schema node;
}

/// Finds the node every override of an [OverrideSet] names.
///
/// An override whose node is missing is `override-target-not-found`; one
/// whose address names several nodes is `override-target-ambiguous`; two
/// overrides that name the same node (`getPet` and `GET /pets/{id}`, or `id`
/// and `path:id`) are `override-conflict`. None of them is a target; the
/// overrides inside such an operation or schema are not resolved.
///
/// A parameter, request body or response override with spec fields whose
/// node lies outside its operation (a path-level parameter, a `$ref`'d
/// component, a node in another file) is `override-shared-target`: the
/// change applies to every operation that uses the node.
final class OverrideResolver {
  /// Creates a resolver of [_overrides] that reports to [_diagnostics].
  const OverrideResolver(this._diagnostics, this._overrides);

  final DiagnosticBag _diagnostics;
  final OverrideSet _overrides;

  /// The targets in [model], read from [documents], in file order:
  /// operations with their parameters, request bodies and responses, then
  /// schemas with their properties.
  List<OverrideTarget> resolve(SpecModel model, SpecDocuments documents) {
    final operations = _OperationIndex(model);
    final targets = <OverrideTarget>[];
    final found = <(OperationTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.operations) {
      final operation = _operation(entry, operations);
      if (operation == null) continue;
      final target = OperationTarget(entry, operation.$1);
      found.add((target, _inside(entry, operation, model)));
    }
    for (final (target, inner) in _unique(found)) {
      final unique = _uniqueTargets(inner);
      targets
        ..add(target)
        ..addAll(unique);
      for (final t in unique) {
        _shared(t, target.node, model, documents);
      }
    }
    final schemas = <(SchemaTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.schemas) {
      final schema = _schema(entry, model);
      if (schema == null) continue;
      schemas.add((
        SchemaTarget(entry, schema),
        [
          for (final property in entry.properties)
            ?_property(property, entry, schema),
        ],
      ));
    }
    for (final (target, inner) in _unique(schemas)) {
      targets
        ..add(target)
        ..addAll(_uniqueTargets(inner));
    }
    return targets;
  }

  /// Reports [target] when it changes the spec at a node outside
  /// [operation].
  void _shared(
    OverrideTarget target,
    Operation operation,
    SpecModel model,
    SpecDocuments documents,
  ) {
    if (target.entry.spec.isEmpty) return;
    final at = target.node.location;
    final inside =
        at.document == operation.location.document &&
        at.pointer.value.startsWith('${operation.pointer.value}/');
    if (inside) return;
    final where = at.document == model.document.location.document
        ? at.pointer.value
        : '${documents.displayPath(at.document)}${at.pointer.value}';
    _report(
      .overrideSharedTarget,
      target.entry,
      'This override changes the shared node at $where; the change applies '
      'to every operation that uses it.',
    );
  }

  /// [found] without the targets whose node another one names too; those
  /// are reported, each naming the others.
  List<(T, List<OverrideTarget>)> _unique<T extends OverrideTarget>(
    List<(T, List<OverrideTarget>)> found,
  ) {
    final byNode = <SpecLocation, List<T>>{};
    for (final (target, _) in found) {
      (byNode[target.node.location] ??= []).add(target);
    }
    final unique = <(T, List<OverrideTarget>)>[];
    for (final (target, inner) in found) {
      final same = byNode[target.node.location]!;
      if (same.length == 1) {
        unique.add((target, inner));
      } else {
        _conflict(target, same);
      }
    }
    return unique;
  }

  /// [targets] without the ones whose node another one names too.
  List<OverrideTarget> _uniqueTargets(List<OverrideTarget> targets) => [
    for (final (target, _) in _unique([
      for (final target in targets) (target, const <OverrideTarget>[]),
    ]))
      target,
  ];

  /// Reports that [target] and the rest of [all] name the same node.
  void _conflict(OverrideTarget target, List<OverrideTarget> all) {
    final others = [
      for (final other in all)
        if (other != target) other.entry.pointer.value,
    ];
    _report(
      .overrideConflict,
      target.entry,
      'This override and the one at ${others.join(', ')} name the same '
      'node (${target.node.location.pointer.value}); neither is applied.',
      fix: 'Merge them into one override.',
    );
  }

  (Operation, PathItem?)? _operation(
    OperationOverride entry,
    _OperationIndex index,
  ) {
    if (entry.operationId case final id?) {
      final matches = index.byId[id] ?? const [];
      if (matches.length > 1) {
        final addresses = [
          for (final (_, method, path) in matches)
            '${method.toUpperCase()} $path',
        ];
        _report(
          .overrideTargetAmbiguous,
          entry,
          'operationId "$id" names ${matches.length} operations; this '
          'override is not applied.',
          fix:
              'Address the operation as METHOD /path: ${addresses.join(', ')}.',
        );
        return null;
      }
      if (matches.isEmpty) {
        _notFound(entry, 'No operation has operationId "$id".');
        return null;
      }
      final (operation, _, path) = matches.single;
      return (operation, index.items[path]);
    }
    final method = entry.method!;
    final path = entry.path!;
    final item = index.items[path];
    final operation = item?.operations[method];
    if (operation == null) {
      _notFound(
        entry,
        item == null
            ? 'The path $path is not in "paths".'
            : 'The path $path has no ${method.toUpperCase()} operation.',
      );
      return null;
    }
    return (operation, item);
  }

  /// The targets inside an operation override: parameters, request body,
  /// responses.
  List<OverrideTarget> _inside(
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
    _notFound(entry, missing);
    return null;
  }

  ParameterTarget? _parameter(
    ParameterOverride entry,
    OperationOverride parent,
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
    final matches = [
      for (final p in [...own, ...shared])
        if (p.name == entry.parameterName &&
            (entry.placement == null || p.placement == entry.placement))
          p,
    ];
    if (matches.isEmpty) {
      final where = entry.placement == null
          ? ''
          : ' in ${entry.placement!.name}';
      _notFound(
        entry,
        'Operation ${parent.key} has no parameter '
        '"${entry.parameterName}"$where.',
      );
      return null;
    }
    if (matches.length > 1) {
      final keys = {
        for (final p in matches)
          '${p.placement?.name ?? '?'}:${entry.parameterName}',
      }.toList()..sort();
      _report(
        .overrideTargetAmbiguous,
        entry,
        'Operation ${parent.key} has ${matches.length} parameters named '
        '"${entry.parameterName}"; this override is not applied.',
        fix: 'Write the key as in:name: ${keys.join(', ')}.',
      );
      return null;
    }
    return ParameterTarget(entry, matches.single);
  }

  SchemaObject? _schema(SchemaOverride entry, SpecModel model) {
    final written = model.document.components?.schemas[entry.key];
    if (written == null) {
      _notFound(entry, 'No schema "${entry.key}" in components.schemas.');
      return null;
    }
    final schema = model.resolveSchema(written);
    if (schema is SchemaObject) return schema;
    _notFound(
      entry,
      schema == null
          ? 'The \$ref of schema "${entry.key}" cannot be followed.'
          : 'Schema "${entry.key}" is the boolean schema ${schema.location}; '
                'it has no fields to change.',
    );
    return null;
  }

  PropertyTarget? _property(
    PropertyOverride entry,
    SchemaOverride parent,
    SchemaObject owner,
  ) {
    final property = owner.properties[entry.key];
    if (property != null) return PropertyTarget(entry, owner, property);
    _notFound(
      entry,
      'Schema "${parent.key}" has no property "${entry.key}" in its own '
      '"properties".',
    );
    return null;
  }

  void _notFound(OverrideEntry entry, String message) => _report(
    .overrideTargetNotFound,
    entry,
    '$message The override is not applied.',
    fix: 'Remove the override, or fix its address.',
  );

  void _report(
    DiagnosticCode code,
    OverrideEntry entry,
    String message, {
    String? fix,
  }) {
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: _overrides.file,
      pointer: entry.pointer,
      span: _overrides.spanOf(entry.pointer),
      fix: fix,
    );
  }
}

/// The operations of `paths`, by `operationId` and by path template.
final class _OperationIndex {
  _OperationIndex(SpecModel model) {
    final seen = <SpecLocation>{};
    for (final MapEntry(key: path, :value) in model.document.paths.entries) {
      final item = model.resolve(value);
      if (item == null) continue;
      items[path] = item;
      for (final MapEntry(key: method, value: operation)
          in <MapEntry<String, Operation>>[
            ...item.operations.entries,
            ...item.additionalOperations.entries,
          ]) {
        final id = operation.operationId;
        if (id == null || !seen.add(operation.location)) continue;
        (byId[id] ??= []).add((operation, method, path));
      }
    }
  }

  /// Path items by template.
  final Map<String, PathItem> items = {};

  /// Operations with their method and path, by `operationId`.
  final Map<String, List<(Operation, String, String)>> byId = {};
}
