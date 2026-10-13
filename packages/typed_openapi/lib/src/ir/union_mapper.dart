import '../model/schema.dart';
import '../overrides/override_set.dart';
import 'discriminator_reader.dart';
import 'ir.dart';
import 'json_kinds.dart';
import 'mapping_tools.dart';
import 'names.dart';
import 'schema_shapes.dart';
import 'type_recursion.dart';
import 'union_notices.dart';
import 'union_state.dart';
import 'variant_collector.dart';
import 'variant_names.dart';

/// Turns a `oneOf`/`anyOf`, or a polymorphic base with its subtypes, into a
/// [UnionDecl]: how a value picks its variant, the variants and their
/// classes (R9).
final class UnionMapper {
  /// A union mapper that maps the branches of a union with [types].
  UnionMapper(this._tools, TypeRecursion types)
    : _kinds = _tools.kinds,
      _notices = _tools.unionNotices,
      _collector = VariantCollector(_tools, types),
      _discriminators = DiscriminatorReader(_tools),
      _variantNames = VariantNames(_tools.state);

  final MappingTools _tools;
  final JsonKinds _kinds;
  final UnionNotices _notices;
  final VariantCollector _collector;
  final DiscriminatorReader _discriminators;
  final VariantNames _variantNames;

  /// Whether the union [schema] of [branches] is generated as `JsonValue`
  /// (R9.2): it has no discriminator, no variant has a JSON type of its own
  /// ([JsonKinds.conflicts]), and its override `union` (or else the
  /// config's) is `raw`. Reported, with the override that changes it
  /// (TOA453).
  bool isRawUnion(SchemaObject schema, List<Schema> branches) {
    if (schema.discriminator?.propertyName != null) return false;
    if (_unionMode(schema) == .structural) return false;
    final (conflicts, distinct) = _kinds.conflicts(branches);
    if (conflicts.length < distinct) return false;
    final context = _tools.context;
    final kind = schema.oneOf.isNotEmpty ? 'oneOf' : 'anyOf';
    // A variant without one JSON type conflicts with every other variant.
    final reason = conflicts.values.contains(null)
        ? 'a variant that can hold values of several JSON types (a union '
              'without a discriminator, or a schema without a type)'
        : 'variants that share a JSON type';
    context.report(
      .unionUndiscriminated,
      'This $kind has no discriminator and $reason, so a value cannot be '
      'told apart by its type; it is generated as JsonValue.',
      schema.location,
      fix:
          'Add a discriminator at the source, or generate a union that tries '
          'the variants with union: structural (an override of the schema, '
          'or the config key for every such union).',
      override: context.schemaOverride(schema.location, {
        'union': 'structural',
      }),
    );
    return true;
  }

  /// The `union` of [schema]: its override, else the override of the
  /// property it is written in, else the config's.
  UnionMode _unionMode(SchemaObject schema) {
    final context = _tools.context;
    final overrides = context.overrides;
    return overrides.schemaAt(schema.location)?.union ??
        overrides.propertyAt(schema.location)?.union ??
        context.config.union;
  }

  /// Sets how the declaration of the union at [site] is built once it is
  /// named: a `oneOf`/`anyOf`, or, for a polymorphic base, the schemas that
  /// extend it with `allOf` (their flat models).
  void declare(UnionSite site) {
    final schema = site.schema;
    _notices.partsIgnored(site);
    if (!site.isSubtypes) {
      _notices.subsumedBranches(schema, site.scope, collapsed: false);
    }
    final choice = _chooseDispatch(schema, site.branches);
    final set = _collector.collect(site, choice);
    _reportOutcome(site, choice, set);
    final draft = UnionDraft(
      site,
      choice.dispatch,
      set,
      _discriminators.read(site, set.variants),
    );
    site.pending.build = (name, types) => _build(draft, name, types);
  }

  /// How the union [schema] of [branches] tells its variants apart: by its
  /// discriminator, else by the JSON type of a value, else, when its
  /// `union` is `structural` and the JSON type does not tell them apart, by
  /// trying them.
  DispatchChoice _chooseDispatch(SchemaObject schema, List<Schema> branches) {
    final hasDiscriminator = schema.discriminator?.propertyName != null;
    final allConflicts = hasDiscriminator
        ? const <int, JsonKind?>{}
        : _kinds.conflicts(branches).$1;
    final UnionDispatch dispatch;
    if (hasDiscriminator) {
      dispatch = .discriminator;
    } else if (allConflicts.isEmpty) {
      dispatch = .jsonType;
    } else if (_unionMode(schema) == .structural) {
      dispatch = .structural;
    } else {
      dispatch = .jsonType;
    }
    // Branches of a JSON type others share are one variant of any JSON
    // value, unless the union tries them all.
    return DispatchChoice(
      dispatch,
      allConflicts,
      dispatch == .jsonType ? allConflicts : const {},
    );
  }

  /// Reports the branches that share a JSON type, and the override `union`
  /// that changes nothing for the union at [site].
  void _reportOutcome(UnionSite site, DispatchChoice choice, VariantSet set) {
    if (choice.conflicts.isNotEmpty) {
      _notices.sharedJsonType(
        site,
        choice.conflicts.keys.toSet(),
        set.sharedKinds,
      );
    }
    if (choice.dispatch == .discriminator || choice.allConflicts.isEmpty) {
      _tools.notices.unionHasNoEffect(
        site.schema,
        choice.dispatch == .discriminator
            ? 'the union has a discriminator'
            : set.droppedDuplicate && set.variants.length < 2
            ? 'the duplicate variants were dropped (TOA454), and one variant '
                  'is left'
            : 'the variants of the union have JSON types of their own',
      );
    }
  }

  /// The declaration of the union [draft], with its variant classes named in
  /// [types].
  UnionDecl _build(UnionDraft draft, String name, NameScope types) {
    final site = draft.site;
    final schema = site.schema;
    final variants = draft.set.variants;
    final classes = _variantNames.classes(name, [
      for (final variant in variants) variant.type,
    ]);
    return UnionDecl(
      id: site.pending.id,
      name: name,
      kind: site.kind,
      dispatch: draft.dispatch,
      discriminator: schema.discriminator?.propertyName,
      defaultVariant: draft.values.fallback,
      exhaustive:
          _tools.context.overrides.schemaAt(schema.location)?.exhaustive ??
          true,
      unknownSensitive: site.branches.any(
        (branch) => SchemaShapes.carriesSecret(
          branch,
          refs: _tools.queries.refs,
          intoProperties: true,
        ),
      ),
      description: schema.description,
      deprecated: schema.deprecated,
      variants: [
        for (final (i, variant) in variants.indexed)
          _variantIr(draft, variant, (classes[i], name), types),
      ],
      unknownName: _tools.names.helperName(
        types,
        '${name}Unknown',
        site.pending,
        'the unknown variant class of $name',
      ),
    );
  }

  /// The variant [variant] of the union [draft], wrapped in the class named
  /// by [named] (the class and the union) in [types].
  UnionVariantIr _variantIr(
    UnionDraft draft,
    VariantDraft variant,
    (String, String) named,
    NameScope types,
  ) {
    final (className, union) = named;
    final queries = _tools.queries;
    return UnionVariantIr(
      variant.type,
      discriminatorValues: [
        ...?draft.values.byTarget[variant.target ?? variant.branch.location],
      ]..sort(),
      name: _tools.names.helperName(
        types,
        className,
        draft.site.pending,
        'a variant class of $union',
      ),
      jsonKinds: [...variant.kinds]..sort((a, b) => a.index - b.index),
      sensitive:
          SchemaShapes.carriesSecret(variant.branch, refs: queries.refs) ||
          variant.type.holdsRawJson &&
              [variant.branch, ...variant.also].any(
                (branch) => queries.holdsRawSecret(branch, variant.type),
              ),
    );
  }
}
