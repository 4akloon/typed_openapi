import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/names.dart';

NameScope _scope() => NameScope(reserved: {'Class'}, reservedSuffix: 'Model');

void main() {
  test('a claim for an identity gets the name the lock keeps', () {
    final scope = _scope()..lock({'a': 'PetStatus2'});
    expect(scope.claim('PetStatus', identity: 'a'), (
      'PetStatus2',
      NameChange.kept,
    ));
  });

  test('the kept name equal to the candidate is no change', () {
    final scope = _scope()..lock({'a': 'Pet'});
    expect(scope.claim('Pet', identity: 'a'), ('Pet', null));
  });

  test('a claim without the identity never takes a kept name', () {
    final scope = _scope()..lock({'a': 'Pet'});
    expect(scope.claim('Pet'), ('Pet2', NameChange.collision));
    expect(scope.claim('Pet', identity: 'b'), ('Pet3', NameChange.collision));
    expect(scope.claim('Pet', identity: 'a'), ('Pet', null));
  });

  test('an explicit claim takes a kept name and the identity is renamed', () {
    final scope = _scope()..lock({'a': 'Pet'});
    expect(scope.claim('Pet', isExplicit: true), ('Pet', null));
    expect(scope.claim('Pet', identity: 'a'), ('Pet2', NameChange.lockTaken));
  });

  test('a reserved name takes a kept name first', () {
    final scope = _scope()
      ..lock({'a': 'Pet'})
      ..reserve('Pet');
    expect(scope.claim('Pet', identity: 'a'), ('Pet2', NameChange.lockTaken));
  });

  test('a kept name says why a fresh run would differ', () {
    final scope = _scope()..lock({'a': 'ClassModel', 'b': 'Pet2', 'c': 'Pet'});
    expect(scope.claim('Class', identity: 'a'), (
      'ClassModel',
      NameChange.reserved,
    ));
    expect(scope.claim('Pet', identity: 'b'), ('Pet2', NameChange.collision));
  });
}
