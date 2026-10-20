import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../normalizer_rule.dart';

/// An operation without `operationId` (C-34): the generator has to name its
/// method after the HTTP method and path.
final class MissingOperationId extends NormalizerRule {
  /// Creates the rule.
  const MissingOperationId();

  @override
  String get name => 'missing-operation-id';

  @override
  List<DiagnosticCode> get codes => const [.missingOperationId];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final operation in context.nodes<Operation>()) {
      // An operation written as a `$ref` is TOA107 already; it is empty.
      if (operation.operationId != null ||
          operation.unknownKeys.containsKey(r'$ref')) {
        continue;
      }
      yield context.finding(
        .missingOperationId,
        'This operation has no "operationId", so its method is named after '
        'the HTTP method and the path.',
        operation.location,
        fix:
            'Add an operationId at the source, or override the method name of '
            'this operation.',
        backendFix: 'Add an operationId at the source.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      'In ASP.NET, name the endpoint: .WithName("getUser") or '
          '[EndpointName("getUser")]; with Swashbuckle, '
          'CustomOperationIds(api => api.TryGetMethodInfo(out var mi) ? '
          'mi.Name : null).',
    _ => null,
  };
}

/// Operations that share an `operationId` (C-36); which one keeps the name
/// cannot be told, so this is a diagnostic only.
final class DuplicateOperationId extends NormalizerRule {
  /// Creates the rule.
  const DuplicateOperationId();

  @override
  String get name => 'duplicate-operation-id';

  @override
  List<DiagnosticCode> get codes => const [.duplicateOperationId];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final first = <String, Operation>{};
    for (final operation in context.nodes<Operation>()) {
      final id = operation.operationId;
      if (id == null) continue;
      final earlier = first[id];
      if (earlier == null) {
        first[id] = operation;
        continue;
      }
      final where = earlier.location.document == operation.location.document
          ? earlier.pointer.value
          : '${context.documents.displayPath(earlier.location.document)}'
                '${earlier.pointer.value}';
      yield context.finding(
        .duplicateOperationId,
        'operationId "$id" is also the id of the operation at $where; method '
        'names would clash.',
        operation.location.child('operationId'),
        fix:
            'Give each operation its own operationId at the source. To '
            'generate anyway, lower TOA504 in the client\'s severity and pin '
            'the second method\'s name with an override.',
        backendFix: 'Give each operation its own operationId at the source.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, set `operationIdFactory` in SwaggerModule.createDocument '
          '(the default is controllerKey_methodKey).',
    .fastapi =>
      'In FastAPI, pass `generate_unique_id_function` to FastAPI(...).',
    .springdoc =>
      'In springdoc, set @Operation(operationId = "...") explicitly; springdoc '
          'adds a _1 suffix to an operationId it finds twice.',
    _ => null,
  };
}
