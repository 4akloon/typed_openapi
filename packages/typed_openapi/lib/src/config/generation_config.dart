import 'dart:convert';

import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import '../overrides/override_set.dart';

/// How operations are put into API classes (R5.3).
enum GroupBy {
  /// A class per tag; an operation goes to its first tag's class.
  tag,

  /// A class per first segment of the path.
  path,

  /// One class.
  single,
}

/// Which request body properties tell "absent" from `null` (R7.2).
enum TriStateRule {
  /// Optional nullable properties of PATCH request bodies.
  patch,

  /// Every optional property of PATCH request bodies.
  optional,

  /// Properties with `x-typed-tri-state: true`.
  extension,
}

/// A pattern of an `include` or `exclude` filter, with where the config
/// has it.
final class FilterPattern {
  /// Creates a pattern.
  const FilterPattern(this.value, this.pointer, [this.span]);

  /// The tag, `operationId` or path glob.
  final String value;

  /// Where the pattern is in the config file.
  final JsonPointer pointer;

  /// The source range of the pattern.
  final SourceSpan? span;
}

/// An `include` or `exclude` filter of operations (R4.1).
final class OperationFilter {
  /// Creates a filter.
  const OperationFilter({
    this.tags = const [],
    this.operations = const [],
    this.paths = const [],
  });

  /// Tags, as in the spec.
  final List<FilterPattern> tags;

  /// `operationId`s.
  final List<FilterPattern> operations;

  /// Path templates with `*` (one segment) and `**` (any segments).
  final List<FilterPattern> paths;

  /// Whether the filter has no pattern.
  bool get isEmpty => tags.isEmpty && operations.isEmpty && paths.isEmpty;

  /// The patterns, as plain values.
  Map<String, Object?> toJson() => {
    for (final (key, patterns) in [
      ('tags', tags),
      ('operations', operations),
      ('paths', paths),
    ])
      if (patterns.isNotEmpty) key: [for (final p in patterns) p.value],
  };
}

/// What the config says about generating a client: names, groups, filters,
/// types and the tri-state rule.
final class GenerationConfig {
  /// Creates a generation config; every field has a default.
  const GenerationConfig({
    this.groupTemplate = defaultGroupTemplate,
    this.defaultGroup = defaultDefaultGroup,
    this.inputSuffix = defaultInputSuffix,
    this.patchSuffix = defaultPatchSuffix,
    this.operationPrefix,
    this.groupBy = .tag,
    this.include = const OperationFilter(),
    this.exclude = const OperationFilter(),
    this.numberType,
    this.formats = const {},
    this.schemas = const {},
    this.triState = .patch,
    this.defaultErrorSchema,
    this.file,
    this.client,
    this.clientSpan,
  });

  /// The default of [groupTemplate].
  static const defaultGroupTemplate = '{Tag}Api';

  /// The default of [defaultGroup].
  static const defaultDefaultGroup = 'DefaultApi';

  /// The default of [inputSuffix].
  static const defaultInputSuffix = 'Input';

  /// The default of [patchSuffix].
  static const defaultPatchSuffix = 'Patch';

  /// `naming.group`: the class name of a group, with `{Tag}` for the
  /// group's name in UpperCamelCase.
  final String groupTemplate;

  /// `naming.default_group`: the class of operations without a group.
  final String defaultGroup;

  /// `naming.input_suffix`: appended to the name of the request model of a
  /// schema split by direction.
  final String inputSuffix;

  /// `naming.patch_suffix`: appended to the name of the PATCH body model of
  /// a schema that is also used elsewhere.
  final String patchSuffix;

  /// `naming.operation_prefix`: a pattern removed from the start of an
  /// `operationId` before it becomes a method name.
  ///
  /// It is applied only where its match starts at index 0 and is not empty:
  /// `^v1_` and `v1_` both turn `v1_list` into `list`, but `users_v1_list`
  /// is left as it is, and so is every id when the pattern can match the
  /// empty string (`.*`) and does not match anything at the start.
  final RegExp? operationPrefix;

  /// `group_by`.
  final GroupBy groupBy;

  /// `include`: when not empty, only matching operations are generated.
  final OperationFilter include;

  /// `exclude`: matching operations are not generated.
  final OperationFilter exclude;

  /// `types.number`: the Dart type of `number` without a format: `num`
  /// (null), `double` or `int`.
  final String? numberType;

  /// `types.formats`: custom types by `format`.
  final Map<String, DartTypeOverride> formats;

  /// `types.schemas`: custom types by `components.schemas` key.
  final Map<String, DartTypeOverride> schemas;

  /// `tri_state`.
  final TriStateRule triState;

  /// `errors.default_schema`: the `components.schemas` key of the body of
  /// error responses that document none.
  final String? defaultErrorSchema;

  /// The config file, as diagnostics name it.
  final String? file;

  /// Where the client is in the config file (`#/clients/<name>`); null for
  /// a config made in code.
  final JsonPointer? client;

  /// The source range of the client's entry in the config file.
  final SourceSpan? clientSpan;

  /// The settings as one string: two clients with equal keys generate the
  /// same IR from the same spec.
  ///
  /// The order in which `types.formats` and `types.schemas` are written does
  /// not matter. A client with an `include` or `exclude` filter has its own
  /// key, so that the diagnostics about its patterns (TOA557, TOA558) and
  /// about an empty client (TOA563) are reported at its own place in the
  /// config, not at the place of another client that has the same settings.
  String get key => jsonEncode({
    'group': groupTemplate,
    'default_group': defaultGroup,
    'input_suffix': inputSuffix,
    'patch_suffix': patchSuffix,
    'operation_prefix': operationPrefix?.pattern,
    'group_by': groupBy.name,
    'include': include.toJson(),
    'exclude': exclude.toJson(),
    'client': include.isEmpty && exclude.isEmpty ? null : client?.value,
    'number': numberType,
    'formats': _sorted(formats),
    'schemas': _sorted(schemas),
    'tri_state': triState.name,
    'default_schema': defaultErrorSchema,
  });

  static Map<String, Object?> _sorted(Map<String, DartTypeOverride> types) => {
    for (final name in types.keys.toList()..sort())
      name: [types[name]!.type, types[name]!.import, types[name]!.converter],
  };
}
