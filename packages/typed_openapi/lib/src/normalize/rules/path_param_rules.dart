import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../../model/spec_node.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// The path templates of a spec with their path items, as both path rules
/// read them.
final class _PathTemplates {
  _PathTemplates(this.context);

  final RuleContext context;

  static final _variable = RegExp(r'\{([^{}]+)\}');

  /// Every templated path with its resolved path item, in document order.
  Iterable<(String, PathItem)> get paths sync* {
    for (final MapEntry(key: template, value: item)
        in context.model.document.paths.entries) {
      final resolved = context.model.resolve(item);
      if (resolved != null) yield (template, resolved);
    }
  }

  /// The variables of [template], in order, each once.
  static List<String> variablesOf(String template) => [
    ...{for (final m in _variable.allMatches(template)) m.group(1)!},
  ];

  /// The path parameters among [parameters], with where each is written.
  List<(Parameter, SpecLocation)> pathParameters(
    List<RefOr<Parameter>> parameters,
  ) => [
    for (final parameter in parameters)
      if (context.model.resolve(parameter) case final resolved?
          when resolved.placement == .path && resolved.name != null)
        (resolved, _siteOf(parameter, resolved)),
  ];

  /// Whether one of [parameters] is a `$ref` that does not resolve: which
  /// path parameters there are is not known then (TOA101 reports it).
  bool hasUnresolved(List<RefOr<Parameter>> parameters) =>
      parameters.any((p) => context.model.resolve(p) == null);

  static SpecLocation _siteOf(RefOr<Parameter> written, Parameter resolved) =>
      switch (written) {
        Ref() => written.location,
        Inline() => resolved.location,
      };
}

/// A variable of the path template without a declared path parameter (C-6)
/// gets `{name, in: path, required: true, schema: {type: string}}` in each
/// operation that lacks it: a path segment is a string on the wire.
final class DeclareMissingPathParams extends NormalizerRule {
  /// Creates the rule.
  const DeclareMissingPathParams();

  @override
  String get name => 'declare-missing-path-params';

  @override
  List<DiagnosticCode> get codes => const [.missingPathParameter];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final templates = _PathTemplates(context);
    for (final (template, item) in templates.paths) {
      final variables = _PathTemplates.variablesOf(template);
      if (variables.isEmpty || templates.hasUnresolved(item.parameters)) {
        continue;
      }
      final shared = {
        for (final (p, _) in templates.pathParameters(item.parameters)) p.name,
      };
      for (final operation in item.operations.values) {
        // An operation written as a `$ref` is TOA107 already; it is empty.
        if (operation.unknownKeys.containsKey(r'$ref')) continue;
        // With a parameter that cannot be read, a name may be declared that
        // looks missing; nothing is added to guess.
        if (templates.hasUnresolved(operation.parameters)) continue;
        final declared = {
          ...shared,
          for (final (p, _) in templates.pathParameters(operation.parameters))
            p.name,
        };
        final lowered = {for (final n in declared) n!.toLowerCase()};
        // A name that differs only in case is PathParamNotInTemplate's
        // finding; adding a parameter would hide it.
        final missing = [
          for (final v in variables)
            if (!declared.contains(v) && !lowered.contains(v.toLowerCase())) v,
        ];
        if (missing.isEmpty) continue;
        // One finding per operation: a fix is one edit of its parameters.
        final names = missing.map((m) => '"$m"').join(', ');
        final added = missing.length == 1
            ? 'it is added as a required string path parameter'
            : 'they are added as required string path parameters';
        yield context.finding(
          .missingPathParameter,
          'The path $template has ${missing.map((m) => '{$m}').join(', ')}, '
          'but this operation declares no path parameter $names; '
          '$added.',
          operation.location,
          fix:
              'Declare each at the source as {name: <name>, in: path, '
              'required: true, schema: {type: string}}.',
          edits: [_edit(context, operation, missing)],
        );
      }
    }
  }

  /// One edit that adds every parameter of [names] to [operation].
  static SpecEdit _edit(
    RuleContext context,
    Operation operation,
    List<String> names,
  ) {
    final at = operation.location.child('parameters');
    final added = [
      for (final name in names)
        {
          'name': name,
          'in': 'path',
          'required': true,
          'schema': {'type': 'string'},
        },
    ];
    return switch (context.rawAt(at)) {
      (final List<Object?> existing,) => SpecEdit.replace(at, [
        ...existing,
        ...added,
      ]),
      _ => SpecEdit.add(at, added),
    };
  }
}

/// A declared path parameter that is not a variable of the path template,
/// or is one in another case (C-7). Which name is right cannot be told, so
/// this is a diagnostic only.
final class PathParamNotInTemplate extends NormalizerRule {
  /// Creates the rule.
  const PathParamNotInTemplate();

  @override
  String get name => 'path-param-not-in-template';

  @override
  List<DiagnosticCode> get codes => const [.pathParameterNotInTemplate];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final templates = _PathTemplates(context);
    for (final (template, item) in templates.paths) {
      final variables = _PathTemplates.variablesOf(template);
      final parameters = [
        ...templates.pathParameters(item.parameters),
        for (final operation in item.operations.values)
          ...templates.pathParameters(operation.parameters),
      ];
      for (final (parameter, site) in parameters) {
        final name = parameter.name!;
        if (variables.contains(name)) continue;
        final other = variables
            .where((v) => v.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        yield context.finding(
          .pathParameterNotInTemplate,
          'Path parameter "$name" is not in the path template $template'
          '${other == null ? '' : ', which writes it as {$other}'}.',
          site,
          fix:
              'Make the parameter name and the template variable the same at '
              'the source; until then, override the name of this parameter.',
        );
      }
    }
  }
}
