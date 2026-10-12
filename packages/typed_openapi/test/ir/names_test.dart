import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/names.dart';

void main() {
  const names = DartNames();

  test('splits names into words at separators and case changes', () {
    expect(names.words('user_dto'), ['user', 'dto']);
    expect(names.words('UserController_get'), ['User', 'Controller', 'get']);
    expect(names.words('HTTPServer'), ['HTTP', 'Server']);
    expect(names.words('pet-store.Order v2'), [
      'pet',
      'store',
      'Order',
      'v',
      '2',
    ]);
    expect(names.words('ім’я'), isEmpty);
  });

  test('keeps the case of a schema name except its first letter', () {
    expect(names.pascal('Pet'), 'Pet');
    expect(names.pascal('UserDTO'), 'UserDTO');
    expect(names.pascal('CreateUserDto'), 'CreateUserDto');
    expect(names.pascal('user_dto'), 'UserDto');
    expect(names.pascal('pet store'), 'PetStore');
    expect(names.pascal('2fa'), r'$2Fa');
    expect(names.pascal('+'), isNull);
  });

  test('turns operation ids and properties into lowerCamelCase', () {
    expect(names.camel('UserController_get'), 'userControllerGet');
    expect(names.camel('getPetByID'), 'getPetByID');
    expect(names.camel('ID'), 'id');
    expect(names.camel('created_at'), 'createdAt');
    expect(names.camel('Content-Type'), 'contentType');
    expect(names.camel('2fa_enabled'), r'$2FaEnabled');
    expect(names.camel('ім’я'), isNull);
  });

  test('gives reserved names a suffix and repeated names a number', () {
    final types = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.builtInIdentifiers,
        ...DartNames.takenTypeNames,
      },
      reservedSuffix: 'Model',
    );
    expect(types.claim('Pet'), ('Pet', null));
    expect(types.claim('List'), ('ListModel', NameChange.reserved));
    expect(types.claim('Result'), ('ResultModel', NameChange.reserved));
    expect(types.claim('Pet'), ('Pet2', NameChange.collision));
    expect(types.claim('Pet'), ('Pet3', NameChange.collision));
    expect(types.claim('ListModel'), ('ListModel2', NameChange.collision));
    expect(types.isTaken('Pet3'), isTrue);

    final members = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.modelMembers},
      reservedSuffix: '_',
    );
    expect(members.claim('class'), ('class_', NameChange.reserved));
    expect(members.claim('toJson'), ('toJson_', NameChange.reserved));
    expect(members.claim('get'), ('get', null));
    expect(
      members.claim('get', alternatives: ['getQuery']),
      ('getQuery', NameChange.collision),
    );
    expect(
      members.claim('get', alternatives: ['getQuery']),
      ('get2', NameChange.collision),
    );
  });
}
