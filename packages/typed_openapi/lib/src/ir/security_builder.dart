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
  /// document's. The metadata never says less than the spec: a scheme
  /// `components.securitySchemes` does not define is reported (TOA568), and
  /// an alternative that names one is left out as a whole when another
  /// alternative can be described; when none can, every alternative stays
  /// and the scheme has the kind [SecurityKind.unknown], so the operation
  /// is never read as open (no alternative) or as optional (an empty one).
  List<List<SecurityUseIr>> of(Operation operation) {
    final requirements =
        operation.security ?? _context.model.document.security ?? const [];
    final schemes = _context.model.document.components?.securitySchemes;
    final read = [
      for (final requirement in requirements)
        _Alternative(requirement.location, [
          for (final MapEntry(key: name, value: scopes)
              in requirement.schemes.entries)
            (
              name: name,
              scopes: scopes,
              scheme: _scheme(name, schemes),
              isDefined: _isDefined(name, schemes),
            ),
        ]),
    ];
    final complete = [
      for (final alternative in read)
        if (alternative.isComplete) alternative,
    ];
    final isDropped = complete.isNotEmpty;
    for (final alternative in read) {
      _reportUnknown(alternative, isDropped: isDropped);
    }
    return [
      for (final alternative in isDropped ? complete : read) alternative.uses,
    ];
  }

  void _reportUnknown(_Alternative alternative, {required bool isDropped}) {
    final outcome = isDropped
        ? 'its alternative is left out of the metadata, which keeps the '
              'alternatives that can be described'
        : 'the metadata has it as an unknown scheme, so the operation is not '
              'read as open';
    for (final entry in alternative.entries) {
      if (entry.scheme != null) continue;
      final problem = entry.isDefined
          ? 'whose scheme in components.securitySchemes has no usable type'
          : 'which components.securitySchemes does not define';
      _context.report(
        .securitySchemeUnknown,
        'The security requirement names "${entry.name}", $problem; $outcome.',
        alternative.location,
        fix: entry.isDefined
            ? 'Give the scheme a valid type at the source.'
            : 'Define the scheme at the source, or fix its name.',
      );
    }
  }

  bool _isDefined(String name, Map<String, RefOr<SecurityScheme>>? schemes) {
    final written = schemes?[name];
    return written != null && _context.model.resolve(written) != null;
  }

  SecuritySchemeIr? _scheme(
    String name,
    Map<String, RefOr<SecurityScheme>>? schemes,
  ) {
    final written = schemes?[name];
    final scheme = written == null ? null : _context.model.resolve(written);
    final type = scheme?.type;
    if (scheme == null || type == null) return null;
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

/// The schemes of one security requirement (an alternative), each with its
/// scopes and the scheme it names, null when that is not defined.
final class _Alternative {
  const _Alternative(this.location, this.entries);

  final SpecLocation location;
  final List<
    ({
      String name,
      List<String> scopes,
      SecuritySchemeIr? scheme,
      bool isDefined,
    })
  >
  entries;

  /// Whether every scheme it names is defined.
  bool get isComplete => entries.every((entry) => entry.scheme != null);

  /// The schemes with their scopes; one that is not defined is unknown.
  List<SecurityUseIr> get uses => [
    for (final (:name, :scopes, :scheme, isDefined: _) in entries)
      SecurityUseIr(scheme ?? SecuritySchemeIr(name, .unknown), scopes),
  ];
}
