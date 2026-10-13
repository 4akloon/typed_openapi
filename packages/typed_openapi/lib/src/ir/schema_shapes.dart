import '../model/schema.dart';
import 'ir.dart' show JsonKind;
import 'ref_follower.dart';
import 'schema_forms.dart';
import 'secret_detection.dart';
import 'subsumed_branches.dart';

/// Questions about the shape of a schema that the schema mapper and the
/// direction index both ask: whether it is only `null`, what enum values it
/// has, which one schema it stands for, which branches add no value, whether
/// it holds a secret.
///
/// The answers live in [SchemaForms], [SubsumedBranches] and
/// [SecretDetection]; this is the one place the callers know.
final class SchemaShapes {
  const SchemaShapes._();

  /// The one schema [schema] stands for (R6.3): the part of an `allOf` with
  /// one part besides parts that only annotate ([isAnnotationOnly]), or the
  /// branch of a `oneOf`/`anyOf` with one branch besides `null` and the
  /// branches that add no value to another ([subsumedBranches]); null when
  /// there is none. A [refs] follows the `$ref` of a branch.
  static Schema? singleOf(SchemaObject schema, {RefFollower? refs}) =>
      SchemaForms.singleOf(schema, refs: refs);

  /// The branches of the `oneOf` or `anyOf` of [schema] that add no value
  /// to another branch (TOA455), each with the JSON type of the branch that
  /// has its values: an enum or `const` of one primitive type next to a
  /// plain branch of that type, in a union without a discriminator
  /// (`anyOf: [string, {enum: ['']}]`). A [refs] follows the `$ref` of a
  /// branch; see [SubsumedBranches.of] for what makes a branch plain.
  static Map<SchemaObject, JsonKind> subsumedBranches(
    SchemaObject schema, {
    RefFollower? refs,
  }) => SubsumedBranches.of(schema, refs: refs);

  /// Whether [schema] is written inline and adds no structure: it has
  /// annotations (`description`, `default`, `deprecated`, `nullable`, ...)
  /// and constraints the client does not check; an `allOf` part like this
  /// is not merged into a model.
  static bool isAnnotationOnly(Schema schema) =>
      SchemaForms.isAnnotationOnly(schema);

  /// Whether an annotation-only `allOf` [part] says the value may be `null`:
  /// `nullable: true`, `type: 'null'` or a `null` enum or `const`.
  static bool allowsNull(SchemaObject part) => SchemaForms.allowsNull(part);

  /// The parts of the `allOf` of [schema] that [singleOf] sets aside
  /// because they only annotate: empty unless [schema] stands for the one
  /// structural part of its `allOf`.
  static List<SchemaObject> annotationParts(SchemaObject schema) =>
      SchemaForms.annotationParts(schema);

  /// The schemas that say what the property [property] is, in the order they
  /// are met: the property, its annotation-only `allOf` parts, and the
  /// schema it stands for, each followed through its `$ref` ([refs]).
  /// `readOnly`, `writeOnly` and `format: password` are read from every one
  /// of them.
  static List<SchemaObject> annotationSources(
    Schema property, {
    required RefFollower refs,
  }) => SecretDetection.annotationSources(property, refs: refs);

  /// Whether a value of [schema] is a secret that must not be printed
  /// (`toString` writes `<redacted>`). By default the properties of an
  /// object are not looked into; with [intoProperties] they are, for a value
  /// that stays raw JSON. See [SecretDetection.carriesSecret].
  static bool carriesSecret(
    Schema schema, {
    required RefFollower refs,
    bool intoProperties = false,
    Set<Object>? seen,
  }) => SecretDetection.carriesSecret(
    schema,
    refs: refs,
    intoProperties: intoProperties,
    seen: seen,
  );

  /// Whether [schema] is written inline and allows only `null`.
  static bool isNullOnly(Schema schema) => SchemaForms.isNullOnly(schema);

  /// The non-null values of an enum, or null when [schema] is not one: its
  /// `enum`, its `const` as a one-value enum, or the values of a `oneOf` or
  /// `anyOf` whose branches are all `const`s or enums written inline.
  static List<Object?>? enumValues(SchemaObject schema) =>
      SchemaForms.enumValues(schema);
}
