import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'mapping_scope.dart';
import 'pending_declaration.dart';

/// A variant of a union being built: its type, the schema a `$ref` branch
/// (or a subtype) is, the branch, and, for the variant of any JSON value,
/// the JSON types it takes.
final class VariantDraft {
  /// A variant of [type] made from [branch]; [target] is the schema a `$ref`
  /// branch or a subtype names.
  VariantDraft(this.type, this.target, this.branch);

  /// The Dart type of the variant.
  final DartType type;

  /// The schema the branch refers to, when it is a `$ref` or a subtype.
  final SpecLocation? target;

  /// The branch as written.
  final Schema branch;

  /// The JSON types the variant of any JSON value takes.
  final List<JsonKind> kinds = [];

  /// The other branches that make up a variant of any JSON value, besides
  /// [branch].
  final List<Schema> also = [];
}

/// A union to declare: the schema, its declaration, the branches that make
/// the variants, and the scope they are mapped in.
final class UnionSite {
  /// The union [schema] of [branches], declared as [pending]; with
  /// [isSubtypes], the branches are the schemas that extend a base
  /// with `allOf` (their flat models).
  const UnionSite(
    this.schema,
    this.pending,
    this.kind,
    this.branches,
    this.scope, {
    this.isSubtypes = false,
  });

  /// The schema of the union.
  final SchemaObject schema;

  /// The declaration being filled in.
  final PendingDeclaration pending;

  /// Whether the branches were written as `oneOf` or `anyOf`.
  final UnionKind kind;

  /// The branches that make the variants, `null` ones left out.
  final List<Schema> branches;

  /// The scope the variants are mapped in.
  final MappingScope scope;

  /// Whether the union is a polymorphic base and the branches are its
  /// subtypes.
  final bool isSubtypes;
}

/// How a union tells its variants apart, and which of its branches share a
/// JSON type.
final class DispatchChoice {
  /// A choice of [dispatch]; [allConflicts] are the branches (by index) of a
  /// union without a discriminator that the JSON type cannot tell apart, and
  /// [conflicts] those of them that become one variant of any JSON value.
  const DispatchChoice(this.dispatch, this.allConflicts, this.conflicts);

  /// How a value picks its variant.
  final UnionDispatch dispatch;

  /// The branches that share a JSON type, with that type.
  final Map<int, JsonKind?> allConflicts;

  /// The branches that are one variant of any JSON value: the conflicts,
  /// unless the union tries every variant.
  final Map<int, JsonKind?> conflicts;
}

/// The variants a union's branches make.
final class VariantSet {
  /// Variants; [sharedKinds] are the JSON types of the variant of any JSON
  /// value, and [droppedDuplicate] says a duplicate was dropped.
  const VariantSet(this.variants, this.sharedKinds, this.droppedDuplicate);

  /// The variants, in order.
  final List<VariantDraft> variants;

  /// The JSON types the variant of any JSON value takes; empty without one.
  final List<JsonKind> sharedKinds;

  /// Whether a branch was dropped as a duplicate of another (TOA454).
  final bool droppedDuplicate;
}

/// The discriminator values that select the variants of a union.
final class DiscriminatorValues {
  /// Values by the location of the variant's schema; [fallback] is the
  /// variant the default mapping names.
  const DiscriminatorValues(this.byTarget, this.fallback);

  /// No values and no fallback: a union without a discriminator.
  const DiscriminatorValues.none() : byTarget = const {}, fallback = null;

  /// The values that select each variant, by the location of its schema.
  final Map<SpecLocation, List<String>> byTarget;

  /// The variant a value without a variant of its own selects.
  final DartType? fallback;
}

/// A union before its variants are named.
final class UnionDraft {
  /// A union of [site] told apart by [dispatch], whose [set] of variants
  /// the discriminator [values] select.
  const UnionDraft(this.site, this.dispatch, this.set, this.values);

  /// The union.
  final UnionSite site;

  /// How a value picks its variant.
  final UnionDispatch dispatch;

  /// The variants.
  final VariantSet set;

  /// The discriminator values of the variants and the fallback.
  final DiscriminatorValues values;
}
