import 'dart:convert';

import 'package:collection/collection.dart';

import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// Values repeated in an `enum` (C-9, C-52) are removed; the first
/// occurrence of each stays, in order. Values are compared as JSON, so
/// `Admin` and `admin` are two values.
final class DedupeEnumValues extends NormalizerRule {
  /// Creates the rule.
  const DedupeEnumValues();

  /// More repeats than this suggest several enums merged into one (C-52).
  static const _mergedEnums = 3;

  static const _equality = DeepCollectionEquality();

  @override
  String get name => 'dedupe-enum-values';

  @override
  List<DiagnosticCode> get codes => const [.duplicateEnumValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final values = schema.enumValues;
      if (values == null) continue;
      final kept = <Object?>[];
      final repeated = <Object?>[];
      for (final value in values) {
        final seen = kept.any((k) => _equality.equals(k, value));
        (seen ? repeated : kept).add(value);
      }
      if (repeated.isEmpty) continue;
      final at = schema.location.child('enum');
      final shown = repeated.map(jsonEncode).toSet().join(', ');
      yield context.finding(
        .duplicateEnumValue,
        'The enum repeats $shown; the repeats are removed and the first '
        'occurrence of each value is kept'
        '${repeated.length > _mergedEnums ? '. So many repeats look like '
                  'several enums merged into one' : ''}.',
        at,
        fix: 'Remove the repeated values at the source.',
        edits: [SpecEdit.replace(at, kept)],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, give the enum its own schema with `enumName` (the CLI '
          'plugin option `autoFillEnumName` sets it) instead of spreading '
          'several TypeScript enums into one list.',
    _ => null,
  };
}

/// A nullable enum written as `oneOf` of an enum of only `null` and a
/// `$ref` (C-54, NestJS 11): the intent is a nullable reference, but
/// generators read a union.
final class NullableEnumOneOf extends NormalizerRule {
  /// Creates the rule.
  const NullableEnumOneOf();

  @override
  String get name => 'nullable-enum-one-of';

  @override
  List<DiagnosticCode> get codes => const [.nullableEnumOneOf];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.oneOf.length != 2) continue;
      final nulls = schema.oneOf.whereType<SchemaObject>().where(_onlyNull);
      final refs = schema.oneOf.whereType<SchemaObject>().where(
        (s) => s.ref != null,
      );
      if (nulls.length != 1 || refs.length != 1) continue;
      final ref = refs.single.ref!;
      yield context.finding(
        .nullableEnumOneOf,
        'This is a nullable reference to "$ref" written as "oneOf" with an '
        'enum of only null; generators read it as a union of two types.',
        schema.location.child('oneOf'),
        fix:
            'Write a nullable reference to "$ref" at the source; until then, '
            'override this schema as a nullable "$ref".',
      );
    }
  }

  static bool _onlyNull(SchemaObject schema) {
    final values = schema.enumValues;
    return values != null &&
        values.isNotEmpty &&
        values.every((v) => v == null) &&
        schema.ref == null;
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, @nestjs/swagger 12 writes nullability according to the '
          'document version; on 11.x keep the document at OpenAPI 3.0.',
    _ => null,
  };
}
