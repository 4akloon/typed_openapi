import '../model/schema.dart';
import '../model/spec_node.dart';
import 'declaration_names.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'mapping_state.dart';
import 'mapping_tools.dart';
import 'names.dart';
import 'override_notices.dart';
import 'pending_declaration.dart';

/// Turns an enum schema into an [EnumDecl]: its kind, the labels the spec
/// gives its values, and the names of its values (R6.2).
final class EnumMapper {
  /// An enum mapper that reports through [tools].
  EnumMapper(MappingTools tools)
    : _context = tools.context,
      _declNames = tools.names,
      _notices = tools.notices;

  static const _names = DartNames();
  static final _numberText = RegExp(r'^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$');

  final IrContext _context;
  final DeclarationNames _declNames;
  final OverrideNotices _notices;

  /// The `x-enum-varnames` and `x-enum-descriptions` of the enum [schema]
  /// with [values]: a list of strings with one entry per value, or null when
  /// the extension is missing or malformed (TOA351); a description may be
  /// `null`, which is no description. An enum that has `null` among its
  /// written values may list it too.
  (List<String>?, List<String?>?) labels(
    SchemaObject schema,
    List<Object?> values,
  ) => (
    _labelsOf(schema, values, 'x-enum-varnames')?.cast<String>(),
    _labelsOf(schema, values, 'x-enum-descriptions', allowNull: true),
  );

  List<String?>? _labelsOf(
    SchemaObject schema,
    List<Object?> values,
    String key, {
    bool allowNull = false,
  }) {
    final written = schema.extensions[key];
    if (written == null) return null;
    final all = schema.enumValues;
    if (written is List<Object?> &&
        written.every((e) => e is String || (allowNull && e == null))) {
      final strings = written.cast<String?>();
      if (strings.length == values.length) return strings;
      if (all != null && strings.length == all.length) {
        return [
          for (final (i, value) in all.indexed)
            if (value != null) strings[i],
        ];
      }
    }
    _context.report(
      .enumVarnamesInvalid,
      '$key must be a list of strings with one entry per enum value '
      '(${values.length}); it is ignored.',
      schema.location.child(key),
      fix: 'Write one string for each value of the enum at the source.',
    );
    return null;
  }

  /// Sets how [pending], the declaration of the enum [schema] described by
  /// [draft], is built once it is named.
  void declare(
    SchemaObject schema,
    PendingDeclaration pending,
    EnumDraft draft,
  ) {
    _notices.unionHasNoEffect(schema, 'the schema is an enum, not a union');
    pending.build = (name, types) =>
        _build(schema, pending, draft, name, types);
  }

  EnumDecl _build(
    SchemaObject schema,
    PendingDeclaration pending,
    EnumDraft draft,
    String name,
    NameScope types,
  ) {
    return EnumDecl(
      id: pending.id,
      name: name,
      kind: draft.kind,
      exhaustive:
          _context.overrides.schemaAt(schema.location)?.exhaustive ?? true,
      knownName: _declNames.helperName(
        types,
        '${name}Known',
        pending,
        'the enum of the known values of $name',
      ),
      unknownName: _declNames.helperName(
        types,
        '${name}Unknown',
        pending,
        'the class of an unknown value of $name',
      ),
      description: schema.description,
      deprecated: schema.deprecated,
      values: _values(schema, draft, name),
    );
  }

  List<EnumValueIr> _values(
    SchemaObject schema,
    EnumDraft draft,
    String owner,
  ) {
    final scope = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.enumMembers},
      reservedSuffix: '_',
    );
    return [
      for (final (i, value) in draft.values.indexed)
        EnumValueIr(
          _valueName(scope, draft.names?[i], value!, schema.location, owner),
          value,
          description: draft.descriptions?[i],
        ),
    ];
  }

  /// The name of the enum value [value] of [owner]: from its
  /// `x-enum-varnames` entry [named], else from the value. A number, or a
  /// string that is one, is `value` and its digits (`valueMinus1`,
  /// `value0_5`, `value1eMinus7`).
  String _valueName(
    NameScope scope,
    String? named,
    Object value,
    SpecLocation location,
    String owner,
  ) {
    final fromName = named == null ? null : _names.camel(named);
    final text = '$value';
    final isNumber =
        value is num || (value is String && _numberText.hasMatch(text));
    final candidate =
        fromName ?? (isNumber ? _numberName(text) : _names.camel(text));
    final claimed = scope.claim(candidate ?? 'value');
    _reportClaim(candidate, claimed, value, owner, location);
    if (named != null && fromName == null) {
      _context.report(
        .nameUnrepresentable,
        'The x-enum-varnames entry "$named" of enum $owner has no ASCII '
        'letter or digit, so the value "$value" is named "${claimed.$1}".',
        location,
        severity: .info,
        fix: 'Write a name with a letter or digit in x-enum-varnames.',
      );
    }
    if (candidate != null && value is! num) {
      _context.checkLossyName(
        fromName == null ? text : named!,
        claimed.$1,
        location,
        what: 'Value',
        fix: 'Name it with x-enum-varnames at the source.',
      );
    }
    return claimed.$1;
  }

  /// Reports a name that is not the [candidate] the value asks for: a
  /// fallback, a reserved name or a collision.
  void _reportClaim(
    String? candidate,
    (String, NameChange?) claimed,
    Object value,
    String owner,
    SpecLocation location,
  ) {
    final (name, change) = claimed;
    // A fallback name for an enum value is a naming decision, not a lost
    // type, so it is an info: an enum of a spec that is not yours can only
    // be named at the source.
    if (candidate == null) {
      _context.report(
        .nameUnrepresentable,
        'Value "$value" of enum $owner has no ASCII letter or digit, so it '
        'is named "$name". Add x-enum-varnames to the enum in the spec to '
        'name its values.',
        location,
        severity: .info,
        fix: 'Name the values with x-enum-varnames at the source.',
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        'Value "$value" of enum $owner is named "$name".',
        location,
        fix: 'Name the values with x-enum-varnames at the source.',
      );
    }
  }

  /// The identifier for the number written as [text]: `value`, `Minus` for
  /// a sign, `_` for the point, the exponent without a plus.
  static String _numberName(String text) {
    final negative = text.startsWith('-');
    final digits = (negative ? text.substring(1) : text)
        .replaceAll('.', '_')
        .replaceAllMapped(
          RegExp('([eE])([+-]?)'),
          (m) => '${m[1]}${m[2] == '-' ? 'Minus' : ''}',
        );
    return 'value${negative ? 'Minus' : ''}$digits';
  }
}
