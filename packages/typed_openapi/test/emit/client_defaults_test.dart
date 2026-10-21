import 'package:test/test.dart';

import '../helpers/emit_fixture.dart';

void main() {
  group('the generated constructors take default call options', () {
    final files = emitClient('petstore.yaml');
    final root = files.entries.singleWhere(
      (e) => e.value.contains('final PetsApi pets;'),
    );
    final group = files.entries.singleWhere(
      (e) => e.value.contains('class PetsApi {'),
    );

    test('the root passes defaults to every group', () {
      expect(
        root.value,
        contains('CallOptions defaults = const CallOptions()'),
      );
      expect(root.value, contains('PetsApi(transport, defaults: defaults)'));
    });

    test('a group hands defaults to its sender', () {
      expect(
        group.value,
        contains('ClientSender(transport, defaults: defaults)'),
      );
    });

    test('the root imports CallOptions from the client package', () {
      expect(root.value, matches(RegExp(r'show[^;]*\bCallOptions\b')));
    });
  });
}
