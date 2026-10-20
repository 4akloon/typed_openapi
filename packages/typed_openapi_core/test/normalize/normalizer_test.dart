import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/project_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/load/spec_loader.dart';
import 'package:typed_openapi_core/src/model/document.dart';
import 'package:typed_openapi_core/src/model/schema.dart';
import 'package:typed_openapi_core/src/normalize/normalizer.dart';
import 'package:typed_openapi_core/src/normalize/normalizer_rule.dart';
import 'package:typed_openapi_core/src/normalize/rules/drop_invalid_default.dart';
import 'package:typed_openapi_core/src/normalize/rules/path_param_rules.dart';
import 'package:typed_openapi_core/src/normalize/spec_edit.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// Renames the title "old" to "new": a fix that holds after one pass.
final class _RenameTitle extends NormalizerRule {
  const _RenameTitle();

  @override
  String get name => 'rename-title';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final info in context.nodes<Info>()) {
      if (info.title != 'old') continue;
      final at = info.location.child('title');
      yield context.finding(
        .invalidValue,
        'The title is old.',
        at,
        fix: 'Rename it.',
        edits: [SpecEdit.replace(at, 'new')],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) =>
      preset == .nestjs ? 'Use @ApiTitle.' : null;
}

/// Removes `required: true` from every schema: the fix M3's
/// `bool-required-to-array` makes, without moving the name.
final class _DropBoolRequired extends NormalizerRule {
  const _DropBoolRequired();

  @override
  String get name => 'drop-bool-required';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final raw = context.rawAt(schema.location)?.$1;
      if (raw is! Map<String, Object?> || raw['required'] is! bool) continue;
      final at = schema.location.child('required');
      yield context.finding(
        .invalidValue,
        'Boolean required.',
        at,
        edits: [SpecEdit.remove(at)],
      );
    }
  }
}

/// Removes `x-drop` from the root with one edit carried by the first of
/// two findings.
final class _OneEditTwoFindings extends NormalizerRule {
  const _OneEditTwoFindings();

  @override
  String get name => 'one-edit-two-findings';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final root = context.model.document.location;
    if (context.rawObject(root)?.containsKey('x-drop') != true) return;
    final at = root.child('x-drop');
    yield context.finding(
      .invalidValue,
      'First.',
      at,
      edits: [SpecEdit.remove(at)],
    );
    yield context.finding(.invalidValue, 'Second.', at);
  }
}

/// Removes every `bad` item of the root's `x-l` list, each by its own index.
final class _DropBadItems extends NormalizerRule {
  const _DropBadItems();

  @override
  String get name => 'drop-bad-items';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final root = context.model.document.location;
    final items = context.rawObject(root)?['x-l'];
    if (items is! List<Object?>) return;
    final list = root.child('x-l');
    final edits = [
      for (var i = 0; i < items.length; i++)
        if (items[i] == 'bad') SpecEdit.remove(list.child(i)),
    ];
    if (edits.isEmpty) return;
    yield context.finding(.invalidValue, 'Bad items.', list, edits: edits);
  }
}

/// Removes the item `a` of the root's `x-l` list and renames the item `b`
/// in the same pass: the rename names an index the removal shifts.
final class _RemoveThenRename extends NormalizerRule {
  const _RemoveThenRename();

  @override
  String get name => 'remove-then-rename';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final root = context.model.document.location;
    final items = context.rawObject(root)?['x-l'];
    if (items is! List<Object?>) return;
    final list = root.child('x-l');
    for (var i = 0; i < items.length; i++) {
      final name = (items[i] as Map<String, Object?>)['name'];
      if (name == 'a') {
        yield context.finding(
          .invalidValue,
          'Drop a.',
          list.child(i),
          edits: [SpecEdit.remove(list.child(i))],
        );
      } else if (name == 'b') {
        final at = list.child(i).child('name');
        yield context.finding(
          .invalidValue,
          'Rename b.',
          at,
          edits: [SpecEdit.replace(at, 'B')],
        );
      }
    }
  }
}

/// Reports every schema without a type: a diagnostic-only rule.
final class _Untyped extends NormalizerRule {
  const _Untyped();

  @override
  String get name => 'untyped';

  @override
  List<DiagnosticCode> get codes => const [.missingRequiredField];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.types.isNotEmpty || schema.ref != null) continue;
      yield context.finding(
        .missingRequiredField,
        'No type.',
        schema.location,
      );
    }
  }
}

/// Sets `info.title` on every pass: it never settles.
final class _AlwaysEdits extends NormalizerRule {
  const _AlwaysEdits(this.name, [this.suffix = '+']);

  @override
  final String name;

  final String suffix;

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final info = context.nodes<Info>().single;
    yield context.finding(
      .invalidValue,
      'Title by $name.',
      info.location,
      edits: [
        SpecEdit.replace(info.location.child('title'), '${info.title}$suffix'),
      ],
    );
  }
}

void main() {
  bool isNotApplied(Diagnostic d) => d.code == DiagnosticCode.fixNotApplied;

  const spec = '''
openapi: 3.0.3
info: {title: old, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        name: {type: string, required: true}
''';

  (NormalizedSpec, DiagnosticBag) normalize(
    String text,
    List<NormalizerRule> rules, {
    Set<String> disabled = const {},
    Preset? preset,
  }) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(text, 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: rules,
      disabled: disabled,
      preset: preset,
    ).normalize(document, .v30);
    return (result, bag);
  }

  test('a fix is applied, the model is read again and reported once', () {
    final (result, bag) = normalize(spec, [const _RenameTitle()]);
    expect(result.model.document.info?.title, 'new');
    expect(result.documents.root.root['info'], {
      'title': 'new',
      'version': '1',
    });
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.invalidValue, '#/info/title'),
      (
        DiagnosticCode.invalidValue,
        '#/components/schemas/Pet/properties/name/required',
      ),
    ]);
    expect(bag.all.first.message, 'The title is old.');
    expect(bag.all.first.line, 2);
  });

  test('parser diagnostics come from the last pass only', () {
    // The first read reports `required: true` as invalid-value; the fix
    // removes it, so the report has the fix and not the parser's complaint.
    final (_, bag) = normalize(spec, [const _DropBoolRequired()]);
    expect(bag.all.single.message, 'Boolean required.');
  });

  test('findings without edits of a rule that fixes are reported too', () {
    final (_, bag) = normalize(
      'openapi: 3.0.3\ninfo: {title: t, version: "1"}\nx-drop: 1\n',
      [const _OneEditTwoFindings()],
    );
    expect(bag.all.map((d) => d.message), ['First.', 'Second.']);
  });

  test('diagnostic-only findings are reported once, from the last pass', () {
    final (_, bag) = normalize(
      'openapi: 3.0.3\ninfo: {title: old, version: "1"}\n'
      'components: {schemas: {Any: {description: anything}}}\n',
      [const _RenameTitle(), const _Untyped()],
    );
    expect(bag.all.map((d) => d.message), ['The title is old.', 'No type.']);
  });

  test('a fix that overlaps an earlier one waits for the next pass', () {
    // declare-missing-path-params replaces the whole parameter list, which
    // contains the default that drop-invalid-default removes.
    final (result, bag) = normalize(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /items/{id}:
    get:
      parameters:
        - {name: limit, in: query, schema: {type: integer, default: many}}
      responses: {}
''',
      [const DeclareMissingPathParams(), const DropInvalidDefault()],
    );
    final get =
        ((result.documents.root.root['paths']! as Map)['/items/{id}']!
                as Map)['get']!
            as Map;
    expect(get['parameters'], [
      {
        'name': 'limit',
        'in': 'query',
        'schema': {'type': 'integer'},
      },
      {
        'name': 'id',
        'in': 'path',
        'required': true,
        'schema': {'type': 'string'},
      },
    ]);
    expect(bag.all.where(isNotApplied), isEmpty);
  });

  test('the same fix proposed twice is applied once, without a warning', () {
    final (result, bag) = normalize(
      r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /b/{x}:
    $ref: '#/components/x-items/Shared'
  /c/{x}:
    $ref: '#/components/x-items/Shared'
components:
  x-items:
    Shared:
      get: {responses: {}}
''',
      [const DeclareMissingPathParams()],
    );
    expect(bag.all.where(isNotApplied), isEmpty);
    final shared =
        ((result.documents.root.root['components']! as Map)['x-items']!
                as Map)['Shared']!
            as Map;
    expect((shared['get'] as Map)['parameters'], hasLength(1));
  });

  test('a fix that never fits is reported as not applied', () {
    final (result, bag) = normalize(spec, [
      const _AlwaysEdits('first'),
      const _AlwaysEdits('second', '-'),
    ]);
    expect(result.model.document.info?.title, 'old++');
    final skipped = bag.all.where(isNotApplied).map((d) => d.message).toSet();
    expect(
      skipped,
      contains(
        'A fix of rule "second" was not applied: the spec still changed '
        'after 3 passes.',
      ),
    );
  });

  test('the normalizer stops after three passes and says so', () {
    final (result, bag) = normalize(spec, [const _AlwaysEdits('loop')]);
    expect(result.model.document.info?.title, 'old++');
    expect(Normalizer.maxPasses, 3);
    expect(
      bag.all
          .where((d) => d.code == DiagnosticCode.fixNotApplied)
          .single
          .message,
      contains('still changed after 3 passes'),
    );
  });

  test(
    'removing several items of one list by index removes the right ones',
    () {
      final (result, _) = normalize(
        'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n'
        'x-l: [bad, ok, bad, last]\n',
        [const _DropBadItems()],
      );
      expect(result.documents.root.root['x-l'], ['ok', 'last']);
    },
  );

  test('an edit behind a removed list item is proposed again next pass', () {
    final (result, _) = normalize(
      'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n'
      'x-l: [{name: a}, {name: b}, {name: c}]\n',
      [const _RemoveThenRename()],
    );
    expect(result.documents.root.root['x-l'], [
      {'name': 'B'},
      {'name': 'c'},
    ]);
  });

  test('a disabled rule does not run', () {
    final (result, bag) = normalize(
      spec,
      [const _RenameTitle()],
      disabled: {'rename-title'},
    );
    expect(result.model.document.info?.title, 'old');
    expect(bag.all.single.code, DiagnosticCode.invalidValue);
    expect(bag.all.single.pointer?.value, contains('required'));
  });

  test('a preset adds the framework hint to the fix', () {
    final (_, bag) = normalize(spec, [const _RenameTitle()], preset: .nestjs);
    expect(bag.all.first.fix, 'Rename it. Use @ApiTitle.');
  });

  test('fixes in another file are applied to that file', () {
    final dir = TempDir();
    dir.write(
      'pet.yaml',
      'Pet:\n  type: object\n  properties:\n'
          '    name: {type: string, required: true}\n',
    );
    final path = dir.write('api.yaml', r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {$ref: "pet.yaml#/Pet"}
''');
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: [const _DropBoolRequired()],
    ).normalize(document, .v30);
    final pet = result.documents[p.toUri(p.join(dir.path, 'pet.yaml'))]!;
    expect(pet.root['Pet'], {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
    });
    expect(bag.all.single.file, 'pet.yaml');
    expect(bag.all.single.line, 4);
  });
}
