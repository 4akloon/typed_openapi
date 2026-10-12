import '../model/operation.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';

/// Reads the security requirements of an operation (R10.8) with the schemes
/// they name, as metadata for interceptors.
final class SecurityBuilder {
  /// Creates the builder; it reports through [_context].
  const SecurityBuilder(this._context);

  final IrContext _context;

  /// The security requirements of [operation]: its own, else the
  /// document's. A scheme `components.securitySchemes` does not have is
  /// reported (TOA568) and left out.
  List<List<SecurityUseIr>> of(Operation operation) {
    final requirements =
        operation.security ?? _context.model.document.security ?? const [];
    final schemes = _context.model.document.components?.securitySchemes;
    return [
      for (final requirement in requirements)
        [
          for (final MapEntry(key: name, value: scopes)
              in requirement.schemes.entries)
            if (_scheme(name, schemes, requirement.location) case final s?)
              SecurityUseIr(s, scopes),
        ],
    ];
  }

  SecuritySchemeIr? _scheme(
    String name,
    Map<String, RefOr<SecurityScheme>>? schemes,
    SpecLocation at,
  ) {
    final written = schemes?[name];
    final scheme = written == null ? null : _context.model.resolve(written);
    final type = scheme?.type;
    if (scheme == null || type == null) {
      _context.report(
        .securitySchemeUnknown,
        'The security requirement names "$name", which '
        'components.securitySchemes does not define; it is left out of the '
        'metadata.',
        at,
        fix: 'Define the scheme at the source, or fix its name.',
      );
      return null;
    }
    return SecuritySchemeIr(
      name,
      switch (type) {
        .apiKey => .apiKey,
        .http => .http,
        .mutualTLS => .mutualTls,
        .oauth2 => .oauth2,
        .openIdConnect => .openIdConnect,
      },
      parameterName: type == .apiKey ? scheme.name : null,
      placement: type == .apiKey ? scheme.placement?.name : null,
      scheme: type == .http ? scheme.scheme?.toLowerCase() : null,
      bearerFormat: type == .http ? scheme.bearerFormat : null,
      openIdConnectUrl: type == .openIdConnect ? scheme.openIdConnectUrl : null,
    );
  }
}
