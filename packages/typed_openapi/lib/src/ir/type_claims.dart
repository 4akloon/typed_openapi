import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';

/// Claims names in the scope of the library's types and reports the ones
/// that are changed (TOA550, TOA551).
final class TypeClaims {
  /// Creates the claims in [_types]; they report through [_context].
  const TypeClaims(this._context, this._types);

  final IrContext _context;
  final NameScope _types;

  /// Whether [name] is given out.
  bool isTaken(String name) => _types.isTaken(name);

  /// Claims [candidate] for [what] in the library scope; a name that
  /// differs is reported at [at], with an override of the operation's name
  /// when [override] is given.
  String claim(
    String candidate,
    String what,
    SpecLocation at, {
    OperationIr? override,
    String? fix,
  }) {
    final (name, change) = _types.claim(candidate);
    if (change == null) return name;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? '"$candidate" is a name Dart already has; $what is named "$name".'
          : 'Another type is named "$candidate"; $what is named "$name".',
      at,
      fix:
          fix ??
          'Rename the other type, or name the operation explicitly: its '
              'name starts the name of the type.',
      override: override == null
          ? null
          : _context.overrideAt(
              ['operations', override.overrideKey],
              {'name': override.name},
            ),
    );
    return name;
  }
}
