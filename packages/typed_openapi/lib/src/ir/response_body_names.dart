import 'ir.dart';

/// The names of the declarations that are inline response bodies, by the
/// operation that writes them: a sealed status type may take the plural of
/// its name when the operation's own inline body has it (`GetPetError`).
final class ResponseBodyNames {
  /// Indexes the declarations among [declarations] by name.
  ResponseBodyNames(Iterable<Declaration> declarations) {
    for (final declaration in declarations) {
      (_byName[declaration.name] ??= []).add(declaration);
    }
  }

  final Map<String, List<Declaration>> _byName = {};

  /// Whether a declaration called [name] is written inside the responses of
  /// [operation]. A schema of `components.schemas` is not, whoever uses it,
  /// and neither is an inline body of a shared `components.responses`
  /// entry: it is not the operation's own, so it never takes the plural.
  bool isInlineBodyOf(OperationIr operation, String name) {
    final location = operation.location;
    final responses = '${location.pointer.value}/responses/';
    return (_byName[name] ?? const []).any(
      (declaration) =>
          declaration.location.document == location.document &&
          declaration.location.pointer.value.startsWith(responses),
    );
  }
}
