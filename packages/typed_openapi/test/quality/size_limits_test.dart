/// The size limits of `CLAUDE.md` ("Code quality rules") as a ratchet.
///
/// A file in `lib/` has at most 300 lines, a test file 500, a method 40. A
/// unit over its limit may only be here if it is in an allowlist below, with
/// the size it had when it was listed, and it may only shrink: the test fails
/// when a listed unit grows or a new one goes over its limit. A listed unit
/// that shrank or is within its limit again is a stale entry; it does not
/// fail, delete it. Never add a new entry, split the unit instead. The
/// reasoning and the legacy list are in `docs/code-quality-review.md`.
library;

import 'package:test/test.dart';

import '../helpers/size_limits.dart';

/// Files over their limit, with the number of lines (`wc -l`) they had when
/// they were listed. Keep the entries sorted.
const Map<String, int> _fileAllowlist = {
  'lib/src/config/config_loader.dart': 780,
  'lib/src/emit/model_emitter.dart': 379,
  'lib/src/emit/union_emitter.dart': 416,
  'lib/src/generate/output_writer.dart': 896,
  'lib/src/ir/ir.dart': 733,
  'lib/src/ir/ir_builder.dart': 534,
  'lib/src/ir/operation_builder.dart': 565,
  'lib/src/ir/schema_mapper.dart': 2196,
  'lib/src/ir/schema_shapes.dart': 446,
  'lib/src/load/yaml_composer.dart': 810,
  'lib/src/model/operation.dart': 467,
  'lib/src/normalize/normalizer.dart': 383,
  'lib/src/normalize/rules/schema_shape_rules.dart': 341,
  'lib/src/overrides/override_applier.dart': 667,
  'lib/src/overrides/override_loader.dart': 612,
  'lib/src/overrides/override_resolver.dart': 450,
  'lib/src/parse/object_reader.dart': 342,
  'lib/src/parse/operation_parser.dart': 314,
  'test/check/spec_checker_test.dart': 705,
  'test/cli/cli_test.dart': 793,
  'test/cli/generate_command_test.dart': 772,
  'test/emit/model_library_test.dart': 891,
  'test/generate/output_writer_test.dart': 734,
  'test/ir/emitter_contract_test.dart': 576,
  'test/ir/ir_builder_test.dart': 970,
  'test/ir/operation_builder_test.dart': 832,
  'test/ir/schema_mapper_names_test.dart': 562,
  'test/ir/schema_mapper_semantics_test.dart': 857,
  'test/ir/schema_mapper_test.dart': 771,
  'test/ir/union_subsumed_test.dart': 501,
  'test/load/spec_loader_test.dart': 503,
  'test/load/yaml_composer_test.dart': 634,
  'test/overrides/override_applier_test.dart': 1017,
};

/// Files that are exempt for good and are not to be split: a flat catalog
/// with no logic.
const Set<String> _permanent = {'lib/src/diagnostics/diagnostic_code.dart'};

/// Methods over 40 lines (`path#Type.name`, `new` for a constructor), with
/// the lines they had when they were listed. Keep the entries sorted.
const Map<String, int> _methodAllowlist = {
  'lib/src/baseline/anchor_index.dart#AnchorIndex.new': 43,
  'lib/src/baseline/baseline_loader.dart#BaselineLoader._entry': 45,
  'lib/src/baseline/baseline_loader.dart#BaselineLoader._read': 53,
  'lib/src/check/spec_checker.dart#SpecChecker.check': 65,
  'lib/src/cli/generate_command.dart#GenerateCommand.run': 73,
  'lib/src/config/config_loader.dart#ConfigLoader.load': 128,
  'lib/src/config/config_loader.dart#_ConfigReader.severityAt': 63,
  'lib/src/config/config_loader.dart#_GenerationReader._customType': 41,
  'lib/src/diagnostics/github_actions_reporter.dart#GitHubActionsReporter.format':
      41,
  'lib/src/emit/enum_emitter.dart#EnumEmitter.write': 94,
  'lib/src/emit/imports.dart#Imports.write': 48,
  'lib/src/emit/model_emitter.dart#ModelEmitter._fromJson': 46,
  'lib/src/emit/model_emitter.dart#ModelEmitter.write': 57,
  'lib/src/emit/union_emitter.dart#UnionEmitter._byDiscriminator': 61,
  'lib/src/emit/union_emitter.dart#UnionEmitter._byStructure': 41,
  'lib/src/emit/union_emitter.dart#UnionEmitter._variant': 78,
  'lib/src/generate/output_writer.dart#OutputWriter._inspect': 132,
  'lib/src/generate/output_writer.dart#OutputWriter.write': 111,
  'lib/src/ir/ir_builder.dart#IrBuilder._group': 112,
  'lib/src/ir/ir_builder.dart#IrBuilder._methodName': 50,
  'lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty': 50,
  'lib/src/ir/ir_builder.dart#IrBuilder.build': 95,
  'lib/src/ir/operation_builder.dart#OperationBuilder._parameter': 99,
  'lib/src/ir/operation_builder.dart#OperationBuilder._parameters': 74,
  'lib/src/ir/operation_builder.dart#OperationBuilder._pick': 58,
  'lib/src/ir/operation_builder.dart#OperationBuilder._responses': 57,
  'lib/src/ir/operation_selector.dart#OperationSelector.select': 42,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._claim': 66,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._component': 76,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._declare': 93,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._enum': 46,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._jsonKind': 43,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._memberName': 54,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._merged': 77,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._model': 151,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._notesOf': 47,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._structural': 71,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._union': 303,
  'lib/src/ir/schema_mapper.dart#SchemaMapper._valueName': 61,
  'lib/src/load/openapi_version.dart#OpenApiVersionDetector.detect': 47,
  'lib/src/load/yaml_composer.dart#_Composition._alias': 45,
  'lib/src/load/yaml_composer.dart#_Composition._numberValue': 48,
  'lib/src/load/yaml_composer.dart#_Composition._start': 63,
  'lib/src/load/yaml_composer.dart#_Composition.run': 42,
  'lib/src/normalize/normalizer.dart#Normalizer.normalize': 107,
  'lib/src/normalize/rules/bool_required_to_array.dart#BoolRequiredToArray._cannotTake':
      42,
  'lib/src/normalize/rules/bool_required_to_array.dart#BoolRequiredToArray.check':
      57,
  'lib/src/normalize/rules/path_param_rules.dart#DeclareMissingPathParams.check':
      48,
  'lib/src/overrides/override_applier.dart#OverrideApplier._content': 64,
  'lib/src/overrides/override_applier.dart#OverrideApplier._reference': 83,
  'lib/src/overrides/override_applier.dart#OverrideApplier._schema': 55,
  'lib/src/overrides/override_applier.dart#OverrideApplier._typeAndNullable31':
      73,
  'lib/src/overrides/override_loader.dart#_OverrideReader._operation': 44,
  'lib/src/overrides/override_loader.dart#_OverrideReader._schemaSpec': 50,
  'lib/src/overrides/override_resolver.dart#OverrideResolver._operation': 43,
  'lib/src/overrides/override_resolver.dart#OverrideResolver._parameter': 51,
  'lib/src/parse/dialect_checker.dart#DialectChecker.check': 42,
  'lib/src/parse/schema_parser.dart#SchemaParser._object': 75,
  'lib/src/resolve/ref_resolver.dart#RefResolver.resolve': 91,
  'lib/src/resolve/ref_target.dart#RefTarget.parse': 73,
};

void main() {
  final limits = SizeLimits('.');

  test('no file is over its size limit unless it is allowlisted', () {
    final failures = limits.fileFailures(
      allowlist: _fileAllowlist,
      permanent: _permanent,
    );
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });

  test('no method is over 40 lines unless it is allowlisted', () {
    final failures = limits.methodFailures(allowlist: _methodAllowlist);
    if (failures.isNotEmpty) {
      fail(failures.join('\n'));
    }
  });
}
