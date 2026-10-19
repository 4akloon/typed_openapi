import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import '../normalize/normalizer.dart';
import 'api_names.dart';
import 'direction_index.dart';
import 'group_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'method_names.dart';
import 'name_lock.dart';
import 'names.dart';
import 'operation_builder.dart';
import 'operation_checks.dart';
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
  /// Creates a builder that reports to [_diagnostics] and keeps the names
  /// of [names], the client's API lock (M12).
  const IrBuilder(this._diagnostics, {NameLock names = NameLock.none})
    : _names = names;

  final DiagnosticBag _diagnostics;
  final NameLock _names;

  /// The IR of [spec] generated as [client] says.
  ClientIr build(NormalizedSpec spec, ClientConfig client) {
    final context = IrContext(_diagnostics, spec, client, names: _names);
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
    final groupNames = GroupNames(context);
    final groups = <String, List<SpecOperation>>{};
    final groupSites = <String, SpecOperation>{};
    final tagOfGroup = <String, String>{};
    final untagged = <SpecOperation>[];
    for (final entry in selected) {
      final choice = groupNames.choose(entry, tagOfGroup);
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
    for (final group in groups.keys.toList()..sort()) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.methodNames},
        reservedSuffix: '_',
      );
      final names = MethodNames(context).of(groups[group]!, scope);
      for (final entry in groups[group]!) {
        final methods = operations.build(entry, names[entry]!, scope);
        if (methods.isNotEmpty) (built[group] ??= []).addAll(methods);
      }
    }
    if (built.isEmpty) {
      _reportEmpty(
        context,
        refs: refs,
        filtered: all.length - selected.length,
        unbound: operations.unbound,
        streams: operations.streams,
      );
    }
    OperationChecks(context).webhooks();
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
    final groupIrs = {
      for (final group in built.keys.toList()..sort())
        group: GroupIr(
          groupNames.className(
            types,
            group,
            groupSites[group]!.operation.location,
            groupClasses,
          ),
          built[group]!,
        ),
    };
    // The types the emitters add for declarations are named after the
    // groups, so they never rename a group or a declaration; M9's are last.
    final declarations = mapper.declarations(types);
    return ApiNames(context, types).client(declarations, groupIrs);
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
    required int streams,
  }) {
    if (refs + filtered + unbound + streams == 0) return;
    final reasons = [
      if (filtered > 0)
        '$filtered ${filtered == 1 ? 'is' : 'are'} left out by the include '
            'and exclude filters or by overrides',
      if (refs > 0)
        '$refs ${refs == 1 ? 'is' : 'are'} written as a \$ref (TOA107)',
      if (unbound > 0)
        '$unbound ${unbound == 1 ? 'has' : 'have'} a path variable without a '
            'parameter (TOA556)',
      if (streams > 0)
        '$streams ${streams == 1 ? 'has' : 'have'} event streams the client '
            'cannot express (TOA654)',
    ];
    final fixes = [
      if (filtered > 0) 'Check include, exclude and the overrides.',
      if (refs > 0) 'Write the operations inline at the source.',
      if (unbound > 0) 'Declare the path parameters at the source.',
      if (streams > 0) 'Offer text/event-stream on every success.',
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
}
