import '../diagnostics/diagnostic_code.dart';
import 'spec_extension.dart';

/// The registry of the `x-` extensions the generator reads.
///
/// Code that reads or names an extension uses the key from here, so the
/// documentation lists exactly what the generator understands.
abstract final class SpecExtensions {
  /// `x-enum-varnames`: the Dart names of the enum values.
  static const enumVarnames = SpecExtension(
    key: 'x-enum-varnames',
    appliesTo: 'a schema with `enum`',
    effect:
        'Names the enum values, one name per value, in the order of `enum`. '
        'Without it a value is named from its text. A list that is not '
        'strings as long as the enum is ignored.',
    example:
        'type: integer\n'
        'enum: [1, 2]\n'
        'x-enum-varnames: [low, high]',
    diagnostics: [
      DiagnosticCode.enumVarnamesInvalid,
      DiagnosticCode.nameUnrepresentable,
    ],
  );

  /// `x-enum-descriptions`: the doc comments of the enum values.
  static const enumDescriptions = SpecExtension(
    key: 'x-enum-descriptions',
    appliesTo: 'a schema with `enum`',
    effect:
        'Writes one doc comment per enum value, in the order of `enum`; a '
        '`null` entry is no description. A list that is not strings as long '
        'as the enum is ignored.',
    example:
        'type: string\n'
        'enum: [a, b]\n'
        'x-enum-descriptions: [The first, null]',
    diagnostics: [DiagnosticCode.enumVarnamesInvalid],
  );

  /// `x-typed-tri-state`: marks a property as absent, `null` or a value.
  static const triState = SpecExtension(
    key: 'x-typed-tri-state',
    appliesTo: 'a property of a schema',
    effect:
        'With `tri_state: extension` in the config, the property of a '
        'request model distinguishes absent, `null` and a value (a '
        '`Patch<T>`). `true` marks it; any other value does not.',
    example:
        'properties:\n'
        '  nickname:\n'
        '    type: [string, \'null\']\n'
        '    x-typed-tri-state: true',
  );

  /// Every extension, in the order the documentation lists them.
  static const all = [enumVarnames, enumDescriptions, triState];
}
