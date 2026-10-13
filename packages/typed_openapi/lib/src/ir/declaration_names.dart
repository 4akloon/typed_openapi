import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'ir_context.dart';
import 'names.dart';
import 'pending_declaration.dart';

/// Gives the names of declarations, their helper types and their members,
/// and reports every name that differs from what the spec says (R5.2).
final class DeclarationNames {
  /// Names things for the client of [_context].
  DeclarationNames(this._context);

  static const _names = DartNames();

  /// The name of a schema that has none to start from.
  static const fallbackName = 'Schema';

  final IrContext _context;

  /// [pending] in the order their names are claimed: overridden names first,
  /// then component keys, then inline names, each by depth and location.
  static List<PendingDeclaration> inClaimOrder(
    Iterable<PendingDeclaration> pending,
  ) => pending.toList()
    ..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byDepth = a.depth.compareTo(b.depth);
      if (byDepth != 0) return byDepth;
      return a.id.compareTo(b.id);
    });

  /// Claims [candidate] in the library [scope] for a type the emitters add
  /// to the declaration [owner] ([what] says which); a name that differs
  /// is reported.
  String helperName(
    NameScope scope,
    String candidate,
    PendingDeclaration owner,
    String what,
  ) {
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? '"$candidate" is a name Dart already has; $what is named '
                  '"$name".'
            : 'Another type is named "$candidate"; $what is named "$name".',
        owner.id.location,
        // No override: naming the owner would not change a helper's name.
        fix: 'Rename the other type, or rename this one.',
      );
    }
    return name;
  }

  /// Claims the name of [pending] once; an inline declaration's parent is
  /// named first, whatever the order.
  String claim(NameScope scope, PendingDeclaration pending) {
    final named = pending.name;
    if (named != null) return named;
    final candidate = _candidate(scope, pending);
    if (candidate == null) return pending.name = _fallback(scope, pending);
    final (name, change) = scope.claim(candidate);
    final override = _typeOverride(pending, name);
    if (change != null) {
      _reportChange(pending, candidate, (name, change), override);
    }
    if (pending.componentKey case final key?
        when pending.overrideName == null) {
      _context.checkLossyName(
        key,
        name,
        pending.id.location,
        what: 'Schema',
        override: override,
      );
    }
    return pending.name = name;
  }

  /// The name [pending] asks for, before collisions: its override's, its
  /// key's or one made after its parent; null when its key has no ASCII
  /// letter or digit.
  String? _candidate(NameScope scope, PendingDeclaration pending) {
    final suffix = switch (pending.id.variant) {
      .base => '',
      .input => _context.config.inputSuffix,
      .patch => _context.config.patchSuffix,
    };
    if (pending.overrideName case final overridden?) {
      return '$overridden$suffix';
    }
    if (pending.componentKey case final key?) {
      return switch (_names.pascal(key)) {
        final name? => '$name$suffix',
        null => null,
      };
    }
    return switch (pending.hint) {
      // The name of a parent model has its variant suffix already.
      NameHint(:final parent?, suffix: final end) =>
        '${claim(scope, parent)}$end',
      final hint =>
        '${hint?.prefix ?? fallbackName}${hint?.suffix ?? ''}$suffix',
    };
  }

  /// Names [pending], whose key has no ASCII letter or digit,
  /// [fallbackName].
  String _fallback(NameScope scope, PendingDeclaration pending) {
    final (name, _) = scope.claim(fallbackName);
    _context.report(
      .nameUnrepresentable,
      'Schema "${pending.componentKey}" has no ASCII letter or digit, so '
      'its type is named "$name".',
      pending.id.location,
      fix: 'Rename the schema at the source, or name its type.',
      override: _typeOverride(pending, name),
    );
    return name;
  }

  void _reportChange(
    PendingDeclaration pending,
    String candidate,
    (String, NameChange) claimed,
    String? override,
  ) {
    final (name, change) = claimed;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? '"$candidate" is a name Dart already has; the type is named '
                '"$name".'
          : 'Another type is named "$candidate"; this one is named '
                '"$name".',
      pending.id.location,
      fix: override == null
          ? 'Move the schema to components.schemas and name it there, or '
                'rename what it is named after at the source.'
          : 'Name the type explicitly to keep the name stable.',
      override: override,
    );
  }

  /// The override that names the type of [pending] [name], when the schema
  /// has an address in the overrides file: a component's own type. The
  /// override `name` of a property names its field, an inline type has no
  /// address, and the PATCH and request models take their names from the
  /// schema's.
  String? _typeOverride(PendingDeclaration pending, String name) =>
      pending.id.variant == .base && componentKey(pending.id.location) != null
      ? _context.schemaOverride(pending.id.location, {'name': name})
      : null;

  /// The Dart name of the member [json] of the type [owner], from the name
  /// [override] gives or from [json].
  String memberName(
    NameScope scope,
    String json,
    PropertyOverride? override,
    SpecLocation location, {
    required String owner,
  }) {
    final named = override == null
        ? null
        : _context.checkedOverrideName(
            override,
            'name',
            override.name,
            .member,
            what: 'field',
          );
    final candidate = named ?? _names.camel(json);
    if (candidate == null) return _fallbackMember(scope, json, owner, location);
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _reportMemberChange(json, owner, candidate, (name, change), location);
    }
    if (named == null) {
      _context.checkLossyName(
        json,
        name,
        location,
        what: 'Property',
        override: _context.schemaOverride(location, {'name': name}),
      );
    }
    return name;
  }

  /// Names the member [json] of [owner], which has no ASCII letter or
  /// digit, `field`.
  String _fallbackMember(
    NameScope scope,
    String json,
    String owner,
    SpecLocation location,
  ) {
    final (name, _) = scope.claim('field');
    _context.report(
      .nameUnrepresentable,
      'Property "$json" of $owner has no ASCII letter or digit, so its '
      'field is named "$name".',
      location,
      fix: 'Name the field explicitly.',
      override: _context.schemaOverride(location, {'name': name}),
    );
    return name;
  }

  void _reportMemberChange(
    String json,
    String owner,
    String candidate,
    (String, NameChange) claimed,
    SpecLocation location,
  ) {
    final (name, change) = claimed;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? 'Property "$json" of $owner would be the Dart name '
                '"$candidate"; its field is named "$name".'
          : 'Another field of $owner is named "$candidate"; the field of '
                '"$json" is named "$name".',
      location,
      fix: 'Name the field explicitly to keep the name stable.',
      override: _context.schemaOverride(location, {'name': name}),
    );
  }

  /// The name of the field that holds a model's `additionalProperties`,
  /// claimed in the model's field [scope] after the properties, so a
  /// property keeps its name; a name that differs is reported.
  String additionalName(NameScope scope, String owner, SpecLocation at) {
    const candidate = 'additionalProperties';
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        .nameCollision,
        'A property of $owner is named "$candidate"; the field that holds '
        'its additionalProperties is named "$name".',
        at,
        fix: 'Name the property explicitly to keep the names stable.',
      );
    }
    return name;
  }

  /// The name of a schema a `$ref` points to: its `components.schemas` key,
  /// else the last token of its pointer (`#/definitions/Pet`), else its file
  /// name without the extension (`pet.yaml`). A branch of a union is named
  /// after the union (`PetVariant2` for `.../Pet/oneOf/1`).
  static String referenceName(SpecLocation location) {
    final named = _tokensName(location.pointer.tokens);
    if (named != null) return named;
    final file = location.document.pathSegments.lastOrNull ?? '';
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  static String? _tokensName(List<String> tokens) {
    if (tokens.length == 3 && tokens[0] == 'components') {
      if (tokens[1] == 'schemas') return tokens[2];
    }
    if (tokens.isEmpty) return null;
    final index = int.tryParse(tokens.last);
    if (index == null || tokens.length < 2) return tokens.last;
    final owner = _tokensName(tokens.sublist(0, tokens.length - 2));
    if (owner == null) return null;
    final part = switch (tokens[tokens.length - 2]) {
      'oneOf' || 'anyOf' => 'Variant',
      'allOf' => 'Part',
      _ => 'Item',
    };
    return '$owner$part${index + 1}';
  }

  /// The key of the schema at [location] in `components.schemas` of its
  /// document, if it is one.
  static String? componentKey(SpecLocation location) {
    final tokens = location.pointer.tokens;
    if (tokens.length == 3 &&
        tokens[0] == 'components' &&
        tokens[1] == 'schemas') {
      return tokens[2];
    }
    return null;
  }
}
