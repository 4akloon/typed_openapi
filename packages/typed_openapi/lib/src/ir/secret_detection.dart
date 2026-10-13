import '../model/schema.dart';
import 'ref_follower.dart';
import 'schema_forms.dart';

/// Which schemas say what a property is, and which values are secrets that
/// `toString` must not print.
final class SecretDetection {
  const SecretDetection._();

  /// The schemas that say what the property [property] is, in the order they
  /// are met: the property, the annotation-only parts of its `allOf`
  /// ([SchemaForms.annotationParts]), and the schema it stands for ([SchemaForms.singleOf]: the one
  /// part of an `allOf`, or the one branch of a `oneOf`/`anyOf` besides
  /// `null`), each followed through its `$ref` ([refs]) and again through
  /// the one schema it stands for. `readOnly`, `writeOnly` and `format:
  /// password` are read from every one of them, so a nullable
  /// `anyOf: [{type: string, format: password}, {type: 'null'}]` (Pydantic's
  /// `Optional[SecretStr]`) is as much a secret as the plain string.
  static List<SchemaObject> annotationSources(
    Schema property, {
    required RefFollower refs,
  }) {
    final sources = <SchemaObject>[];
    final seen = <Object>{};
    void visit(Schema schema) {
      if (schema is! SchemaObject || !seen.add(schema.location)) return;
      sources.add(schema);
      if (schema.ref != null) {
        if (refs.resolve(schema) case final target?) visit(target);
        return;
      }
      sources.addAll(SchemaForms.annotationParts(schema));
      if (SchemaForms.singleOf(schema, refs: refs) case final single?) {
        visit(single);
      }
    }

    visit(property);
    return sources;
  }

  /// Whether a value of [schema] is a secret that must not be printed
  /// (`toString` writes `<redacted>`): a source of [annotationSources] is
  /// `writeOnly` or has `format: password`, or the value holds one: an
  /// array whose items are secrets, an object whose `additionalProperties`
  /// are, or a `oneOf`/`anyOf` with a secret branch (a union whose value may
  /// be the secret, also when it is not generated as a union).
  ///
  /// By default the properties of an object are not looked into: the model
  /// of the object redacts its own. With [intoProperties] they are, and so
  /// are the parts of an `allOf`, at any depth (a cycle is followed once):
  /// that is the question to ask of a value that stays raw JSON (`JsonValue`,
  /// the unknown variant of a union), which no model prints.
  static bool carriesSecret(
    Schema schema, {
    required RefFollower refs,
    bool intoProperties = false,
    Set<Object>? seen,
  }) {
    final visited = seen ?? <Object>{};
    if (schema is! SchemaObject || !visited.add(schema.location)) return false;
    for (final source in annotationSources(schema, refs: refs)) {
      if (source.writeOnly || source.format == 'password') return true;
      for (final inner in [
        ?source.items,
        ...source.prefixItems,
        ?source.additionalProperties,
        for (final branch in [...source.oneOf, ...source.anyOf])
          if (!SchemaForms.isNullOnly(branch)) branch,
        if (intoProperties) ...source.properties.values,
        if (intoProperties) ...source.allOf,
      ]) {
        if (carriesSecret(
          inner,
          refs: refs,
          intoProperties: intoProperties,
          seen: visited,
        )) {
          return true;
        }
      }
    }
    return false;
  }
}
