import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  /// Measures a package whose `lib/a.dart` holds [source].
  Map<String, int> measure(String source) {
    final dir = TempDir()..write('lib/a.dart', source);
    return SizeLimits(dir.path).measureMethods();
  }

  /// A class `A` with [body] as its members.
  String classWith(String body) => 'class A {\n$body}\n';

  /// [count] lines of a list literal, each a `'x',` item.
  String items(int count) => List.filled(count, "    'x',\n").join();

  test('an expression-bodied getter over 40 lines is measured', () {
    final result = measure(
      classWith('  List<String> get all => [\n${items(45)}  ];\n'),
    );
    expect(result, {'lib/a.dart#A.all': 47});
  });

  test('an expression-bodied method with parameters is measured', () {
    final result = measure(
      classWith(
        '  List<String> build(\n    int a,\n  ) => [\n${items(45)}  ];\n',
      ),
    );
    expect(result, {'lib/a.dart#A.build': 49});
  });

  test('a getter that returns a switch expression is measured', () {
    final result = measure(
      classWith(
        '  int get v => switch (1) {\n${List.filled(45, "    1 => 1,\n").join()}'
        '  };\n',
      ),
    );
    expect(result, {'lib/a.dart#A.v': 47});
  });

  test('a short expression body is not reported', () {
    expect(measure(classWith('  int get v => 1;\n')), isEmpty);
  });

  test('a field whose initializer is long is not a method', () {
    final result = measure(
      classWith('  static const all = [\n${items(45)}  ];\n'),
    );
    expect(result, isEmpty);
  });

  test('a block method with a closure arrow is measured once', () {
    final body = List.filled(45, '    print(1);\n').join();
    final result = measure(
      classWith('  void run() {\n    final f = () => 1;\n$body  }\n'),
    );
    expect(result.keys, ['lib/a.dart#A.run']);
  });

  test('members after an arrow member are still measured', () {
    final body = List.filled(45, '    print(1);\n').join();
    final result = measure(
      classWith('  int get v => 1;\n\n  void run() {\n$body  }\n'),
    );
    expect(result.keys, ['lib/a.dart#A.run']);
  });
}
