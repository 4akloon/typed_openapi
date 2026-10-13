import '../model/spec_node.dart';
import 'ir.dart' show ModelDirection;

/// What mapping a schema depends on besides the schema itself, passed down
/// with every call instead of being set in a field before it.
final class MappingScope {
  /// The scope of a mapping in [direction]; [patchTarget] is the schema of a
  /// PATCH request body that has not got its declaration yet.
  const MappingScope({this.direction = .both, this.patchTarget})
    : replacing = false;

  const MappingScope._(this.direction, this.patchTarget, this.replacing);

  /// Where the models mapped are used.
  final ModelDirection direction;

  /// The location of the PATCH body schema whose declaration is still to be
  /// made: that declaration is the one that may get a model of its own.
  final SpecLocation? patchTarget;

  /// Whether the schema being mapped is replaced by a custom type, so only
  /// the JSON side of it is wanted: nothing is declared, reported or
  /// replaced again (R4.2, R6.8).
  final bool replacing;

  /// This scope for a schema a custom type replaces.
  MappingScope replaced() => MappingScope._(direction, patchTarget, true);

  /// This scope once the declaration of the PATCH body is reached: what is
  /// mapped below it is no PATCH body any more.
  MappingScope withoutPatchTarget() =>
      MappingScope._(direction, null, replacing);
}
