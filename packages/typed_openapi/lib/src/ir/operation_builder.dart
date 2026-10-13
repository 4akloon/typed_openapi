import '../model/operation.dart';
import '../model/path_template.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'media_type_picker.dart';
import 'method_builder.dart';
import 'names.dart';
import 'parameter_checks.dart';
import 'schema_defaults.dart';
import 'schema_mapper.dart';
import 'spec_operation.dart';

export 'spec_operation.dart';

/// Builds the IR of operations: their parameters here (R10.3), and through
/// a [MethodBuilder] their methods with bodies, responses and errors
/// (R10.4, R10.6, R11.4, R12.1); types come from a [SchemaMapper].
final class OperationBuilder {
  /// Creates a builder that maps types with [_mapper].
  OperationBuilder(this._context, this._mapper)
    : _parameterChecks = ParameterChecks(_context),
      _methods = MethodBuilder(_context, _mapper),
      _defaults = SchemaDefaults(_context),
      _picker = MediaTypePicker(_context);

  static const _names = DartNames();

  /// The header parameters OpenAPI says to ignore: the request's own
  /// `Accept`, `Content-Type` and `Authorization` (compared in lower case).
  static const _ignoredHeaders = {'accept', 'content-type', 'authorization'};

  final IrContext _context;
  final SchemaMapper _mapper;
  final ParameterChecks _parameterChecks;
  final MethodBuilder _methods;
  final SchemaDefaults _defaults;
  final MediaTypePicker _picker;

  /// How many operations [build] left out because their event streams
  /// cannot be expressed (TOA654).
  int streams = 0;

  /// How many operations [build] left out because a path variable has no
  /// parameter (TOA556).
  int unbound = 0;

  /// The methods of [entry], named [name]: one, or for an operation that
  /// returns JSON or an event stream also one that returns the events,
  /// named in the group's [methods] (TOA663). Empty when its path template
  /// cannot be filled (counted in [unbound]) or its event streams cannot be
  /// expressed (in [streams]).
  List<OperationIr> build(
    SpecOperation entry,
    String name,
    NameScope methods,
  ) {
    final parameters = _parameters(entry, _names.pascal(name) ?? name);
    if (parameters == null) {
      unbound++;
      return const [];
    }
    final built = _methods.of(entry, name, parameters, methods);
    if (built.isEmpty) streams++;
    return built;
  }

  List<ParameterIr>? _parameters(SpecOperation entry, String prefix) {
    // Operation parameters replace path item parameters with the same name
    // and location.
    final byKey =
        <(ParameterLocation, String?), (ParameterLocation, Parameter)>{};
    for (final written in [
      ...entry.item.parameters,
      ...entry.operation.parameters,
    ]) {
      final parameter = _context.model.resolve(written);
      // A parameter without a valid `in` is not generated; the parser has
      // reported it (TOA111, TOA112).
      final placement = parameter?.placement;
      if (parameter == null || placement == null) continue;
      // OpenAPI says these headers SHALL be ignored: the HTTP client and
      // the body's media type decide them.
      if (placement == .header &&
          _ignoredHeaders.contains(parameter.name?.toLowerCase())) {
        continue;
      }
      byKey[(placement, parameter.name)] = (placement, parameter);
    }
    final variables = [
      for (final match in PathTemplate(entry.path).variables) match[1]!,
    ];
    var bound = true;
    for (final variable in variables) {
      if (byKey.containsKey((ParameterLocation.path, variable))) continue;
      bound = false;
      _context.report(
        .pathVariableUnbound,
        'Path variable "{$variable}" of ${entry.path} has no path parameter '
        'with this exact name, so the operation is not generated.',
        entry.operation.location,
        fix: 'Declare a path parameter named "$variable" at the source.',
      );
    }
    if (!bound) return null;
    final scope = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.argumentNames},
      reservedSuffix: '_',
    );
    const order = [
      ParameterLocation.path,
      ParameterLocation.query,
      ParameterLocation.querystring,
      ParameterLocation.header,
      ParameterLocation.cookie,
    ];
    // By location, then in the order of the spec (a sort is not stable).
    final sorted = byKey.values.toList().indexed.toList()
      ..sort((a, b) {
        final byPlacement = order.indexOf(a.$2.$1) - order.indexOf(b.$2.$1);
        return byPlacement != 0 ? byPlacement : a.$1 - b.$1;
      });
    final named = [
      for (final (_, (placement, parameter)) in sorted)
        if (parameter.name case final wire?)
          if (_parameterChecks.isSendable(placement, parameter, wire))
            (placement, parameter, wire),
    ];
    // The names overrides give are claimed first, so an automatic name that
    // is the same gets the suffix, not the override's.
    final built = <int, ParameterIr>{};
    for (final withOverride in [true, false]) {
      for (final (i, (placement, parameter, wire)) in named.indexed) {
        final given =
            _context.overrides.parameterAt(parameter.location)?.name != null;
        if (given != withOverride) continue;
        built[i] = _parameter(entry, parameter, placement, wire, scope, prefix);
      }
    }
    return [for (var i = 0; i < named.length; i++) built[i]!];
  }

  ParameterIr _parameter(
    SpecOperation entry,
    Parameter parameter,
    ParameterLocation placement,
    String wire,
    NameScope scope,
    String prefix,
  ) {
    final override = _context.overrides.parameterAt(parameter.location);
    final written = override?.name;
    final given = written == null
        ? null
        : _context.checkedOverrideName(
            override!,
            'name',
            written,
            .member,
            what: 'argument',
          );
    final automatic = given == null ? _names.camel(wire) : null;
    final candidate = given ?? automatic ?? 'param';
    final (name, change) = scope.claim(
      candidate,
      alternatives: ['$candidate${_names.pascal(placement.name)}'],
    );
    final address = [
      'operations',
      entry.overrideKey,
      'parameters',
      '${placement.name}:$wire',
    ];
    if (given == null && automatic == null) {
      _context.report(
        .nameUnrepresentable,
        'Parameter "$wire" has no ASCII letter or digit; the argument is '
        'named "$name".',
        parameter.location,
        fix: 'Name the argument explicitly.',
        override: _context.overrideAt(address, {'name': 'argument'}),
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Parameter "$wire" would be the Dart name "$candidate"; the '
                  'argument is named "$name".'
            : 'Another argument of ${entry.overrideKey} is named '
                  '"$candidate"; the argument of ${placement.name} parameter '
                  '"$wire" is named "$name".',
        parameter.location,
        fix: 'Name the argument explicitly to keep the name stable.',
        override: _context.overrideAt(address, {'name': name}),
      );
    }
    if (given == null && automatic != null) {
      _context.checkLossyName(
        wire,
        name,
        parameter.location,
        what: 'Parameter',
        override: _context.overrideAt(address, {'name': name}),
      );
    }
    final (schema, contentType) = switch (parameter.schema) {
      final schema? => (schema, null),
      null => _picker.content(parameter.content, parameter.location),
    };
    final mapped = schema == null
        ? const CoreType(.json)
        : _mapper.typeOf(
            schema,
            NameHint(prefix, _names.pascal(wire) ?? ''),
            direction: .request,
          );
    final custom = override?.dartType;
    final type = custom == null
        ? mapped
        : CustomType(
            type: custom.type,
            import: custom.import,
            converter: custom.converter,
            json: mapped.withNullable(false),
          );
    final required = placement == .path || parameter.required;
    return ParameterIr(
      name: name,
      wireName: wire,
      placement: placement,
      type: required ? type : type.withNullable(true),
      location: parameter.location,
      required: required,
      style: _parameterChecks.checkedStyle(parameter, placement, wire),
      explode: parameter.explode,
      allowReserved: parameter.allowReserved,
      contentType: contentType,
      description: parameter.description,
      deprecated: parameter.deprecated,
      defaultValue: _defaults.of(schema),
    );
  }
}
