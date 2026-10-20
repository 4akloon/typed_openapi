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
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// Files over their limit, with the number of lines (`wc -l`) they had when
/// they were listed. Keep the entries sorted.
const Map<String, int> _fileAllowlist = {
  // The declarations, enums, the client and its groups; the operation's
  // parameter, body and response nodes have files of their own.
  'lib/src/ir/ir.dart': 477,
  'test/ir/emitter_contract_test.dart': 576,
  'test/ir/ir_builder_test.dart': 970,
  'test/ir/operation_builder_test.dart': 832,
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
  'lib/src/config/config_loader.dart#ConfigLoader.load': 128,
  'lib/src/config/config_reader.dart#ConfigReader.severityAt': 63,
  'lib/src/diagnostics/github_actions_reporter.dart#GitHubActionsReporter.format':
      41,
  // M9: event streams are a reason a client is empty.
  'lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty': 55,
  'lib/src/ir/ir_builder.dart#IrBuilder.build': 93,
  // M9: a parameter keeps its schema's default.
  'lib/src/ir/operation_builder.dart#OperationBuilder._parameter': 100,
  'lib/src/ir/operation_builder.dart#OperationBuilder._parameters': 74,
  'lib/src/ir/operation_selector.dart#OperationSelector.select': 42,
  'lib/src/load/openapi_version.dart#OpenApiVersionDetector.detect': 47,
  'lib/src/normalize/normalizer.dart#Normalizer.normalize': 43,
  'lib/src/normalize/rules/bool_required_to_array.dart#BoolRequiredToArray._cannotTake':
      42,
  'lib/src/normalize/rules/bool_required_to_array.dart#BoolRequiredToArray.check':
      57,
  'lib/src/normalize/rules/path_param_rules.dart#DeclareMissingPathParams.check':
      48,
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
