import 'severity.dart';

/// The catalog of diagnostic codes.
///
/// An [id] is stable: once released it never changes meaning.
enum DiagnosticCode {
  /// The document is not valid JSON or YAML.
  ///
  /// Example: A YAML file with a tab in its indentation, or a JSON file with a
  /// trailing comma.
  ///
  /// Fix: Correct the syntax at the source; the message gives the line and
  /// column.
  parseError('TOA001', 'parse-error', .error),

  /// A mapping repeats a key.
  ///
  /// Example: Two `get:` keys under one path item.
  ///
  /// Fix: Remove one of the keys.
  duplicateKey('TOA002', 'duplicate-key', .warning),

  /// The document root is not an object.
  ///
  /// Example: A file whose top level is a list or a string.
  ///
  /// Fix: Make the top level of the file an OpenAPI object.
  rootNotObject('TOA003', 'root-not-object', .error),

  /// The input file, or a file a `$ref` points to, does not exist.
  ///
  /// Example: `input:` in the config names a file that is not there, or a
  /// `$ref` points to a missing file.
  ///
  /// Fix: Check `input` in the config, or download a fresh snapshot of the
  /// spec.
  inputNotFound('TOA004', 'input-not-found', .error),

  /// Source positions could not be recorded for a document.
  ///
  /// Example: A `.json` file that the position-tracking reader rejects but
  /// plain JSON decoding accepts.
  ///
  /// Fix: Nothing to do; the diagnostics of that file show JSON pointers and no
  /// line.
  positionsUnavailable('TOA005', 'positions-unavailable', .info),

  /// The input file exists but cannot be read as UTF-8 text.
  ///
  /// Example: `input:` points at a directory, or at a file that is not UTF-8
  /// text or cannot be opened.
  ///
  /// Fix: Point `input` at the spec file itself if it is a directory; otherwise
  /// save the spec as UTF-8 and check the file permissions.
  inputUnreadable('TOA006', 'input-unreadable', .error),

  /// The document nests deeper than the parser can follow, in its text or
  /// once YAML aliases are expanded.
  ///
  /// Example: A JSON file with more than 1000 nested arrays.
  ///
  /// Fix: Flatten the document at the source.
  nestingTooDeep('TOA007', 'nesting-too-deep', .error),

  /// YAML aliases expand to far more nodes than the text has, or the JSON
  /// pointers of the document's nodes add up to more than the budget.
  ///
  /// Example: A chain of YAML anchors in which each one aliases the previous
  /// anchor several times, so that a short file expands to millions of nodes.
  ///
  /// Fix: Write the repeated part out once and refer to it with `$ref` instead
  /// of YAML aliases.
  aliasExpansionTooLarge('TOA008', 'alias-expansion-too-large', .error),

  /// A YAML tag outside the JSON Schema ruleset OpenAPI requires, such as
  /// `!!timestamp` or `!custom`; the value is read as its text.
  ///
  /// Example: A value written as `!!timestamp 2001-12-14` or `!custom x`.
  ///
  /// Fix: Remove the tag, or quote the value so that it is a plain string.
  yamlTagUnsupported('TOA009', 'yaml-tag-unsupported', .error),

  /// The document has no `openapi` field.
  ///
  /// Example: A document that starts with `info:` and has no `openapi:` line.
  ///
  /// Fix: Add the version the backend emits, for example `openapi: 3.0.3`.
  missingOpenApiVersion('TOA010', 'missing-openapi-version', .error),

  /// The document declares a version this tool does not read.
  ///
  /// Example: A Swagger 2.0 document (`swagger: "2.0"`) or `openapi: 4.0.0`.
  ///
  /// Fix: Have the backend emit OpenAPI 3, or convert the document.
  unsupportedOpenApiVersion(
    'TOA011',
    'unsupported-openapi-version',
    .error,
  ),

  /// The document declares a 3.x minor version newer than 3.2.
  ///
  /// Example: `openapi: 3.3.0`.
  ///
  /// Fix: Declare `openapi: 3.2.0` if the document is written to that version.
  unknownOpenApiMinorVersion(
    'TOA012',
    'unknown-openapi-minor-version',
    .warning,
  ),

  /// The `openapi` field is not a string, so YAML may have changed it (3.10
  /// reads as 3.1).
  ///
  /// Example: `openapi: 3.10` in YAML, which a YAML parser reads as the number
  /// 3.1.
  ///
  /// Fix: Quote the version, for example `openapi: "3.1.0"`.
  openApiVersionNotString(
    'TOA013',
    'openapi-version-not-string',
    .warning,
  ),

  /// The YAML parser warns about the text, for example about an unknown
  /// directive; reading goes on.
  ///
  /// Example: A YAML directive that the parser does not know.
  ///
  /// Fix: Fix the construct the message names, or remove it.
  yamlWarning('TOA015', 'yaml-warning', .warning),

  /// A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct;
  /// it is read as 3.1.
  ///
  /// Example: `openapi: 3.0.3` with a schema that has `type: [string, "null"]`
  /// or `const`.
  ///
  /// Fix: Declare `openapi: 3.1.0` if the backend emits 3.1; otherwise remove
  /// the construct.
  openApi31InOpenApi30('TOA020', 'openapi-3-1-in-3-0', .warning),

  /// A 3.1 or later document uses `nullable`, which only 3.0 defines; it is
  /// read as in 3.0.
  ///
  /// Example: `openapi: 3.1.0` with a schema that has `nullable: true`.
  ///
  /// Fix: Write `type: [<type>, "null"]` instead of `nullable: true`.
  nullableAfterOpenApi30('TOA021', 'nullable-after-3-0', .warning),

  /// A document older than 3.2 uses an OpenAPI 3.2 construct; it is read
  /// anyway.
  ///
  /// Example: `openapi: 3.1.0` with an `in: querystring` parameter or an
  /// `itemSchema`.
  ///
  /// Fix: Declare `openapi: 3.2.0` if the backend emits 3.2; otherwise remove
  /// the construct.
  openApi32InOlder('TOA022', 'openapi-3-2-in-older', .info),

  /// A `$ref` is empty, truncated or not a URI with a JSON pointer.
  ///
  /// Example: `$ref: ''` or a `$ref` with a query string such as `a.yaml?x=1`.
  ///
  /// Fix: Fix the code that writes the spec; in NestJS this usually means a
  /// circular import made a DTO type undefined.
  invalidRef('TOA100', 'invalid-ref', .error),

  /// A `$ref` points to a file or a node that does not exist.
  ///
  /// Example: `$ref: '#/components/schemas/Pet'` when `components.schemas` has
  /// no `Pet`.
  ///
  /// Fix: Define the target, or point the reference at an existing one.
  unresolvedRef('TOA101', 'unresolved-ref', .error),

  /// A `$ref` points to a remote URL; only local files are read.
  ///
  /// Example: `$ref: 'https://example.com/common.yaml#/Error'`.
  ///
  /// Fix: Save the document next to the spec and refer to it by a relative
  /// path.
  remoteRef('TOA102', 'remote-ref', .error),

  /// `$ref`s point at each other in a loop that never reaches a definition.
  ///
  /// Example: `A: {$ref: B}` and `B: {$ref: A}`.
  ///
  /// Fix: Point one of them at the actual definition.
  refCycle('TOA103', 'ref-cycle', .error),

  /// A `$ref` points to a node of another kind, such as a schema where a
  /// parameter is expected.
  ///
  /// Example: A `$ref` in a `parameters` list that points to a schema.
  ///
  /// Fix: Point the `$ref` at a node of the kind the place expects.
  refKindMismatch('TOA104', 'ref-kind-mismatch', .error),

  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
  /// resolves them against the file location instead.
  ///
  /// Example: A schema with `$id: https://example.com/schemas/pet` whose
  /// `$ref`s are relative.
  ///
  /// Fix: Remove `$id` or `$self` if it only names the schema; references are
  /// resolved against the file.
  refBaseIgnored('TOA105', 'ref-base-ignored', .warning),

  /// A key in `components` has characters OpenAPI does not allow there.
  ///
  /// Example: A key such as `Pet Store` under `components.schemas`; OpenAPI
  /// allows letters, digits and `.`, `-`, `_`.
  ///
  /// Fix: Rename it at the source; type names are derived from it.
  invalidComponentKey('TOA106', 'invalid-component-key', .warning),

  /// A `$ref` where OpenAPI does not accept a Reference Object, as bundlers
  /// such as Redocly allow; it is ignored.
  ///
  /// Example: A `$ref` beside the `get:` key of a path item, or in place of the
  /// `info` object.
  ///
  /// Fix: Write the object in place, or use a bundler to inline the reference.
  refNotAllowed('TOA107', 'ref-not-allowed', .warning),

  /// `$ref: #/...` without quotes in YAML: `#` starts a comment, so the
  /// value is null.
  ///
  /// Example: `$ref: #/components/schemas/Pet` without quotes in YAML.
  ///
  /// Fix: Quote the reference: `$ref: '#/components/schemas/Pet'`.
  refCommentedOut('TOA108', 'ref-commented-out', .warning),

  /// A YAML 1.1 merge key `<<`, which OpenAPI's YAML does not have; it is
  /// read as a plain key named `<<`.
  ///
  /// Example: A mapping with `<<: *defaults`.
  ///
  /// Fix: Write the keys out.
  yamlMergeKey('TOA109', 'yaml-merge-key', .warning),

  /// An object has a key that no OpenAPI version defines; it is ignored.
  ///
  /// Example: A schema with `nullabel: true`, or a key that no OpenAPI version
  /// has and that does not start with `x-`.
  ///
  /// Fix: Fix the spelling, or prefix a custom key with `x-`.
  unknownKey('TOA110', 'unknown-key', .warning),

  /// A field has the wrong JSON type or a value the spec does not allow; it
  /// is ignored.
  ///
  /// Example: `type: strng` on a schema, or `required: yes` where a list is
  /// expected.
  ///
  /// Fix: For an unknown `type`, use one of `string`, `number`, `integer`,
  /// `boolean`, `array`, `object`, `null`; otherwise give the field the type
  /// the message names.
  invalidValue('TOA111', 'invalid-value', .warning),

  /// A field the spec requires is missing.
  ///
  /// Example: An `info` object without `title`, or a parameter without `name`.
  ///
  /// Fix: Add the field the message names at the source.
  missingRequiredField('TOA112', 'missing-required-field', .warning),

  /// A mapping key is a collection, or an alias of one, instead of a
  /// string; the entry is ignored.
  ///
  /// Example: A YAML key written as `? [a, b]`.
  ///
  /// Fix: Write the key as a plain or quoted string.
  nonStringKey('TOA113', 'non-string-key', .error),

  /// A mapping key is a YAML null (`~`, `null` or empty); it is read as its
  /// text.
  ///
  /// Example: A YAML key written as `~:` or `null:`, or an empty key.
  ///
  /// Fix: Quote the key, for example `"null":`.
  nullKey('TOA114', 'null-key', .warning),

  /// A property schema says `required: true` or `false` (OpenAPI 2 style); for
  /// `true` the name is moved into the object's `required` list, for `false`
  /// the flag is only removed. When the `required` of the object is not a list,
  /// nothing is changed.
  ///
  /// Example: A property schema with `required: true`, as OpenAPI 2 writes it.
  ///
  /// Fix: Add the name to `required` of the object schema and remove `required`
  /// from the property at the source; until then the tool applies this for you,
  /// except when `required` of the object is not a list.
  boolRequired('TOA201', 'bool-required', .warning),

  /// An array has no `items` in an OpenAPI 3.0 document, which requires it.
  ///
  /// Example: `type: array` without `items` in an `openapi: 3.0.x` document.
  ///
  /// Fix: Add `items` with the element schema at the source, or override
  /// `items` of this schema.
  arrayWithoutItems('TOA202', 'array-without-items', .warning),

  /// An array's `items` is an array with a boolean `required`: a list
  /// declared twice by a decorator.
  ///
  /// Example: `type: array` with `items: {type: array, required: true}`.
  ///
  /// Fix: If the field is a flat list, declare it once at the source; until
  /// then, override `items` of this schema with the inner `items`.
  doubleArray('TOA203', 'double-array', .warning),

  /// `format` is on an array without `items` instead of on its elements.
  ///
  /// Example: `type: array` without `items` and with `format: uuid`.
  ///
  /// Fix: Move `format` into the elements at the source; until then, override
  /// `items` of this schema with the element schema and remove its `format`.
  formatOnArray('TOA204', 'format-on-array', .warning),

  /// `type: object` with `format: binary` instead of a binary string.
  ///
  /// Example: `type: object` with `format: binary`.
  ///
  /// Fix: Write `type: string` at the source; until then, override `type` of
  /// this schema with `string`.
  binaryObject('TOA205', 'binary-object', .warning),

  /// `type: object` next to `oneOf`/`anyOf` whose branches are all of other
  /// types.
  ///
  /// Example: `type: object` next to a `oneOf` of `string` and `integer`.
  ///
  /// Fix: Remove `type: object` at the source; until then, remove `type` of
  /// this schema with an override.
  contradictoryObjectType('TOA206', 'contradictory-object-type', .warning),

  /// An `example` whose structure the schema does not allow: an object for
  /// an array, or a structure for a scalar and back.
  ///
  /// Example: A schema `type: array` with `example: {id: 1}`.
  ///
  /// Fix: Fix the schema or the example at the source; if the example is right,
  /// override `type` of this schema.
  exampleTypeMismatch('TOA207', 'example-type-mismatch', .warning),

  /// An `example` that is a scalar of another type than the scalar schema,
  /// such as a string for a number; only the documentation is off.
  ///
  /// Example: A schema `type: number` with `example: "12.5"`.
  ///
  /// Fix: Write the example as a number at the source.
  exampleScalarType('TOA208', 'example-scalar-type', .info),

  /// A schema's `default` is not of the schema's type; it is ignored.
  ///
  /// Example: A schema `type: integer` with `default: "ten"`.
  ///
  /// Fix: Change the default to a value of the schema's type, or remove it;
  /// until then the tool removes it for you.
  invalidDefault('TOA211', 'invalid-default', .warning),

  /// A schema allows several JSON types besides `null` (`type: [string,
  /// integer]`); it is generated as `JsonValue`.
  ///
  /// Example: `type: [string, integer]`.
  ///
  /// Fix: Give the schema one type at the source, or a Dart type with an
  /// override.
  mixedTypeSchema('TOA250', 'mixed-type-schema', .warning),

  /// A schema that is not an object, an enum or a union refers to itself
  /// (`A: {type: array, items: {$ref: A}}`); the reference is generated as
  /// `JsonValue`.
  ///
  /// Example: `A: {type: array, items: {$ref: '#/components/schemas/A'}}`.
  ///
  /// Fix: Make the recursive part an object schema at the source.
  recursiveAlias('TOA251', 'recursive-alias', .warning),

  /// Two `allOf` parts define the same property with different schemas;
  /// the later part's is used.
  ///
  /// Example: Two `allOf` parts that both define `id`, one as a string and one
  /// as an integer.
  ///
  /// Fix: Define each property in one `allOf` part at the source.
  allOfPropertyConflict('TOA252', 'allof-property-conflict', .info),

  /// An `allOf` part is not an object (a scalar, an enum or a union), so it
  /// cannot be merged into a model; it is ignored.
  ///
  /// Example: An `allOf` part that is `{type: string}` or an enum next to an
  /// object part.
  ///
  /// Fix: Make every `allOf` part an object schema at the source.
  allOfPartIgnored('TOA253', 'allof-part-ignored', .warning),

  /// A schema an override excludes is used by a generated type; the use is
  /// generated as `JsonValue`. An excluded `allOf` part is the exception: it is
  /// merged into the flat model all the same, and this says so. Also reported
  /// when an excluded schema has a custom Dart type: the type is used and the
  /// exclude has no effect.
  ///
  /// Example: An override `exclude: true` on a schema that a property of
  /// another schema refers to, or on a schema that also has a custom Dart type.
  ///
  /// Fix: Exclude what uses the schema too, or give the schema a custom Dart
  /// type instead of excluding it; when it has both, remove the `exclude` or
  /// the custom type.
  excludedSchemaReferenced('TOA254', 'excluded-schema-referenced', .info),

  /// An object with `properties` has a `oneOf` or `anyOf` whose branches
  /// only add constraints (`required`, `minProperties`, ...); it is
  /// generated as a model and the branches are ignored.
  ///
  /// Example: An object with `properties` and a `oneOf` whose branches are only
  /// `{required: [a]}` and `{required: [b]}`.
  ///
  /// Fix: Nothing to do; the client does not check the constraints.
  oneOfConstraintsIgnored('TOA255', 'oneof-constraints-ignored', .info),

  /// Parts, properties or branches of a schema are ignored because another
  /// keyword decides its shape: `allOf` parts or `properties` beside a
  /// `oneOf` or `anyOf` union, or the union's branches when the schema is
  /// a model made of `allOf` parts or `properties`.
  ///
  /// Example: A schema with `oneOf: [A, B]` and also `properties`.
  ///
  /// Fix: Move the properties into the branches, or make the schema a plain
  /// union at the source.
  compositionPartsIgnored('TOA256', 'composition-parts-ignored', .warning),

  /// An `enum` repeats a value; the repeats are removed.
  ///
  /// Example: `enum: [a, b, a]`.
  ///
  /// Fix: Remove the repeated values at the source; until then the tool removes
  /// them for you.
  duplicateEnumValue('TOA301', 'duplicate-enum-value', .warning),

  /// A nullable enum written as `oneOf` of an enum of only `null` and a
  /// `$ref`.
  ///
  /// Example: `oneOf: [{enum: [null]}, {$ref: '#/components/schemas/Status'}]`.
  ///
  /// Fix: Write a nullable reference at the source; until then, override this
  /// schema as a nullable `$ref`.
  nullableEnumOneOf('TOA303', 'nullable-enum-one-of', .warning),

  /// An enum mixes values of several JSON types, or has objects or lists
  /// among its values; it is generated as `JsonValue`.
  ///
  /// Example: `enum: [1, "two", true]`.
  ///
  /// Fix: Give the enum values of one JSON type at the source.
  enumMixedValues('TOA350', 'enum-mixed-values', .warning),

  /// `x-enum-varnames` or `x-enum-descriptions` is not a list of strings as
  /// long as the enum; it is ignored.
  ///
  /// Example: An enum of three values with `x-enum-varnames` that lists two
  /// names.
  ///
  /// Fix: Make `x-enum-varnames` a list of strings with one name for each enum
  /// value.
  enumVarnamesInvalid('TOA351', 'enum-varnames-invalid', .warning),

  /// The discriminator property is not required in a variant.
  ///
  /// Example: A union with `discriminator.propertyName: kind` whose variants do
  /// not list `kind` in `required`.
  ///
  /// Fix: Add the discriminator property to `required` of each variant at the
  /// source.
  discriminatorNotRequired('TOA401', 'discriminator-not-required', .info),

  /// A `discriminator.mapping` value points to a schema that does not
  /// exist.
  ///
  /// Example: `mapping: {cat: '#/components/schemas/Kat'}` when there is no
  /// `Kat` schema.
  ///
  /// Fix: Point the mapping at an existing schema at the source; until then,
  /// override the mapping of this discriminator.
  discriminatorMappingUnresolved(
    'TOA402',
    'discriminator-mapping-unresolved',
    .error,
  ),

  /// A variant of a union with a discriminator is written inline, so no
  /// discriminator value selects it.
  ///
  /// Example: A union with a discriminator whose variant is an inline object,
  /// not a `$ref`.
  ///
  /// Fix: Make the variant a component schema and `$ref` it.
  discriminatorValueMissing('TOA450', 'discriminator-value-missing', .warning),

  /// A `discriminator.mapping` value, or the `defaultMapping`, names a schema
  /// that is not a variant of the union; it is ignored. A value that maps to
  /// the base schema itself, which is generated as the union of its subtypes,
  /// is decoded as the unknown variant with its JSON kept.
  ///
  /// Example: A `mapping` value that names a schema the union's `oneOf` does
  /// not list, or one that maps to the base schema itself.
  ///
  /// Fix: Map the value to a variant of the union, or to a schema that extends
  /// the base.
  discriminatorMappingNotVariant(
    'TOA451',
    'discriminator-mapping-not-variant',
    .info,
  ),

  /// A `discriminator` sits on a schema that is neither a `oneOf`/`anyOf`
  /// union nor a base other schemas extend with `allOf`: nothing can be
  /// picked by it, so the schema is generated as a model.
  ///
  /// Example: A schema with a `discriminator` that no other schema extends with
  /// `allOf` and that is not a union.
  ///
  /// Fix: Extend the schema with `allOf` in its subtypes, or list them in a
  /// `oneOf`.
  discriminatorWithoutSubtypes(
    'TOA452',
    'discriminator-without-subtypes',
    .info,
  ),

  /// A `oneOf` or `anyOf` without a discriminator has variants of the same
  /// JSON type, or a variant that can hold several (a nested union without a
  /// discriminator), so a value cannot be told apart: the
  /// union keeps it as `JsonValue` in one variant (`PetJson`), or, when no
  /// variant has a JSON type of its own, is `JsonValue` itself. An override
  /// `union: structural` (or the config key `union`) generates a union that
  /// tries the variants; a discriminator at the source is better.
  ///
  /// Example: `oneOf: [{$ref: Cat}, {$ref: Dog}]`, both objects, with no
  /// discriminator.
  ///
  /// Fix: Add a discriminator at the source, or generate a union that tries the
  /// variants with `union: structural` (an override of the schema, or the
  /// config key for every such union).
  unionUndiscriminated('TOA453', 'union-undiscriminated', .warning),

  /// Two variants of a union have the same Dart type; the later one is
  /// dropped, since a value could not be told apart between them.
  ///
  /// Example: A `oneOf` with two inline `{type: string}` branches.
  ///
  /// Fix: Remove the duplicate variant at the source.
  unionVariantDuplicate('TOA454', 'union-variant-duplicate', .info),

  /// A branch of a `oneOf` or `anyOf` without a discriminator is an enum or
  /// a `const` of a primitive type (`string`, `integer`, `number`,
  /// `boolean`) while another branch is that type with no constraint: the
  /// values of the first are values of the second, so the branch is dropped
  /// and, when one branch remains, the union is that type (Stripe's
  /// `anyOf: [string, {enum: ['']}]`). An integer enum next to a plain
  /// `number` is dropped too; a number enum next to an `integer` is not.
  ///
  /// The other branch counts as plain when it has no `enum`, `const`,
  /// `format`, `pattern` or keyword the rule does not model (`if`, `not`,
  /// `dependentSchemas`, ...), and every enum value meets its length and
  /// range constraints (`multipleOf` on the exact decimal numbers). From
  /// OpenAPI 3.1 the keywords next to the `$ref` of a branch are the
  /// branch's own and are held to the same rule; 3.0 ignores them. The
  /// values of a dropped branch stay in the documentation of the field
  /// ("Known values") when the union is a union class or collapses; a union
  /// that stays `JsonValue` lists none.
  ///
  /// For a `oneOf` the collapse is looser than the spec: a value both
  /// branches take (`''` for `oneOf: [string, {const: ''}]`) is rejected by
  /// the `oneOf` and accepted by the type. This is accepted on purpose: the
  /// idiom is common (Stripe), its authors mean "any of these", and the
  /// client does not validate.
  ///
  /// Example: `anyOf: [{type: string}, {enum: ['']}]`.
  ///
  /// Fix: Remove the enum branch at the source, or leave it for the
  /// documentation.
  unionBranchSubsumed('TOA455', 'union-branch-subsumed', .info),

  /// Two variants of a union with a discriminator are selected by the same
  /// value (a `const` of the property, a mapping entry or the implicit name):
  /// the earlier variant decodes it, and the later one is never picked by
  /// that value.
  ///
  /// Example: Two variants that both fix `kind` to `"circle"`, or a mapping
  /// that sends one value to two schemas.
  ///
  /// Fix: Give each variant its own discriminator value, in the mapping or in
  /// the `const` of the property.
  discriminatorValueDuplicate(
    'TOA456',
    'discriminator-value-duplicate',
    .warning,
  ),

  /// A `$ref` variant that the discriminator's `mapping` does not name fixes
  /// the discriminator property to one value (a `const` or a one-value
  /// `enum`, also through a `$ref` or an `allOf` part) that is not its
  /// component name: that value selects it, not the name OpenAPI implies
  /// (OpenAI's tool unions). An explicit `mapping` entry always wins.
  ///
  /// Example: A variant `ToolCall` without a mapping entry whose `type`
  /// property is `const: function`.
  ///
  /// Fix: Add the value to the `mapping` to say so, or map the component name
  /// if the payloads carry it.
  discriminatorValueDerived(
    'TOA457',
    'discriminator-value-derived',
    .info,
  ),

  /// A non-object variant of a union with a discriminator has the JSON type
  /// of an earlier variant (a string enum next to a plain string): a value
  /// of that type is decoded as the earlier variant, since a value that is
  /// not an object has no discriminator property to tell them apart, so this
  /// variant is never produced when decoding.
  ///
  /// Example: A union with a discriminator that has `{type: string}` and, after
  /// it, a string enum.
  ///
  /// Fix: Remove the variant at the source, or give the earlier variant a type
  /// that does not take every value of that JSON type.
  unionJsonTypeShadowed('TOA458', 'union-json-type-shadowed', .info),

  /// A variable of the path template has no path parameter; one is added.
  ///
  /// Example: The path `/products/{id}` on an operation that declares no `id`
  /// parameter.
  ///
  /// Fix: Declare each at the source as a parameter with `in: path`,
  /// `required: true` and `schema: {type: string}`; until then the tool adds
  /// it for you.
  missingPathParameter('TOA501', 'missing-path-parameter', .warning),

  /// A path parameter is not a variable of the path template, or is one in
  /// another case.
  ///
  /// Example: A path parameter `userId` on the path `/users/{id}`.
  ///
  /// Fix: Make the parameter name and the template variable the same at the
  /// source; until then, override the name of this parameter.
  pathParameterNotInTemplate(
    'TOA502',
    'path-parameter-not-in-template',
    .error,
  ),

  /// An operation has no `operationId`.
  ///
  /// Example: A `get:` operation without `operationId`.
  ///
  /// Fix: Add an `operationId` at the source, or override the method name of
  /// this operation.
  missingOperationId('TOA503', 'missing-operation-id', .info),

  /// Two operations share an `operationId`.
  ///
  /// Example: Two operations with `operationId: getPets`.
  ///
  /// Fix: Give each operation its own `operationId` at the source. To generate
  /// anyway, lower this code in the client's `severity` and pin the second
  /// method's name with an override.
  duplicateOperationId('TOA504', 'duplicate-operation-id', .error),

  /// A name from the spec is a Dart reserved word or a name Dart already has
  /// (`class`, `List`); the generated name gets a suffix.
  ///
  /// Example: A schema named `List` or a property named `class`.
  ///
  /// Fix: Rename it at the source if the suffix is unwelcome, or name it with
  /// an override.
  nameReserved('TOA550', 'name-reserved', .info),

  /// Two generated declarations, members or arguments would have the same
  /// name; the later one (by spec location) gets a suffix.
  ///
  /// Example: Schemas `PetList` and `pet_list`, which both become `PetList`.
  ///
  /// Fix: Rename the other type, or rename this one.
  nameCollision('TOA551', 'name-collision', .info),

  /// A name from the spec has no ASCII letter or digit, so no Dart name can
  /// be made from it; a generic name is used.
  ///
  /// Example: A schema named `日本語`.
  ///
  /// Fix: Rename the schema at the source, or name its type with an override.
  nameUnrepresentable('TOA552', 'name-unrepresentable', .warning),

  /// An operation has several tags; it is generated once, in the group of
  /// its first tag.
  ///
  /// Example: An operation with `tags: [pets, store]`.
  ///
  /// Fix: Keep one tag at the source, or name the group with an override
  /// `group`.
  operationMultipleTags('TOA553', 'operation-multiple-tags', .info),

  /// An operation has no tag; it is generated in the default group.
  ///
  /// Example: An operation with no `tags`.
  ///
  /// Fix: Tag the operations at the source, or set `group_by` to `path` or
  /// `single` in the config.
  operationUntagged('TOA554', 'operation-untagged', .info),

  /// Two tags differ only in case or separators, so they give one group.
  ///
  /// Example: Tags `pet-store` and `PetStore`.
  ///
  /// Fix: Write the tag the same way everywhere at the source.
  tagsMerged('TOA555', 'tags-merged', .info),

  /// A variable of the path template has no path parameter with its exact
  /// name (`{ID}` with a parameter `id`); the operation is not generated.
  ///
  /// Example: The path `/users/{ID}` with a parameter named `id`.
  ///
  /// Fix: Declare a path parameter with the exact name of the variable at the
  /// source.
  pathVariableUnbound('TOA556', 'path-variable-unbound', .error),

  /// A tag, `operationId` or path pattern of the config's `include` or
  /// `exclude` matches no operation of the spec.
  ///
  /// Example: `include: {tags: [petz]}` in the config when the spec has the tag
  /// `pets`.
  ///
  /// Fix: Fix the pattern, or remove it from the config.
  filterMatchesNothing('TOA557', 'filter-matches-nothing', .warning),

  /// The config lists the same tag, `operationId` or path pattern in both
  /// `include` and `exclude`; `exclude` wins.
  ///
  /// Example: The tag `internal` in both `include` and `exclude` of one client.
  ///
  /// Fix: Remove it from one of the filters.
  filterConflict('TOA558', 'filter-conflict', .info),

  /// A name from the spec lost characters when it became a Dart name
  /// (`Größe` became `grE`: letters outside ASCII are dropped). Changes of
  /// case and separators (`my_thing`, `X-Request-ID`) are not reported.
  ///
  /// Example: A property named `Größe`, which becomes `grE` because letters
  /// outside ASCII are dropped.
  ///
  /// Fix: Name it explicitly to keep the meaning: the text of the diagnostic
  /// ends with an `Override:` snippet. For a client name, set `naming.client`
  /// in the config.
  nameLossy('TOA559', 'name-lossy', .info),

  /// An override `name` (of a schema, property, operation, parameter) or
  /// `group` is not a valid Dart name for what it names (`my thing`, `1x`,
  /// `_private`), or loses characters when it is made one; the name made
  /// from it is used, or the override is ignored when nothing is left. A
  /// `group` that differs from UpperCamelCase only by case or separators
  /// (`pet-store`) is not reported: it is used as `PetStore`.
  ///
  /// Example: An override `name: my thing` or `name: 1x`.
  ///
  /// Fix: Give the override a valid Dart name of the right kind, or remove it.
  overrideNameInvalid('TOA560', 'override-name-invalid', .warning),

  /// No operation of a client is generated: all are filtered out, all are
  /// written as a `$ref` (TOA107), all have an unbound path variable (TOA556),
  /// all are event streams the client cannot express (TOA654) or all are left
  /// out by overrides. The message says why.
  ///
  /// Example: A client whose `include` filter leaves no operation.
  ///
  /// Fix: Fix the filters of the client, or the spec; the message says why
  /// nothing is generated.
  clientEmpty('TOA563', 'client-empty', .warning),

  /// A parameter's `style` is not allowed for its `in` (path takes `simple`,
  /// `label` or `matrix`; query `form`, `spaceDelimited`, `pipeDelimited` or
  /// `deepObject`; header `simple`; cookie `form` or `cookie`), or the
  /// `style` of the `encoding` of a form property is not one a query takes,
  /// so the default style is used.
  ///
  /// Example: A query parameter with `style: simple`, or a path parameter with
  /// `style: form`.
  ///
  /// Fix: Use one of the styles the parameter's location allows at the source.
  parameterStyleInvalid('TOA564', 'parameter-style-invalid', .warning),

  /// A parameter is `in: querystring` (OpenAPI 3.2), which the client cannot
  /// send yet: the parameter is not generated.
  ///
  /// Example: A parameter with `in: querystring`.
  ///
  /// Fix: Describe the query string as query parameters at the source.
  querystringNotGenerated('TOA565', 'querystring-not-generated', .warning),

  /// A path item or an operation has its own `servers`; the client sends every
  /// request to the base URL of the user's transport.
  ///
  /// Example: An operation with its own `servers: [{url:
  /// https://upload.example.com}]`.
  ///
  /// Fix: Send these requests through a transport with that base URL, or move
  /// the servers to the document.
  operationServersIgnored('TOA566', 'operation-servers-ignored', .warning),

  /// An operation has `callbacks`, or the document has `webhooks`: requests
  /// the server makes, which the client does not generate.
  ///
  /// Example: An operation with `callbacks:` or a document with `webhooks:`.
  ///
  /// Fix: Nothing to do; the client sends requests and does not receive them.
  callbacksNotGenerated('TOA567', 'callbacks-not-generated', .info),

  /// A security requirement names a scheme that `components.securitySchemes`
  /// does not have (or defines without a valid type), or is not an object
  /// (a string, `null`; also TOA111), or the `security` field is not a list
  /// (also TOA111): the alternative is left out of the
  /// operation's metadata when another one can be described, else it stays
  /// with a scheme of the kind unknown.
  ///
  /// Example: `security: [{apiKeyAuth: []}]` when `components.securitySchemes`
  /// has no `apiKeyAuth`.
  ///
  /// Fix: Write the requirement as an object that names a scheme the document
  /// defines, at the source.
  securitySchemeUnknown('TOA568', 'security-scheme-unknown', .warning),

  /// `typed_openapi.lock` keeps a name for a type or a method, but an
  /// override's name or a custom type took it first, or the kept name is not a
  /// usable Dart name for what it names (a hand-edited lock): it is named anew.
  ///
  /// Example: `typed_openapi.lock` keeps the name `Pet`, and an override now
  /// names another type `Pet`; or a lock edited by hand keeps the name `my
  /// pet`.
  ///
  /// Fix: Rename the override or the custom type, or accept the new name; run
  /// `generate --fresh-names` to write new names to the lock.
  lockedNameTaken('TOA569', 'locked-name-taken', .warning),

  /// `typed_openapi.lock` keeps the name of a type or a method that a run
  /// without the lock would name otherwise.
  ///
  /// Example: A schema renamed in the spec whose type keeps the name
  /// `typed_openapi.lock` recorded.
  ///
  /// Fix: Run `generate --fresh-names` to take the new names.
  lockedNameKept('TOA570', 'locked-name-kept', .info),

  /// `typed_openapi.lock` keeps a name for a type the spec no longer
  /// declares: the name is free again.
  ///
  /// Example: A schema removed from the spec whose name the lock still keeps.
  ///
  /// Fix: Nothing to do; the next `generate` drops it from the lock.
  lockedNameReleased('TOA571', 'locked-name-released', .info),

  /// `*/*` is used as a media type.
  ///
  /// Example: A response with the media type `*/*`.
  ///
  /// Fix: Declare the actual media type (usually `application/json`) at the
  /// source, or override the content type here.
  wildcardMediaType('TOA601', 'wildcard-media-type', .warning),

  /// A request or response body has a media type that is not JSON, a form,
  /// `multipart/form-data`, `text/*` or `text/event-stream` (or is a form or
  /// multipart response): it is sent or read as bytes and its schema is not
  /// used.
  ///
  /// Example: A response in `application/pdf`, or a request body in
  /// `application/xml`.
  ///
  /// Fix: Use a JSON media type at the source if the schema matters.
  mediaTypeAsBytes('TOA650', 'media-type-as-bytes', .info),

  /// A request body, a response or a parameter offers several media types; the
  /// client uses one and the message names the ones it drops.
  ///
  /// Example: A request body that offers both `application/json` and
  /// `application/xml`.
  ///
  /// Fix: Offer one media type at the source if the client should use another;
  /// for `sse.method: only`, remove it to keep the body in a method too.
  mediaTypesDropped('TOA651', 'media-types-dropped', .info),

  /// `errors.default_schema` names a key that is not in `components.schemas`;
  /// the setting is ignored.
  ///
  /// Example: `errors: {default_schema: ApiError}` in the config when
  /// `components.schemas` has no `ApiError`.
  ///
  /// Fix: Name a key of `components.schemas`, or remove the setting.
  defaultErrorSchemaMissing(
    'TOA652',
    'default-error-schema-missing',
    .warning,
  ),

  /// An operation documents no 2xx response: any 2xx is a success whose
  /// value is the body as `JsonValue`.
  ///
  /// Example: An operation whose `responses` has only `404` and `500`.
  ///
  /// Fix: Document the success response at the source.
  successUndocumented('TOA653', 'success-undocumented', .warning),

  /// An event-stream operation has a shape the client cannot express: its
  /// event-stream successes have different event types, or another success has
  /// a body that is not an event stream. The operation is not generated when
  /// some of its successes are only a stream; when each stream offers a body
  /// too, only the event-stream method is left out and the method that returns
  /// the body is generated. Also reported when an `sse` override of the event
  /// types does not reach a shared `$ref`'d response, so the event types still
  /// differ.
  ///
  /// Example: An operation whose `200` is `text/event-stream` and whose `201`
  /// is `application/json` only; or two event-stream successes with different
  /// `itemSchema`s.
  ///
  /// Fix: Offer `text/event-stream` on every success with a body and give the
  /// event-stream successes one event type; for a shared `$ref`'d response,
  /// override the schema it uses by its component name, or write the response
  /// in the operation.
  eventStreamNotGenerated('TOA654', 'event-stream-not-generated', .warning),

  /// The schema of a multipart body is not an object with properties (a
  /// union, an `allOf`, a map): there is no class of parts, the body is the
  /// schema's type, each property of its JSON is a part, and a binary
  /// string is sent as base64 text, not as a file.
  ///
  /// Example: A `multipart/form-data` body whose schema is a `oneOf` or a map.
  ///
  /// Fix: Describe the body as an object with a property for each part at the
  /// source.
  multipartNotObject('TOA655', 'multipart-not-object', .warning),

  /// An `encoding` entry of a multipart part or of a form property has
  /// `headers`, which the client does not send.
  ///
  /// Example: An `encoding` entry of a multipart part with `headers: {X-Rate:
  /// ...}`.
  ///
  /// Fix: Send the headers another way, or remove them at the source.
  encodingHeadersIgnored('TOA656', 'encoding-headers-ignored', .info),

  /// A key of an operation's `responses` is not an HTTP status: OpenAPI
  /// allows a code from 100 to 599, a range (`1XX` to `5XX`, in either case)
  /// and `default`. The response is not generated, so a key written by a
  /// tool or by hand can never reach a name or an expression of the client.
  /// A key that repeats another one in a different case (`2xx` and `2XX`)
  /// is reported the same way.
  ///
  /// Example: A `responses` key `"20"` or `"success"`.
  ///
  /// Fix: Rename or remove the key at the source.
  responseStatusInvalid('TOA657', 'response-status-invalid', .warning),

  /// A response documents a 1xx or 3xx status. The client has no result for
  /// them (Dio follows redirects and the interim statuses are not
  /// responses), so the response is not generated; at run time the status is
  /// an undocumented one, or handled by the `default` response when the
  /// operation has one.
  ///
  /// Example: A `responses` key `301` or `100`.
  ///
  /// Fix: Nothing to do; the status is handled as undocumented or by the
  /// `default` response.
  responseStatusNotGenerated(
    'TOA658',
    'response-status-not-generated',
    .info,
  ),

  /// An `encoding` key of a form or multipart body names no property of the
  /// body's schema (a misspelled name, a property the schema does not have):
  /// the entry is ignored.
  ///
  /// Example: An `encoding` entry `avatr` when the body's schema has the
  /// property `avatar`.
  ///
  /// Fix: Use the name of a property of the schema, or remove the entry.
  encodingKeyUnknown('TOA659', 'encoding-key-unknown', .warning),

  /// The `default` of a parameter does not match the parameter's `enum` or
  /// `format` (`default: other` for `enum: [a, b]`, a `format: date` default
  /// that is not a date): it is not documented as the default.
  ///
  /// Example: A parameter with `enum: [a, b]` and `default: other`.
  ///
  /// Fix: Use a default that fits the schema at the source.
  defaultValueInvalid('TOA660', 'default-value-invalid', .warning),

  /// The `contentType` of an `encoding` entry of a multipart part is a list
  /// (`image/png, image/jpeg`), a wildcard (`image/*`) or no media type: the
  /// part is sent with one concrete type, the file's own when it has one,
  /// else the first concrete type of the list, else `application/octet-stream`
  /// for a file and no media type for text.
  ///
  /// Example: A multipart part with `encoding.contentType: image/png,
  /// image/jpeg`.
  ///
  /// Fix: Name one concrete media type in the encoding at the source.
  partMediaTypeChosen('TOA661', 'part-media-type-chosen', .info),

  /// An object part of a multipart body has a `contentType` that is not
  /// JSON (`application/xml`). The client writes JSON only, so the part is
  /// a `String` the caller supplies, sent with that media type.
  ///
  /// Example: A multipart object part with `encoding.contentType:
  /// application/xml`.
  ///
  /// Fix: Write the value in that format yourself and pass the text, or
  /// describe the part as a string at the source.
  partMediaTypeNotJson('TOA662', 'part-media-type-not-json', .warning),

  /// A success of an operation offers JSON (or another body) and
  /// `text/event-stream`: the operation gets a second method, named with
  /// `naming.stream_suffix`, that returns the events.
  ///
  /// Example: An operation whose `200` offers `application/json` and
  /// `text/event-stream`.
  ///
  /// Fix: Nothing to do; set `naming.stream_suffix` in the config to name the
  /// second method otherwise.
  eventStreamMethodAdded('TOA663', 'event-stream-method-added', .info),

  /// The `schema` of an event stream is an array: each event's data is
  /// taken to be one item, as code-first frameworks write it.
  ///
  /// Example: A `text/event-stream` response whose `schema` is `{type: array,
  /// items: {$ref: Message}}`.
  ///
  /// Fix: Describe one event at the source (`itemSchema` in OpenAPI 3.2).
  eventDataArrayItems('TOA664', 'event-data-array-items', .info),

  /// `sse.reconnect` in the config asks event streams to reconnect, but it
  /// applies to GET only: an event-stream operation that is not GET does
  /// not reconnect, since repeating the request may not be safe, unless its
  /// own `sse.reconnect` override enables it. Reported once per such
  /// operation, and only when the config asks.
  ///
  /// Example: `sse: {reconnect: true}` in the config and a `POST` operation
  /// that returns an event stream.
  ///
  /// Fix: Enable `sse.reconnect` for this operation with an override if the
  /// request can be repeated.
  eventStreamReconnectOff('TOA665', 'event-stream-reconnect-off', .info),

  /// The `itemSchema` of an event stream does not say what the data of an
  /// event is (no `data` property, or one that is neither text nor JSON
  /// with a `contentSchema`): the data is read as text.
  ///
  /// Example: An `itemSchema` whose `data` property is an object without
  /// `contentMediaType`.
  ///
  /// Fix: Give `data` `contentMediaType: application/json` and a
  /// `contentSchema` at the source.
  eventItemSchemaUnread('TOA666', 'event-item-schema-unread', .warning),

  /// Two branches of an `itemSchema` union fix the same event name: the
  /// later one is left out.
  ///
  /// Example: Two branches of an `itemSchema` `oneOf` that both fix `event` to
  /// `"update"`.
  ///
  /// Fix: Give each event its own name at the source.
  eventNameDuplicate('TOA667', 'event-name-duplicate', .warning),

  /// An event name has no ASCII letter or digit (`""`, `*/`), so its
  /// variant is named by its place (`ChatEventEvent2`).
  ///
  /// Example: An event named `*/`.
  ///
  /// Fix: Name the event with letters at the source.
  eventNameUnrepresentable('TOA668', 'event-name-unrepresentable', .info),

  /// A part of the `sse` override of an operation does not apply: `data` or
  /// `events` find no `text/event-stream` 2xx response written in the
  /// operation (a `$ref`'d one is shared), the operation has no event stream
  /// for `reconnect`, `method` or `unknown`, `unknown` has no events by name
  /// to apply to, or an event's data cannot be read. The message names the
  /// part; the rest of `sse` applies.
  ///
  /// Example: An `sse: {data: Message}` override on an operation whose event
  /// stream response is a shared `$ref`.
  ///
  /// Fix: Remove the part the message names, or write the response in the
  /// operation; a shared response is overridden through the schema it uses, by
  /// its component name.
  sseOverrideNotApplied('TOA669', 'sse-override-not-applied', .warning),

  /// An event name that no `event:` line can carry: an empty one (the wire
  /// reads it as `message`) or one with a line break. Its variant could
  /// never be selected, so it is left out.
  ///
  /// Example: An event fixed to `""` or to a name with a line break.
  ///
  /// Fix: Give the event a name that fits on an `event:` line at the source.
  eventNameUnreachable('TOA670', 'event-name-unreachable', .warning),

  /// A `text/event-stream` response with an error status (or `default`) of
  /// an operation whose method does not return events: its body is read as
  /// text, like any other error body that is not JSON.
  ///
  /// Example: A `500` response in `text/event-stream` on an operation that
  /// returns JSON.
  ///
  /// Fix: Use a JSON media type for errors at the source if the schema matters.
  eventStreamErrorAsText('TOA671', 'event-stream-error-as-text', .info),

  /// A normalizer fix or an override was not applied: its file cannot be
  /// read, its target is gone, the spec kept changing after the last pass, or
  /// the change would have no effect in the spec's dialect.
  ///
  /// Example: A fix that still changes the spec after the third pass, or an
  /// override that would sit beside a `$ref` in an `openapi: 3.0.x` document.
  ///
  /// Fix: Read the message; usually override the referenced schema by name, or
  /// make the change at the source.
  fixNotApplied('TOA800', 'fix-not-applied', .warning),

  /// The overrides file a client names does not exist.
  ///
  /// Example: `overrides: overrides.yaml` in the config when the file is not
  /// there.
  ///
  /// Fix: Create the file, or fix `overrides` of this client in the config.
  overridesNotFound('TOA801', 'overrides-not-found', .error),

  /// The overrides file cannot be read, or an override has a value of the wrong
  /// type, or a field that cannot be set where it is (on a schema that is a
  /// reference, or together with `nullable` on a schema that is nullable
  /// through `anyOf` or `oneOf`); the value is ignored.
  ///
  /// Example: An overrides file that is a list, an override with `exclude:
  /// "yes"`, or a field other than `nullable` on a schema that is a `$ref`.
  ///
  /// Fix: Point `overrides` of this client at the overrides file itself, give
  /// each field the type the message names, and override `nullable` alone, or
  /// the schema by its name, where other fields cannot be set.
  invalidOverride('TOA802', 'invalid-override', .error),

  /// An override has a key this tool does not know, such as a misspelled
  /// field; it is ignored.
  ///
  /// Example: An override with `nme: Pet`.
  ///
  /// Fix: Fix the spelling; the message names the closest known key (`Did you
  /// mean "name"?`) when one is within edit distance 2, then lists the allowed
  /// keys.
  unknownOverrideKey('TOA803', 'unknown-override-key', .error),

  /// An override names an operation, a schema, a property, a parameter or a
  /// response the spec does not have; it is not applied.
  ///
  /// Example: An override for the operation `getPetz` when the spec has
  /// `getPets`.
  ///
  /// Fix: Remove the override, or fix its address.
  overrideTargetNotFound('TOA804', 'override-target-not-found', .warning),

  /// An override's address names more than one node, such as an
  /// `operationId` two operations share; it is not applied.
  ///
  /// Example: An override for `operationId: list` that two operations share, or
  /// for a parameter `id` found in the path and the query.
  ///
  /// Fix: For an `operationId` two operations share, address the operation as
  /// `METHOD /path`; for parameters with one name, write the key as `in:name`;
  /// for a response with several media types, add `contentType` to the
  /// override.
  overrideTargetAmbiguous('TOA805', 'override-target-ambiguous', .error),

  /// Two overrides change the same node; neither is applied.
  ///
  /// Example: Two override entries for `getPets`, one by `operationId` and one
  /// by `GET /pets`.
  ///
  /// Fix: Merge them into one override.
  overrideConflict('TOA806', 'override-conflict', .error),

  /// An override sets a value the spec already has, or a generation field
  /// has no effect (a `name` or `exhaustive` on an alias, a `name` on a
  /// schema that only a multipart body uses); it can be removed.
  ///
  /// Example: An override that sets `nullable: true` on a schema that is
  /// already nullable.
  ///
  /// Fix: Remove the override.
  overrideUnchanged('TOA807', 'override-unchanged', .info),

  /// An override addressed through an operation changes a node other
  /// operations may share: a path-level parameter, a `$ref`'d component or
  /// a node in another file.
  ///
  /// Example: A parameter override that changes a parameter defined once at the
  /// path level for every operation.
  ///
  /// Fix: Nothing to do if every operation should change; otherwise override
  /// each operation's own parameter.
  overrideSharedTarget('TOA808', 'override-shared-target', .info),

  /// An override removes the `type` of a nullable 3.1 schema, so the schema is
  /// no longer nullable: nullability is the `null` in that `type`.
  ///
  /// Example: An override `type: null` on a schema with `type: [string,
  /// "null"]`.
  ///
  /// Fix: Nothing to do if the schema should stop being nullable; remove the
  /// override if it should stay nullable.
  overrideNullabilityDropped(
    'TOA809',
    'override-nullability-dropped',
    .info,
  ),

  /// The baseline file a client names does not exist.
  ///
  /// Example: `baseline: baseline.yaml` in the config when the file is not
  /// there.
  ///
  /// Fix: Write it with `typed_openapi baseline create`, or fix `baseline` of
  /// this client in the config.
  baselineNotFound('TOA820', 'baseline-not-found', .error),

  /// The baseline file cannot be read, or an entry is malformed and is
  /// ignored.
  ///
  /// Example: A baseline file that is not YAML, has `version: 2`, or has an
  /// entry without a `code`.
  ///
  /// Fix: Point `baseline` of this client at the baseline file itself, or
  /// recreate it with `typed_openapi baseline create`.
  invalidBaseline('TOA821', 'invalid-baseline', .error),

  /// A baseline entry accepts more diagnostics than the check finds: the
  /// problem was fixed, and `baseline prune` can remove the entry.
  ///
  /// Example: A baseline entry for a problem the spec no longer has.
  ///
  /// Fix: Run `typed_openapi baseline prune`.
  baselineEntryStale('TOA822', 'baseline-entry-stale', .warning),

  /// The baseline file cannot be written.
  ///
  /// Example: `baseline create` in a directory that cannot be written.
  ///
  /// Fix: Make the baseline file's location writable.
  baselineNotWritten('TOA823', 'baseline-not-written', .error),

  /// `generate` refuses a client's output directory, which it would replace:
  /// it holds a `pubspec.yaml`, is the `lib` directory of a package, holds a
  /// symbolic link or an input of the run, or holds a file it did not write
  /// or that changed since it wrote it (a file the manifest does not list or
  /// whose hash differs, or any file when there is no manifest); the message
  /// names the files, and `--force` replaces them, but never a package, a
  /// link or an input. Nothing is written for the client.
  ///
  /// Example: An output directory that holds a `pubspec.yaml`, or a
  /// hand-written file next to the generated ones.
  ///
  /// Fix: Move the hand-written files out, point `output` at a directory the
  /// generator owns, or run `generate --force` to replace files (never a
  /// package, a link or an input).
  outputNotOwned('TOA830', 'output-not-owned', .error),

  /// `generate` cannot write a client's output directory, or another run
  /// holds its lock (`.<output>.typed_openapi.lock` next to the output; a
  /// lock of a process that is gone is taken over, and `--break-lock` takes
  /// over one whose owner cannot be told).
  ///
  /// Example: An output directory on a read-only file system, or a second
  /// `generate` running on the same output.
  ///
  /// Fix: Check whether another `generate` runs on this output; delete the lock
  /// file or use `--break-lock` only when its owner is gone.
  outputNotWritten('TOA831', 'output-not-written', .error),

  /// An earlier `generate` was killed while it replaced the output directory
  /// and left the previous tree or a half-built one in sibling directories
  /// named `.<output>.typed_openapi-*`. The run put the previous output back,
  /// when the output was missing, and removed the leftovers. Also reported when
  /// a run takes over the lock of a process that is gone, or breaks a lock
  /// whose owner cannot be told with `--break-lock`.
  ///
  /// Example: A `generate` that was killed halfway through replacing the
  /// output.
  ///
  /// Fix: Nothing to do after a recovery: the output is back as it was before
  /// the killed run. After a lock take-over, check that no other `generate`
  /// still runs on this output.
  outputRecovered('TOA832', 'output-recovered', .info),

  /// `generate --force` overwrote or deleted a file that it did not write or
  /// that changed since it wrote it; one report for each file.
  ///
  /// Example: `generate --force` over a hand-edited generated file.
  ///
  /// Fix: Nothing to do; keep hand-written code outside the output directory.
  outputFileReplaced('TOA833', 'output-file-replaced', .info),

  /// `generate --locked` found that a client's API differs from its snapshot in
  /// `typed_openapi.lock`, or that the lock has no snapshot of it, or one of a
  /// client the config no longer declares. The client is not written and the
  /// lock is not changed.
  ///
  /// Example: `generate --locked` in CI after the spec changed a type without a
  /// committed lock.
  ///
  /// Fix: Run `generate` without `--locked` and commit the lock; `typed_openapi
  /// diff` lists the changes.
  apiLockDiffers('TOA834', 'api-lock-differs', .error),

  /// `typed_openapi.lock` cannot be read, is not a lock of version 1, or
  /// cannot be written. A run that cannot read it writes no client.
  ///
  /// Example: A `typed_openapi.lock` with unresolved merge conflict markers.
  ///
  /// Fix: Resolve the merge conflict in the file, or delete it to start from
  /// the current API.
  apiLockUnusable('TOA835', 'api-lock-unusable', .error),

  /// The configuration file does not exist.
  ///
  /// Example: `--config` naming a file that is not there, or no
  /// `typed_openapi.yaml` in the working directory.
  ///
  /// Fix: Create `typed_openapi.yaml`, or pass its path with `--config`.
  configNotFound('TOA901', 'config-not-found', .error),

  /// The configuration file is malformed or has an invalid value.
  ///
  /// Example: A `typed_openapi.yaml` that is a list, a client without `input`,
  /// or `group_by: tags`.
  ///
  /// Fix: Pass the path of `typed_openapi.yaml` itself with `--config`, and fix
  /// the value the message names.
  configInvalid('TOA902', 'config-invalid', .error),

  /// The configuration file has a key this tool does not know.
  ///
  /// Example: A config with `clients.shop.outptu:`.
  ///
  /// Fix: Fix the spelling; the message lists the allowed keys at that place
  /// (`Allowed keys here: ...`).
  configUnknownKey('TOA903', 'config-unknown-key', .warning),

  /// Two clients write to the same or nested output directories.
  ///
  /// Example: Two clients whose `output` is `lib/api` and `lib/api/shop`.
  ///
  /// Fix: Give each client its own output directory.
  outputOverlap('TOA904', 'output-overlap', .error);

  const DiagnosticCode(this.id, this.slug, this.defaultSeverity);

  /// Codes of the config file: it is read before any level applies, so the
  /// config cannot change them.
  static const configCodes = {
    configNotFound,
    configInvalid,
    configUnknownKey,
    outputOverlap,
  };

  /// Codes the config may raise but not lower or turn off: they say that the
  /// spec, the overrides file or the baseline file cannot be read (or the
  /// baseline file written), so without them the check would pass on a file
  /// it never read. The config codes ([configCodes]) cannot be changed at
  /// all.
  static const fixedCodes = {
    parseError,
    rootNotObject,
    inputNotFound,
    inputUnreadable,
    nestingTooDeep,
    aliasExpansionTooLarge,
    missingOpenApiVersion,
    unsupportedOpenApiVersion,
    overridesNotFound,
    invalidOverride,
    unknownOverrideKey,
    baselineNotFound,
    invalidBaseline,
    baselineNotWritten,
    outputNotOwned,
    outputNotWritten,
    outputRecovered,
    outputFileReplaced,
    apiLockDiffers,
    apiLockUnusable,
    ...configCodes,
  };

  /// The stable id, such as `TOA001`.
  final String id;

  /// The human-readable name, such as `parse-error`.
  final String slug;

  /// The severity used unless configuration overrides it.
  final Severity defaultSeverity;
}
