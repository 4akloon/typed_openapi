import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import '../normalize/normalizer.dart';
import 'direction_index.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'operation_builder.dart';
import 'operation_selector.dart';
import 'schema_mapper.dart';

/// Builds the semantic IR of a client from its normalized spec (M6).
///
/// Operations are grouped (R5.3) and named (R5.1); their parameters,
/// bodies and responses are mapped to types, which creates the
/// declarations they reach (R4.2); then declarations and groups are named
/// in one library scope (R5.2). Problems go to the [DiagnosticBag] given to
/// the constructor; nothing is thrown for any spec.
final class IrBuilder {
  /// Creates a builder that reports to [_diagnostics].
  const IrBuilder(this._diagnostics);

  static const _names = DartNames();

  /// The `operationId` prefix the `nestjs` preset removes:
  /// `UserController_get` → `get`.
  static final nestjsPrefix = RegExp('^[A-Za-z0-9]*Controller_');

  static final _variable = RegExp(r'\{([^}]*)\}');

  final DiagnosticBag _diagnostics;

  /// The IR of [spec] generated as [client] says.
  ClientIr build(NormalizedSpec spec, ClientConfig client) {
    final context = IrContext(_diagnostics, spec, client);
    final all = _operations(context);
    final selected = OperationSelector(context).select(all);
    final directions = DirectionIndex(
      spec.model,
      isExcluded: context.isPropertyExcluded,
    );
    for (final entry in selected) {
      directions.addOperation(entry.operation, entry.item, entry.method);
    }
    if (client.generation.defaultErrorSchema case final key?) {
      directions.add(
        spec.model.document.components?.schemas[key],
        .response,
      );
    }
    final mapper = SchemaMapper(context, directions);
    final operations = OperationBuilder(context, mapper);
    final groups = <String, List<SpecOperation>>{};
    final groupSites = <String, SpecLocation>{};
    final tagOfGroup = <String, String>{};
    // A spec without any tag gets one TOA554, not one per operation.
    final untagged =
        client.generation.groupBy == .tag &&
        all.every((e) => e.operation.tags.isEmpty);
    if (untagged && selected.isNotEmpty) {
      context.report(
        .operationUntagged,
        'No operation of the spec has a tag, so all operations are in '
        '${client.generation.defaultGroup}.',
        SpecLocation(
          spec.model.document.location.document,
          JsonPointer.root.child('paths'),
        ),
        fix:
            'Tag the operations at the source, or set group_by to path or '
            'single in the config.',
      );
    }
    for (final entry in selected) {
      final group = _group(
        context,
        entry,
        tagOfGroup,
        reportUntagged: !untagged,
      );
      (groups[group] ??= []).add(entry);
      final site = groupSites[group];
      if (site == null || entry.operation.location.compareTo(site) < 0) {
        groupSites[group] = entry.operation.location;
      }
    }
    final built = <String, List<OperationIr>>{};
    for (final group in groups.keys.toList()..sort()) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
        reservedSuffix: '_',
      );
      for (final entry in groups[group]!) {
        final name = _methodName(context, entry, scope);
        final operation = operations.build(entry, name);
        if (operation != null) (built[group] ??= []).add(operation);
      }
    }
    final types = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.builtInIdentifiers,
        ...DartNames.takenTypeNames,
      },
      reservedSuffix: 'Model',
    );
    final declarations = mapper.declarations(types);
    return ClientIr(
      declarations: declarations,
      groups: [
        for (final group in built.keys.toList()..sort())
          GroupIr(
            _groupName(context, types, group, groupSites[group]!),
            built[group]!,
          ),
      ],
    );
  }

  /// The operations of `paths`, by location, with `additionalOperations`
  /// (OpenAPI 3.2). A path item shared through `$ref` gives its operations
  /// to every path that uses it.
  static List<SpecOperation> _operations(IrContext context) {
    final result = <SpecOperation>[];
    for (final MapEntry(key: path, :value)
        in context.model.document.paths.entries) {
      final item = context.model.resolve(value);
      if (item == null) continue;
      for (final MapEntry(key: method, value: operation)
          in <MapEntry<String, Operation>>[
            ...item.operations.entries,
            ...item.additionalOperations.entries,
          ]) {
        // An operation written as a `$ref` is empty; TOA107 reports it.
        if (operation.unknownKeys.containsKey(r'$ref')) continue;
        result.add(SpecOperation(operation, method, path, item));
      }
    }
    return result..sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return a.method.compareTo(b.method);
    });
  }

  /// The group of [entry] before the class name template: an override's
  /// `group`, else by `group_by`. [reportUntagged] reports an operation
  /// without a tag.
  static String _group(
    IrContext context,
    SpecOperation entry,
    Map<String, String> tagOfGroup, {
    required bool reportUntagged,
  }) {
    final operation = entry.operation;
    final override = context.overrides.operationAt(operation.location)?.group;
    if (override != null) return _names.pascal(override) ?? override;
    final config = context.config;
    switch (config.groupBy) {
      case .single:
        return '';
      case .path:
        final segment = entry.path
            .split('/')
            .firstWhere(
              (s) => s.isNotEmpty && !s.startsWith('{'),
              orElse: () => '',
            );
        return _names.pascal(segment) ?? '';
      case .tag:
        if (operation.tags.isEmpty) {
          if (!reportUntagged) return '';
          context.report(
            .operationUntagged,
            'This operation has no tag, so it is in '
            '${config.defaultGroup}.',
            operation.location,
            fix: 'Tag the operation at the source, or name its group.',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': 'Default'},
            ),
          );
          return '';
        }
        final tag = operation.tags.first;
        if (operation.tags.length > 1) {
          context.report(
            .operationMultipleTags,
            'This operation has tags ${operation.tags.join(', ')}; it is '
            'generated once, in the group of "$tag".',
            operation.location.child('tags'),
            fix: 'Keep one tag at the source, or name the group.',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': tag},
            ),
          );
        }
        final group = _names.pascal(tag);
        if (group == null) {
          context.report(
            .nameUnrepresentable,
            'Tag "$tag" has no ASCII letter or digit, so the operation is in '
            '${config.defaultGroup}.',
            operation.location.child('tags').child(0),
            fix: 'Name the group of the operation.',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': 'MyGroup'},
            ),
          );
          return '';
        }
        final earlier = tagOfGroup[group];
        if (earlier == null) {
          tagOfGroup[group] = tag;
        } else if (earlier != tag) {
          context.report(
            .tagsMerged,
            'Tags "$earlier" and "$tag" give the same group name, so their '
            'operations are in one class.',
            operation.location.child('tags').child(0),
            fix: 'Write the tag the same way everywhere at the source.',
          );
        }
        return group;
    }
  }

  /// The class name of [group] in the library scope [types].
  static String _groupName(
    IrContext context,
    NameScope types,
    String group,
    SpecLocation site,
  ) {
    final config = context.config;
    final candidate = group.isEmpty
        ? config.defaultGroup
        : config.groupTemplate.replaceAll('{Tag}', group);
    final (name, change) = types.claim(candidate);
    if (change != null) {
      context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Group class "$candidate" would be a name Dart already has; it '
                  'is named "$name".'
            : 'A type is named "$candidate" already; the group class is '
                  'named "$name".',
        site,
        fix: 'Change naming.group in the config, or rename the schema.',
      );
    }
    return name;
  }

  /// The words of a method name made from [method] and [path]: the method,
  /// the words of every path segment without its variables, then, when the
  /// path has variables, `By` and the variables in path order joined by
  /// `And`: `GET /users/{userId}/posts/{postId}` gives
  /// `getUsersPostsByUserIdAndPostId`, `GET /pets/{id}` gives
  /// `getPetsById`.
  static String _pathName(String method, String path) {
    final variables = <String>[];
    final literal = path.replaceAllMapped(_variable, (match) {
      variables.add(match[1]!);
      return ' ';
    });
    if (variables.isEmpty) return '$method $literal';
    return '$method $literal By ${variables.join(' And ')}';
  }

  /// The method name of [entry] in its group's [scope] (R5.1): an
  /// override's `name`, else `operationId` without the configured prefix,
  /// else [_pathName], in lowerCamelCase.
  static String _methodName(
    IrContext context,
    SpecOperation entry,
    NameScope scope,
  ) {
    final operation = entry.operation;
    final override = context.overrides.operationAt(operation.location)?.name;
    final prefix =
        context.config.operationPrefix ??
        (context.client.preset == .nestjs ? nestjsPrefix : null);
    final id = operation.operationId;
    final source = id == null
        ? _pathName(entry.method, entry.path)
        : prefix == null
        ? id
        : id.replaceFirst(prefix, '');
    final candidate = override ?? _names.camel(source);
    final (name, change) = scope.claim(candidate ?? 'operation');
    if (candidate == null || change != null) {
      context.report(
        candidate == null
            ? .nameUnrepresentable
            : change == .reserved
            ? .nameReserved
            : .nameCollision,
        candidate == null
            ? 'operationId "$id" has no ASCII letter or digit; the method is '
                  'named "$name".'
            : change == .reserved
            ? 'Method "$candidate" would be a name Dart already has; it is '
                  'named "$name".'
            : 'Another method of the group is named "$candidate"; this one '
                  'is named "$name".',
        operation.location,
        fix: 'Name the method explicitly to keep the name stable.',
        override: context.overrideAt(
          ['operations', entry.overrideKey],
          {'name': name},
        ),
      );
    }
    return name;
  }
}
