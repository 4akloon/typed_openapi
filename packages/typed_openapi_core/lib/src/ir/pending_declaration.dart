import 'dart_type.dart';
import 'ir.dart';
import 'names.dart';

/// How an inline schema's declaration is named (R5.4): after its parent
/// declaration or a fixed prefix (an operation), followed by [suffix].
final class NameHint {
  /// A name made of [prefix] and [suffix], such as `CreatePet` + `Request`.
  const NameHint(String this.prefix, this.suffix) : parent = null;

  /// A name made of the name of the declaration [parent] and [suffix].
  const NameHint.under(PendingDeclaration this.parent, this.suffix)
    : prefix = null;

  /// The fixed start of the name, when there is no parent declaration.
  final String? prefix;

  /// The end of the name, such as a property name in UpperCamelCase.
  final String suffix;

  /// The declaration the name is made after, when there is no [prefix].
  final PendingDeclaration? parent;
}

/// A declaration whose name is not given yet.
final class PendingDeclaration {
  /// A declaration with identity [id], to be filled in by the mapper.
  PendingDeclaration(this.id);

  /// The identity of the declaration.
  final DeclId id;

  /// The `components.schemas` key, for a component's declaration.
  String? componentKey;

  /// The name an override gives, valid.
  String? overrideName;

  /// How an inline declaration is named.
  NameHint? hint;

  /// How many parents the name hints lead through.
  int depth = 0;

  /// Whether this is the model of a PATCH body, whose fields follow the
  /// tri-state rule.
  bool patchBody = false;

  /// The name, once it is claimed.
  String? name;

  /// Builds the declaration once its [name] is claimed in [scope].
  late Declaration Function(String name, NameScope scope) build;

  /// The JSON type of every value of the declaration: an object for a
  /// model and a union with a discriminator, the type of an enum's values;
  /// null for a union that may hold values of several types.
  JsonKind? jsonKind;

  /// Overridden names are claimed first, then component keys, then inline
  /// names.
  int get rank => overrideName != null
      ? 0
      : componentKey != null
      ? 1
      : 2;
}
