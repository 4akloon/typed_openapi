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

  final DiagnosticBag _diagnostics;

  /// The IR of [spec] generated as [client] says.
  ClientIr build(NormalizedSpec spec, ClientConfig client) {
    final context = IrContext(_diagnostics, spec, client);
    // Reads the setting once, so a key that is not in the spec is reported
    // even when no operation is generated.
    final defaultError = context.defaultErrorSchema;
    final (all, refs) = _operations(context);
    final selected = OperationSelector(context).select(all);
    final directions = DirectionIndex(
      spec.model,
      isExcluded: context.isPropertyExcluded,
    );
    for (final entry in selected) {
      directions.addOperation(entry.operation, entry.item, entry.method);
    }
    if (defaultError != null) {
      directions.add(
        spec.model.document.components?.schemas[defaultError],
        .response,
      );
    }
    final mapper = SchemaMapper(context, directions);
    final operations = OperationBuilder(context, mapper);
    final groups = <String, List<SpecOperation>>{};
    final groupSites = <String, SpecOperation>{};
    final tagOfGroup = <String, String>{};
    final untagged = <SpecOperation>[];
    for (final entry in selected) {
      final choice = _group(context, entry, tagOfGroup);
      if (choice.untagged) untagged.add(entry);
      final group = choice.name;
      (groups[group] ??= []).add(entry);
      final site = groupSites[group];
      if (site == null ||
          entry.operation.location.compareTo(site.operation.location) < 0) {
        groupSites[group] = entry;
      }
    }
    _reportUntagged(context, selected, untagged);
    final built = <String, List<OperationIr>>{};
    var unbound = 0;
    for (final group in groups.keys.toList()..sort()) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
        reservedSuffix: '_',
      );
      final names = _methodNames(context, groups[group]!, scope);
      for (final entry in groups[group]!) {
        final operation = operations.build(entry, names[entry]!);
        if (operation == null) {
          unbound++;
        } else {
          (built[group] ??= []).add(operation);
        }
      }
    }
    if (built.isEmpty) {
      _reportEmpty(
        context,
        refs: refs,
        filtered: all.length - selected.length,
        unbound: unbound,
      );
    }
    final types = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.builtInIdentifiers,
        ...DartNames.takenTypeNames,
      },
      reservedSuffix: 'Model',
    );
    // The user's types are in the generated library's scope too: a
    // declaration named like one gets a suffix (TOA551).
    for (final name in context.customTypeNames) {
      types.reserve(name);
    }
    mapper.nameDeclarations(types);
    final groupClasses = <String>{};
    final groupIrs = [
      for (final group in built.keys.toList()..sort())
        GroupIr(
          _groupName(
            context,
            types,
            group,
            groupSites[group]!.operation.location,
            groupClasses,
          ),
          built[group]!,
        ),
    ];
    // The types the emitters add for declarations are named after the
    // groups, so they never rename a group or a declaration.
    return ClientIr(declarations: mapper.declarations(types), groups: groupIrs);
  }

  /// Reports operations without a group: one TOA554 when no generated
  /// operation has a tag (they all go to the default group, but for those
  /// an override names), else one for each.
  static void _reportUntagged(
    IrContext context,
    List<SpecOperation> selected,
    List<SpecOperation> untagged,
  ) {
    if (untagged.isEmpty) return;
    final defaultGroup = context.config.defaultGroup;
    if (selected.every((e) => e.operation.tags.isEmpty)) {
      final all = untagged.length == selected.length;
      context.report(
        .operationUntagged,
        all
            ? 'No operation of the spec has a tag, so all operations are in '
                  '$defaultGroup.'
            : 'No operation of the spec has a tag, so the operations without '
                  'a group override are in $defaultGroup.',
        SpecLocation(
          context.model.document.location.document,
          JsonPointer.root.child('paths'),
        ),
        fix:
            'Tag the operations at the source, or set group_by to path or '
            'single in the config.',
      );
      return;
    }
    for (final entry in untagged) {
      context.report(
        .operationUntagged,
        'This operation has no tag, so it is in $defaultGroup.',
        entry.operation.location,
        fix: 'Tag the operation at the source, or name its group.',
        override: context.overrideAt(
          ['operations', entry.overrideKey],
          {'group': 'Default'},
        ),
      );
    }
  }

  /// Reports TOA563 for a client without any operation, when the spec has
  /// some: [refs] written as `$ref`, [filtered] left out by the config or
  /// the overrides, [unbound] that cannot be generated (TOA556).
  static void _reportEmpty(
    IrContext context, {
    required int refs,
    required int filtered,
    required int unbound,
  }) {
    if (refs + filtered + unbound == 0) return;
    final reasons = [
      if (filtered > 0)
        '$filtered ${filtered == 1 ? 'is' : 'are'} left out by the include '
            'and exclude filters or by overrides',
      if (refs > 0)
        '$refs ${refs == 1 ? 'is' : 'are'} written as a \$ref (TOA107)',
      if (unbound > 0)
        '$unbound ${unbound == 1 ? 'has' : 'have'} a path variable without a '
            'parameter (TOA556)',
    ];
    final fixes = [
      if (filtered > 0) 'Check include, exclude and the overrides.',
      if (refs > 0) 'Write the operations inline at the source.',
      if (unbound > 0) 'Declare the path parameters at the source.',
    ];
    final config = context.config;
    final byFilter =
        filtered > 0 &&
        (!config.include.isEmpty || !config.exclude.isEmpty) &&
        config.client != null;
    final message =
        'No operation of this client is generated: ${reasons.join('; ')}.';
    if (byFilter) {
      context.diagnostics.report(
        .clientEmpty,
        message,
        file: config.file,
        pointer: config.client,
        span: config.clientSpan,
        fix: fixes.join(' '),
      );
      return;
    }
    context.report(
      .clientEmpty,
      message,
      SpecLocation(
        context.model.document.location.document,
        JsonPointer.root.child('paths'),
      ),
      fix: fixes.join(' '),
    );
  }

  /// The operations of `paths`, by location, with `additionalOperations`
  /// (OpenAPI 3.2), and how many operations are written as a `$ref` and so
  /// left out. A path item shared through `$ref` gives its operations to
  /// every path that uses it.
  static (List<SpecOperation>, int) _operations(IrContext context) {
    final result = <SpecOperation>[];
    var refs = 0;
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
        if (operation.unknownKeys.containsKey(r'$ref')) {
          refs++;
          continue;
        }
        result.add(SpecOperation(operation, method, path, item));
      }
    }
    result.sort((a, b) {
      final byPath = a.path.compareTo(b.path);
      if (byPath != 0) return byPath;
      return a.method.compareTo(b.method);
    });
    return (result, refs);
  }

  /// The group of [entry] before the class name template: an override's
  /// `group`, else by `group_by`.
  static _GroupChoice _group(
    IrContext context,
    SpecOperation entry,
    Map<String, String> tagOfGroup,
  ) {
    final operation = entry.operation;
    final override = context.overrides.operationAt(operation.location);
    if (override?.group case final written?) {
      // A group is a word list like a tag: a value that differs from its
      // UpperCamelCase form only by case or separators is that form.
      final words = _names.pascal(written);
      final String? name;
      if (_names.isValid(written, .type)) {
        name = written;
      } else if (words != null && !_names.dropsLetters(written)) {
        name = words;
      } else {
        name = context.checkedOverrideName(
          override!,
          'group',
          written,
          .type,
          what: 'group',
        );
      }
      if (name != null) return _GroupChoice(name);
    }
    final config = context.config;
    switch (config.groupBy) {
      case .single:
        return const _GroupChoice('');
      case .path:
        final segment = entry.path
            .split('/')
            .firstWhere(
              (s) => s.isNotEmpty && !s.startsWith('{'),
              orElse: () => '',
            );
        final group = _names.pascal(segment) ?? '';
        if (group.isNotEmpty && !tagOfGroup.containsKey(group)) {
          tagOfGroup[group] = segment;
          context.checkLossyName(
            segment,
            group,
            operation.location,
            what: 'Path segment',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': group},
            ),
          );
        }
        return _GroupChoice(group);
      case .tag:
        if (operation.tags.isEmpty) {
          return const _GroupChoice('', untagged: true);
        }
        final tag = operation.tags.first;
        final tagAt = operation.location.child('tags').child(0);
        if (operation.tags.length > 1) {
          context.report(
            .operationMultipleTags,
            'This operation has tags ${operation.tags.join(', ')}; it is '
            'generated once, in the group of "$tag".',
            operation.location.child('tags'),
            fix: 'Keep one tag at the source, or name the group.',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': _names.pascal(tag) ?? 'MyGroup'},
            ),
          );
        }
        final group = _names.pascal(tag);
        if (group == null) {
          context.report(
            .nameUnrepresentable,
            'Tag "$tag" has no ASCII letter or digit, so the operation is in '
            '${config.defaultGroup}.',
            tagAt,
            fix: 'Name the group of the operation.',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': 'MyGroup'},
            ),
          );
          return const _GroupChoice('');
        }
        final earlier = tagOfGroup[group];
        if (earlier == null) {
          tagOfGroup[group] = tag;
          context.checkLossyName(
            tag,
            group,
            tagAt,
            what: 'Tag',
            override: context.overrideAt(
              ['operations', entry.overrideKey],
              {'group': group},
            ),
          );
        } else if (earlier != tag) {
          context.report(
            .tagsMerged,
            'Tags "$earlier" and "$tag" give the same group name, so their '
            'operations are in one class.',
            tagAt,
            fix: 'Write the tag the same way everywhere at the source.',
          );
        }
        return _GroupChoice(group);
    }
  }

  /// The class name of [group] in the library scope [types]; [groupClasses]
  /// are the class names the groups got already.
  static String _groupName(
    IrContext context,
    NameScope types,
    String group,
    SpecLocation site,
    Set<String> groupClasses,
  ) {
    final config = context.config;
    final candidate = group.isEmpty
        ? config.defaultGroup
        : config.groupTemplate.replaceAll('{Tag}', group);
    final (name, change) = types.claim(candidate);
    groupClasses.add(name);
    if (change != null) {
      final ofGroup = change == .collision && groupClasses.contains(candidate);
      context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Group class "$candidate" would be a name Dart already has; it '
                  'is named "$name".'
            : ofGroup
            ? 'The group class "$candidate" is the class of another group '
                  'already; this group\'s class is named "$name".'
            : 'A type is named "$candidate" already; the group class is '
                  'named "$name".',
        site,
        fix: ofGroup
            ? 'Name the group with the group override of its operations, or '
                  'change naming.group or naming.default_group in the config.'
            : 'Change naming.group in the config, or rename the schema.',
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
    final literal = path.replaceAllMapped(OperationBuilder.pathVariable, (
      match,
    ) {
      variables.add(match[1]!);
      return ' ';
    });
    if (variables.isEmpty) return '$method $literal';
    return '$method $literal By ${variables.join(' And ')}';
  }

  /// The method names of the operations [entries] of one group, in
  /// [scope]. Names that overrides give are claimed first, so an automatic
  /// name that is the same gets the suffix, not the override's.
  static Map<SpecOperation, String> _methodNames(
    IrContext context,
    List<SpecOperation> entries,
    NameScope scope,
  ) {
    final overrides = <SpecOperation, String>{};
    for (final entry in entries) {
      final override = context.overrides.operationAt(entry.operation.location);
      final name = override?.name;
      if (override == null || name == null) continue;
      final checked = context.checkedOverrideName(
        override,
        'name',
        name,
        .member,
        what: 'method',
      );
      if (checked != null) overrides[entry] = checked;
    }
    final names = <SpecOperation, String>{};
    for (final entry in [
      for (final e in entries)
        if (overrides.containsKey(e)) e,
      for (final e in entries)
        if (!overrides.containsKey(e)) e,
    ]) {
      names[entry] = _methodName(context, entry, scope, overrides[entry]);
    }
    return names;
  }

  /// The method name of [entry] in its group's [scope] (R5.1): [override],
  /// else `operationId` without the configured prefix, else [_pathName], in
  /// lowerCamelCase.
  static String _methodName(
    IrContext context,
    SpecOperation entry,
    NameScope scope,
    String? override,
  ) {
    final operation = entry.operation;
    final prefix =
        context.config.operationPrefix ??
        (context.client.preset == .nestjs ? nestjsPrefix : null);
    final id = operation.operationId;
    final source = id == null
        ? _pathName(entry.method, entry.path)
        : prefix == null
        ? id
        : _withoutPrefix(id, prefix);
    final candidate = override ?? _names.camel(source);
    final (name, change) = scope.claim(candidate ?? 'operation');
    final at = ['operations', entry.overrideKey];
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
        override: context.overrideAt(at, {'name': name}),
      );
    }
    if (override == null && candidate != null) {
      context.checkLossyName(
        id == null ? entry.path : source,
        name,
        operation.location,
        what: id == null ? 'Path' : 'operationId',
        override: context.overrideAt(at, {'name': name}),
      );
    }
    return name;
  }

  /// [id] without the match of [prefix] when it starts at index 0 and is
  /// not empty; else [id] itself.
  static String _withoutPrefix(String id, RegExp prefix) {
    final match = prefix.matchAsPrefix(id);
    if (match == null || match.end == 0) return id;
    return id.substring(match.end);
  }
}

/// The group an operation is in before the class name template; [untagged]
/// when it has no group of its own (no tag), so it is in the default group.
final class _GroupChoice {
  const _GroupChoice(this.name, {this.untagged = false});

  final String name;
  final bool untagged;
}
