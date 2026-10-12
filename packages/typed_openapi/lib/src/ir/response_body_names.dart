import 'ir.dart';

/// The names of the declarations that are inline response bodies, by the
/// operation that writes them: a sealed status type may take the plural of
/// its name when the operation's own inline body has it (`GetPetError`).
final class ResponseBodyNames {
  /// Indexes the inline response bodies among [declarations].
  ResponseBodyNames(Iterable<Declaration> declarations)
    : _declarations = declarations.toList();

  final List<Declaration> _declarations;

  /// Whether a declaration called [name] is written inside the responses of
  /// [operation]. A schema of `components.schemas` is not, whoever uses it.
  bool isInlineBodyOf(OperationIr operation, String name) {
    final location = operation.location;
    final responses = '${location.pointer.value}/responses/';
    return _declarations.any(
      (declaration) =>
          declaration.name == name &&
          declaration.location.document == location.document &&
          declaration.location.pointer.value.startsWith(responses),
    );
  }
}
