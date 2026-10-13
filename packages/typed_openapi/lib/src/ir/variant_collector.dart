import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart' show JsonKind;
import 'json_kinds.dart';
import 'mapping_tools.dart';
import 'pending_declaration.dart';
import 'type_recursion.dart';
import 'union_notices.dart';
import 'union_state.dart';

/// Makes the variants of a union from its branches: maps each branch, drops
/// duplicates, and joins the branches whose JSON type others share into one
/// variant of any JSON value.
final class VariantCollector {
  /// A collector that maps branches with [_types].
  const VariantCollector(
    this._tools,
    this._types,
    this._kinds,
    this._notices,
  );

  final MappingTools _tools;
  final TypeRecursion _types;
  final JsonKinds _kinds;
  final UnionNotices _notices;

  /// The variants of the union at [site] that [choice] picks the variants
  /// of.
  VariantSet collect(UnionSite site, DispatchChoice choice) {
    final run = _Collection(choice.conflicts);
    // A branch that is the same schema as a conflicting one is a duplicate
    // of it, not a variant of its own.
    final conflicting = {
      for (final i in choice.conflicts.keys)
        ?_tools.queries.resolved(site.branches[i])?.location,
    };
    for (final (i, branch) in site.branches.indexed) {
      _collectBranch(run, site, (i, branch), conflicting);
    }
    if (choice.dispatch == .jsonType) _joinUntyped(run);
    return VariantSet(run.variants, run.shared?.kinds ?? const [], run.dropped);
  }

  void _collectBranch(
    _Collection run,
    UnionSite site,
    (int, Schema) indexed,
    Set<SpecLocation> conflicting,
  ) {
    final (i, branch) = indexed;
    if (run.conflicts.containsKey(i)) {
      run.share(run.conflicts[i]!, branch);
      return;
    }
    if (conflicting.contains(_tools.queries.resolved(branch)?.location)) {
      _notices.variantDuplicate(branch, site.kind, sameSchema: true);
      run.dropped = true;
      return;
    }
    final type = _typeOf(site, i, branch);
    if (run.variants.any((v) => v.kinds.isEmpty && v.type == type)) {
      _notices.variantDuplicate(branch, site.kind, sameSchema: false);
      run.dropped = true;
      return;
    }
    final refersToSchema =
        site.isSubtypes || (branch is SchemaObject && branch.ref != null);
    run.variants.add(
      VariantDraft(
        type,
        refersToSchema ? _tools.queries.resolved(branch)?.location : null,
        branch,
      ),
    );
  }

  /// The type of the branch [index]: the model of a subtype, else the type
  /// of the schema, an inline one named after the union.
  DartType _typeOf(UnionSite site, int index, Schema branch) => site.isSubtypes
      ? _types.component(branch as SchemaObject, site.scope)
      : _types.map(
          branch,
          NameHint.under(site.pending, 'Variant${index + 1}'),
          site.scope,
        );

  /// Joins into the variant of any JSON value the variants that came out as
  /// a type of any JSON value (a schema excluded or replaced, a recursive
  /// alias): they are picked by their JSON type no more.
  void _joinUntyped(_Collection run) {
    for (final variant in [...run.variants]) {
      if (variant.kinds.isNotEmpty || _kinds.ofType(variant.type) != null) {
        continue;
      }
      final at = run.variants.indexOf(variant);
      run.variants.remove(variant);
      if (_kinds.ofSchema(variant.branch, {}) case final kind?) {
        run.share(kind, variant.branch, at);
      }
    }
  }
}

/// What one collection has made so far.
final class _Collection {
  _Collection(this.conflicts);

  /// The branches (by index) that are one variant of any JSON value.
  final Map<int, JsonKind?> conflicts;
  final List<VariantDraft> variants = [];
  VariantDraft? shared;
  bool dropped = false;

  /// Adds the [branch] of JSON type [kind] to the variant of any JSON
  /// value, which is made at [at] (or last) when it is the first.
  void share(JsonKind kind, Schema branch, [int? at]) {
    var variant = shared;
    if (variant == null) {
      variant = shared = VariantDraft(const CoreType(.json), null, branch);
      variants.insert(at ?? variants.length, variant);
    }
    if (!variant.also.contains(branch)) variant.also.add(branch);
    if (!variant.kinds.contains(kind)) variant.kinds.add(kind);
  }
}
