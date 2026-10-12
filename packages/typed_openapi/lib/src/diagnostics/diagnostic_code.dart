import 'severity.dart';

/// The catalog of diagnostic codes.
///
/// An [id] is stable: once released it never changes meaning.
enum DiagnosticCode {
  /// The document is not valid JSON or YAML.
  parseError('TOA001', 'parse-error', .error),

  /// A mapping repeats a key.
  duplicateKey('TOA002', 'duplicate-key', .warning),

  /// The document root is not an object.
  rootNotObject('TOA003', 'root-not-object', .error),

  /// The input file, or a file a `$ref` points to, does not exist.
  inputNotFound('TOA004', 'input-not-found', .error),

  /// Source positions could not be recorded for a document.
  positionsUnavailable('TOA005', 'positions-unavailable', .info),

  /// The input file exists but cannot be read as UTF-8 text.
  inputUnreadable('TOA006', 'input-unreadable', .error),

  /// The document nests deeper than the parser can follow, in its text or
  /// once YAML aliases are expanded.
  nestingTooDeep('TOA007', 'nesting-too-deep', .error),

  /// YAML aliases expand to far more nodes than the text has, or the JSON
  /// pointers of the document's nodes add up to more than the budget.
  aliasExpansionTooLarge('TOA008', 'alias-expansion-too-large', .error),

  /// A YAML tag outside the JSON Schema ruleset OpenAPI requires, such as
  /// `!!timestamp` or `!custom`; the value is read as its text.
  yamlTagUnsupported('TOA009', 'yaml-tag-unsupported', .error),

  /// The document has no `openapi` field.
  missingOpenApiVersion('TOA010', 'missing-openapi-version', .error),

  /// The document declares a version this tool does not read.
  unsupportedOpenApiVersion(
    'TOA011',
    'unsupported-openapi-version',
    .error,
  ),

  /// The document declares a 3.x minor version newer than 3.2.
  unknownOpenApiMinorVersion(
    'TOA012',
    'unknown-openapi-minor-version',
    .warning,
  ),

  /// The `openapi` field is not a string, so YAML may have changed it (3.10
  /// reads as 3.1).
  openApiVersionNotString(
    'TOA013',
    'openapi-version-not-string',
    .warning,
  ),

  /// The YAML parser warns about the text, for example about an unknown
  /// directive; reading goes on.
  yamlWarning('TOA015', 'yaml-warning', .warning),

  /// A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct;
  /// it is read as 3.1.
  openApi31InOpenApi30('TOA020', 'openapi-3-1-in-3-0', .warning),

  /// A 3.1 or later document uses `nullable`, which only 3.0 defines; it is
  /// read as in 3.0.
  nullableAfterOpenApi30('TOA021', 'nullable-after-3-0', .warning),

  /// A document older than 3.2 uses an OpenAPI 3.2 construct; it is read
  /// anyway.
  openApi32InOlder('TOA022', 'openapi-3-2-in-older', .info),

  /// A `$ref` is empty, truncated or not a URI with a JSON pointer.
  invalidRef('TOA100', 'invalid-ref', .error),

  /// A `$ref` points to a file or a node that does not exist.
  unresolvedRef('TOA101', 'unresolved-ref', .error),

  /// A `$ref` points to a remote URL; only local files are read.
  remoteRef('TOA102', 'remote-ref', .error),

  /// `$ref`s point at each other in a loop that never reaches a definition.
  refCycle('TOA103', 'ref-cycle', .error),

  /// A `$ref` points to a node of another kind, such as a schema where a
  /// parameter is expected.
  refKindMismatch('TOA104', 'ref-kind-mismatch', .error),

  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
  /// resolves them against the file location instead.
  refBaseIgnored('TOA105', 'ref-base-ignored', .warning),

  /// A key in `components` has characters OpenAPI does not allow there.
  invalidComponentKey('TOA106', 'invalid-component-key', .warning),

  /// A `$ref` where OpenAPI does not accept a Reference Object, as bundlers
  /// such as Redocly allow; it is ignored.
  refNotAllowed('TOA107', 'ref-not-allowed', .warning),

  /// `$ref: #/...` without quotes in YAML: `#` starts a comment, so the
  /// value is null.
  refCommentedOut('TOA108', 'ref-commented-out', .warning),

  /// A YAML 1.1 merge key `<<`, which OpenAPI's YAML does not have; it is
  /// read as a plain key named `<<`.
  yamlMergeKey('TOA109', 'yaml-merge-key', .warning),

  /// An object has a key that no OpenAPI version defines; it is ignored.
  unknownKey('TOA110', 'unknown-key', .warning),

  /// A field has the wrong JSON type or a value the spec does not allow; it
  /// is ignored.
  invalidValue('TOA111', 'invalid-value', .warning),

  /// A field the spec requires is missing.
  missingRequiredField('TOA112', 'missing-required-field', .warning),

  /// A mapping key is a collection, or an alias of one, instead of a
  /// string; the entry is ignored.
  nonStringKey('TOA113', 'non-string-key', .error),

  /// A mapping key is a YAML null (`~`, `null` or empty); it is read as its
  /// text.
  nullKey('TOA114', 'null-key', .warning),

  /// A property schema says `required: true` or `false` (OpenAPI 2 style);
  /// the name is moved into the object's `required` list.
  boolRequired('TOA201', 'bool-required', .warning),

  /// An array has no `items` in an OpenAPI 3.0 document, which requires it.
  arrayWithoutItems('TOA202', 'array-without-items', .warning),

  /// An array's `items` is an array with a boolean `required`: a list
  /// declared twice by a decorator.
  doubleArray('TOA203', 'double-array', .warning),

  /// `format` is on an array without `items` instead of on its elements.
  formatOnArray('TOA204', 'format-on-array', .warning),

  /// `type: object` with `format: binary` instead of a binary string.
  binaryObject('TOA205', 'binary-object', .warning),

  /// `type: object` next to `oneOf`/`anyOf` whose branches are all of other
  /// types.
  contradictoryObjectType('TOA206', 'contradictory-object-type', .warning),

  /// An `example` whose structure the schema does not allow: an object for
  /// an array, or a structure for a scalar and back.
  exampleTypeMismatch('TOA207', 'example-type-mismatch', .warning),

  /// An `example` that is a scalar of another type than the scalar schema,
  /// such as a string for a number; only the documentation is off.
  exampleScalarType('TOA208', 'example-scalar-type', .info),

  /// A schema's `default` is not of the schema's type; it is ignored.
  invalidDefault('TOA211', 'invalid-default', .warning),

  /// A schema allows several JSON types besides `null` (`type: [string,
  /// integer]`); it is generated as `JsonValue`.
  mixedTypeSchema('TOA250', 'mixed-type-schema', .warning),

  /// A schema that is not an object, an enum or a union refers to itself
  /// (`A: {type: array, items: {$ref: A}}`); the reference is generated as
  /// `JsonValue`.
  recursiveAlias('TOA251', 'recursive-alias', .warning),

  /// Two `allOf` parts define the same property with different schemas;
  /// the later part's is used.
  allOfPropertyConflict('TOA252', 'allof-property-conflict', .info),

  /// An `allOf` part is not an object (a scalar, an enum or a union), so it
  /// cannot be merged into a model; it is ignored.
  allOfPartIgnored('TOA253', 'allof-part-ignored', .warning),

  /// A schema an override excludes is used by a generated type; the use is
  /// generated as `JsonValue`. An excluded `allOf` part is the exception: it
  /// is merged into the flat model all the same, and this says so.
  excludedSchemaReferenced('TOA254', 'excluded-schema-referenced', .info),

  /// An object with `properties` has a `oneOf` or `anyOf` whose branches
  /// only add constraints (`required`, `minProperties`, ...); it is
  /// generated as a model and the branches are ignored.
  oneOfConstraintsIgnored('TOA255', 'oneof-constraints-ignored', .info),

  /// Parts, properties or branches of a schema are ignored because another
  /// keyword decides its shape: `allOf` parts or `properties` beside a
  /// `oneOf` or `anyOf` union, or the union's branches when the schema is
  /// a model made of `allOf` parts or `properties`.
  compositionPartsIgnored('TOA256', 'composition-parts-ignored', .warning),

  /// An `enum` repeats a value; the repeats are removed.
  duplicateEnumValue('TOA301', 'duplicate-enum-value', .warning),

  /// A nullable enum written as `oneOf` of an enum of only `null` and a
  /// `$ref`.
  nullableEnumOneOf('TOA303', 'nullable-enum-one-of', .warning),

  /// An enum mixes values of several JSON types, or has objects or lists
  /// among its values; it is generated as `JsonValue`.
  enumMixedValues('TOA350', 'enum-mixed-values', .warning),

  /// `x-enum-varnames` or `x-enum-descriptions` is not a list of strings as
  /// long as the enum; it is ignored.
  enumVarnamesInvalid('TOA351', 'enum-varnames-invalid', .warning),

  /// The discriminator property is not required in a variant.
  discriminatorNotRequired('TOA401', 'discriminator-not-required', .info),

  /// A `discriminator.mapping` value points to a schema that does not
  /// exist.
  discriminatorMappingUnresolved(
    'TOA402',
    'discriminator-mapping-unresolved',
    .error,
  ),

  /// A variant of a union with a discriminator is written inline, so no
  /// discriminator value selects it.
  discriminatorValueMissing('TOA450', 'discriminator-value-missing', .warning),

  /// A `discriminator.mapping` value names a schema that is not a variant of
  /// the union; it is ignored.
  discriminatorMappingNotVariant(
    'TOA451',
    'discriminator-mapping-not-variant',
    .info,
  ),

  /// A `discriminator` sits on a schema that is neither a `oneOf`/`anyOf`
  /// union nor a base other schemas extend with `allOf`: nothing can be
  /// picked by it, so the schema is generated as a model.
  discriminatorWithoutSubtypes(
    'TOA452',
    'discriminator-without-subtypes',
    .info,
  ),

  /// A `oneOf` or `anyOf` without a discriminator has variants of the same
  /// JSON type, or a variant that can hold several (a nested union without a
  /// discriminator), so a value cannot be told apart (R9.2): the
  /// union keeps it as `JsonValue` in one variant (`PetJson`), or, when no
  /// variant has a JSON type of its own, is `JsonValue` itself. An override
  /// `union: structural` (or the config key `union`) generates a union that
  /// tries the variants; a discriminator at the source is better.
  unionUndiscriminated('TOA453', 'union-undiscriminated', .warning),

  /// Two variants of a union have the same Dart type; the later one is
  /// dropped, since a value could not be told apart between them.
  unionVariantDuplicate('TOA454', 'union-variant-duplicate', .info),

  /// A branch of a `oneOf` or `anyOf` without a discriminator is an enum or
  /// a `const` of a primitive type (`string`, `integer`, `number`,
  /// `boolean`) while another branch is that type with no constraint: the
  /// values of the first are values of the second, so the branch is dropped
  /// and, when one branch remains, the union is that type (Stripe's
  /// `anyOf: [string, {enum: ['']}]`). An integer enum next to a plain
  /// `number` is dropped too; a number enum next to an `integer` is not.
  unionBranchSubsumed('TOA455', 'union-branch-subsumed', .info),

  /// Two variants of a union with a discriminator are selected by the same
  /// value (a `const` of the property, a mapping entry or the implicit name):
  /// the earlier variant decodes it, and the later one is never picked by
  /// that value.
  discriminatorValueDuplicate(
    'TOA456',
    'discriminator-value-duplicate',
    .warning,
  ),

  /// A variable of the path template has no path parameter; one is added.
  missingPathParameter('TOA501', 'missing-path-parameter', .warning),

  /// A path parameter is not a variable of the path template, or is one in
  /// another case.
  pathParameterNotInTemplate(
    'TOA502',
    'path-parameter-not-in-template',
    .error,
  ),

  /// An operation has no `operationId`.
  missingOperationId('TOA503', 'missing-operation-id', .info),

  /// Two operations share an `operationId`.
  duplicateOperationId('TOA504', 'duplicate-operation-id', .error),

  /// A name from the spec is a Dart reserved word or a name Dart already
  /// has (`class`, `List`); the generated name gets a suffix.
  nameReserved('TOA550', 'name-reserved', .info),

  /// Two generated declarations, members or arguments would have the same
  /// name; the later one (by spec location) gets a suffix.
  nameCollision('TOA551', 'name-collision', .info),

  /// A name from the spec has no ASCII letter or digit, so no Dart name can
  /// be made from it; a generic name is used.
  nameUnrepresentable('TOA552', 'name-unrepresentable', .warning),

  /// An operation has several tags; it is generated once, in the group of
  /// its first tag.
  operationMultipleTags('TOA553', 'operation-multiple-tags', .info),

  /// An operation has no tag; it is generated in the default group.
  operationUntagged('TOA554', 'operation-untagged', .info),

  /// Two tags differ only in case or separators, so they give one group.
  tagsMerged('TOA555', 'tags-merged', .info),

  /// A variable of the path template has no path parameter with its exact
  /// name (`{ID}` with a parameter `id`); the operation is not generated.
  pathVariableUnbound('TOA556', 'path-variable-unbound', .error),

  /// A tag, `operationId` or path pattern of the config's `include` or
  /// `exclude` matches no operation of the spec.
  filterMatchesNothing('TOA557', 'filter-matches-nothing', .warning),

  /// The config lists the same tag, `operationId` or path pattern in both
  /// `include` and `exclude`; `exclude` wins.
  filterConflict('TOA558', 'filter-conflict', .info),

  /// A name from the spec lost characters when it became a Dart name
  /// (`Größe` became `grE`: letters outside ASCII are dropped). Changes of
  /// case and separators (`my_thing`, `X-Request-ID`) are not reported.
  nameLossy('TOA559', 'name-lossy', .info),

  /// An override `name` (of a schema, property, operation, parameter) or
  /// `group` is not a valid Dart name for what it names (`my thing`, `1x`,
  /// `_private`), or loses characters when it is made one; the name made
  /// from it is used, or the override is ignored when nothing is left. A
  /// `group` that differs from UpperCamelCase only by case or separators
  /// (`pet-store`) is not reported: it is used as `PetStore`.
  overrideNameInvalid('TOA560', 'override-name-invalid', .warning),

  /// A request or response body has a media type that is not JSON, a form,
  /// `multipart/form-data`, `text/*` or `text/event-stream`: it is sent or
  /// read as bytes and its schema is not used. Also reported when an
  /// operation offers several media types of a body and the others are
  /// dropped; the message names the chosen one and the dropped ones.
  mediaTypeAsBytes('TOA561', 'media-type-as-bytes', .info),

  /// `errors.default_schema` names a key that is not in
  /// `components.schemas`; the setting is ignored.
  defaultErrorSchemaMissing(
    'TOA562',
    'default-error-schema-missing',
    .warning,
  ),

  /// No operation of a client is generated: all are filtered out, all are
  /// written as a `$ref` (TOA107), or all have an unbound path variable
  /// (TOA556). The message says why.
  clientEmpty('TOA563', 'client-empty', .warning),

  /// A parameter's `style` is not allowed for its `in` (path takes `simple`,
  /// `label` or `matrix`; query `form`, `spaceDelimited`, `pipeDelimited` or
  /// `deepObject`; header `simple`; cookie `form` or `cookie`), so the default style of
  /// the placement is used. Also reported for an `in: querystring`
  /// parameter (OpenAPI 3.2), which the client cannot send: the parameter
  /// is not generated.
  parameterStyleInvalid('TOA564', 'parameter-style-invalid', .warning),

  /// `*/*` is used as a media type.
  wildcardMediaType('TOA601', 'wildcard-media-type', .warning),

  /// A normalizer fix or an override was not applied: its file cannot be
  /// read, its target is gone, the spec kept changing after the last pass, or
  /// the change would have no effect in the spec's dialect.
  fixNotApplied('TOA800', 'fix-not-applied', .warning),

  /// The overrides file a client names does not exist.
  overridesNotFound('TOA801', 'overrides-not-found', .error),

  /// The overrides file cannot be read, or an override has a value of the
  /// wrong type; the value is ignored.
  invalidOverride('TOA802', 'invalid-override', .error),

  /// An override has a key this tool does not know, such as a misspelled
  /// field; it is ignored.
  unknownOverrideKey('TOA803', 'unknown-override-key', .error),

  /// An override names an operation, a schema, a property, a parameter or a
  /// response the spec does not have; it is not applied.
  overrideTargetNotFound('TOA804', 'override-target-not-found', .warning),

  /// An override's address names more than one node, such as an
  /// `operationId` two operations share; it is not applied.
  overrideTargetAmbiguous('TOA805', 'override-target-ambiguous', .error),

  /// Two overrides change the same node; neither is applied.
  overrideConflict('TOA806', 'override-conflict', .error),

  /// An override sets a value the spec already has; it can be removed.
  overrideUnchanged('TOA807', 'override-unchanged', .info),

  /// An override addressed through an operation changes a node other
  /// operations may share: a path-level parameter, a `$ref`'d component or
  /// a node in another file.
  overrideSharedTarget('TOA808', 'override-shared-target', .info),

  /// An override removes the `type` of a nullable 3.1 schema, so the schema
  /// is no longer nullable: nullability is the `null` in that `type`.
  overrideNullabilityDropped(
    'TOA809',
    'override-nullability-dropped',
    .info,
  ),

  /// The baseline file a client names does not exist.
  baselineNotFound('TOA820', 'baseline-not-found', .error),

  /// The baseline file cannot be read, or an entry is malformed and is
  /// ignored.
  invalidBaseline('TOA821', 'invalid-baseline', .error),

  /// A baseline entry accepts more diagnostics than the check finds: the
  /// problem was fixed, and `baseline prune` can remove the entry.
  baselineEntryStale('TOA822', 'baseline-entry-stale', .warning),

  /// The baseline file cannot be written.
  baselineNotWritten('TOA823', 'baseline-not-written', .error),

  /// `generate` refuses a client's output directory, which it would own:
  /// it holds a `pubspec.yaml`, is the `lib` directory of a package, holds
  /// an input of the run, or holds files but no manifest. Nothing is
  /// written for the client.
  outputNotOwned('TOA830', 'output-not-owned', .error),

  /// `generate` cannot write a client's output directory.
  outputNotWritten('TOA831', 'output-not-written', .error),

  /// The configuration file does not exist.
  configNotFound('TOA901', 'config-not-found', .error),

  /// The configuration file is malformed or has an invalid value.
  configInvalid('TOA902', 'config-invalid', .error),

  /// The configuration file has a key this tool does not know.
  configUnknownKey('TOA903', 'config-unknown-key', .warning),

  /// Two clients write to the same or nested output directories.
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
    ...configCodes,
  };

  /// The stable id, such as `TOA001`.
  final String id;

  /// The human-readable name, such as `parse-error`.
  final String slug;

  /// The severity used unless configuration overrides it.
  final Severity defaultSeverity;
}
