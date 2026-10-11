import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/normalize/spec_edit.dart';

void main() {
  final file = Uri.file('/specs/api.yaml');
  SpecLocation at(String pointer) =>
      SpecLocation(file, JsonPointer.parse(pointer));

  test('add, replace and remove change a copy, never the original', () {
    final original = <String, Object?>{
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    };
    final editor = TreeEditor(original);
    expect(editor.apply(SpecEdit.add(at('#/a/d'), 3)), isNull);
    expect(editor.apply(SpecEdit.replace(at('#/a/b'), 10)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/a/c'))), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/-'), 3)), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 0)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/l/1'))), isNull);
    expect(editor.root, {
      'a': {'b': 10, 'd': 3},
      'l': [0, 2, 3],
    });
    expect(original, {
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    });
  });

  test('a node shared by two places (a YAML alias) changes in one', () {
    final shared = <String, Object?>{'type': 'string'};
    final editor = TreeEditor({'x': shared, 'y': shared});
    expect(editor.apply(SpecEdit.add(at('#/x/format'), 'uuid')), isNull);
    expect(editor.root['x'], {'type': 'string', 'format': 'uuid'});
    expect(editor.root['y'], {'type': 'string'});
  });

  test('a node reached through a YAML alias changes at one use only', () {
    final document = SpecLoader(DiagnosticBag()).parse(
      'a: &a {type: string, items: {k: 1}}\n'
          'x: *a\n'
          'y: *a\n',
      'api.yaml',
    )!;
    final editor = TreeEditor(document.root);
    expect(editor.apply(SpecEdit.add(at('#/x/format'), 'uuid')), isNull);
    expect(editor.apply(SpecEdit.replace(at('#/y/items/k'), 2)), isNull);
    expect(editor.root['a'], {
      'type': 'string',
      'items': {'k': 1},
    });
    expect(editor.root['x'], {
      'type': 'string',
      'items': {'k': 1},
      'format': 'uuid',
    });
    expect(editor.root['y'], {
      'type': 'string',
      'items': {'k': 2},
    });
    expect(document.root['x'], {
      'type': 'string',
      'items': {'k': 1},
    });
    expect(document.root['y'], {
      'type': 'string',
      'items': {'k': 1},
    });
  });

  test('an edit of a missing node says why and changes nothing', () {
    final editor = TreeEditor({
      'a': {'b': 1},
    });
    expect(editor.apply(SpecEdit.replace(at('#/a/x'), 1)), contains('#/a/x'));
    expect(editor.apply(SpecEdit.remove(at('#/a/b/c'))), isNotNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 1)), isNotNull);
    expect(editor.apply(SpecEdit.remove(at('#'))), contains('root'));
    expect(editor.root, {
      'a': {'b': 1},
    });
  });

  test('an edit that shifts list items overlaps edits in that list', () {
    SpecEdit remove(String pointer) => SpecEdit.remove(at(pointer));
    SpecEdit add(String pointer) => SpecEdit.add(at(pointer), 1);
    SpecEdit replace(String pointer) => SpecEdit.replace(at(pointer), 1);
    expect(
      remove('#/l/1').overlaps(replace('#/l/2/schema/type')),
      isTrue,
    );
    expect(replace('#/l/2/schema/type').overlaps(remove('#/l/1')), isTrue);
    expect(remove('#/l/0').overlaps(remove('#/l/2')), isTrue);
    expect(add('#/l/-').overlaps(add('#/l/-')), isTrue);
    expect(add('#/l/-').overlaps(replace('#/l/0/x')), isTrue);
    expect(replace('#/l/0').overlaps(replace('#/l/2')), isFalse);
    expect(remove('#/l/0').overlaps(replace('#/m/1/x')), isFalse);
    expect(remove('#/a/x').overlaps(remove('#/a/y')), isFalse);
  });

  test('edits overlap when one is at or inside the other', () {
    final b = SpecEdit.remove(at('#/a/b'));
    expect(b.overlaps(SpecEdit.remove(at('#/a/b'))), isTrue);
    expect(b.overlaps(SpecEdit.add(at('#/a/b/c'), 1)), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a'))), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a/bc'))), isFalse);
    expect(
      b.overlaps(
        SpecEdit.remove(SpecLocation(Uri.file('/b.yaml'), b.location.pointer)),
      ),
      isFalse,
    );
  });
}
