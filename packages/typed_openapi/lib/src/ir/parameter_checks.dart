import '../model/operation.dart';
import 'ir_context.dart';
import 'parameter_styles.dart';

/// Checks a parameter before it is generated: whether it can be sent
/// (TOA565) and whether its style is allowed where it is (TOA564).
final class ParameterChecks {
  /// Creates the checks; they report through [_context].
  const ParameterChecks(this._context);

  final IrContext _context;

  /// Whether a parameter of [placement] can be sent; a `querystring`
  /// parameter cannot, and is reported (TOA565).
  bool isSendable(
    ParameterLocation placement,
    Parameter parameter,
    String wire,
  ) {
    if (placement != .querystring) return true;
    _context.report(
      .querystringNotGenerated,
      'Parameter "$wire" is in: querystring (OpenAPI 3.2), which the client '
      'cannot send; the parameter is not generated.',
      parameter.location,
      fix: 'Describe the query string as query parameters at the source.',
    );
    return false;
  }

  /// The style of [parameter] as the IR keeps it: what the spec writes when
  /// its placement allows it, else null (the default style of the
  /// placement), with TOA564.
  ParameterStyle? checkedStyle(
    Parameter parameter,
    ParameterLocation placement,
    String wire,
  ) {
    final style = parameter.style;
    final allowed = ParameterStyles.allowed[placement];
    if (style == null || allowed == null || allowed.contains(style)) {
      return style;
    }
    final fallback = allowed.first;
    _context.report(
      .parameterStyleInvalid,
      'The style "${style.name}" is not allowed for a ${placement.name} '
      'parameter, which takes '
      '${[for (final s in allowed) '"${s.name}"'].join(', ')}; the default '
      'style "${fallback.name}" is used for "$wire".',
      parameter.location,
      fix: 'Use one of these styles at the source.',
    );
    return null;
  }
}
