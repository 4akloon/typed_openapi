import 'api_change.dart';

/// The category of a changed fact of a snapshot entry: the rule table of
/// the facts the snapshot builder writes (M12, decision 2).
final class FactChanges {
  /// Creates the table.
  const FactChanges();

  /// The facts whose change breaks code that names the entry.
  static const breaking = {
    'type',
    'returns',
    'kind',
    'known',
    'unknown',
    'additional',
    'additionalName',
    'data',
    'variables',
  };

  /// The facts that only change what goes on the wire.
  static const wire = {
    'json',
    'const',
    'method',
    'path',
    'accept',
    'responses',
    'in',
    'wire',
    'style',
    'explode',
    'allowReserved',
    'media',
    'discriminator',
    'values',
    'url',
  };

  /// The facts that are documentation.
  static const docs = {'doc', 'deprecated'};

  /// The category of a change of [fact] from [before] to [after] (null
  /// when absent). `required` is breaking when it becomes true and additive
  /// when it becomes false; a fact the table does not know is breaking, so
  /// a new fact is never under-reported.
  ChangeCategory categoryOf(String fact, String? before, String? after) {
    if (fact == 'required') {
      return after == 'true' ? .breaking : .additive;
    }
    if (wire.contains(fact)) return .wire;
    if (docs.contains(fact)) return .docs;
    return .breaking;
  }

  /// A sentence on the change of [fact] of [what]. A fact that appears or
  /// goes is said so, never written as a value: a value may itself be
  /// `none` (Stripe's `setup_future_usage`).
  String describe(String what, String fact, String? before, String? after) =>
      switch (fact) {
        'doc' => '$what: the documentation changed.',
        'deprecated' when after == 'true' => '$what is now deprecated.',
        'deprecated' => '$what is no longer deprecated.',
        'required' when after == 'true' => '$what is now required.',
        'required' => '$what is now optional.',
        _ => switch ((before, after)) {
          (null, final now?) => '$what: $fact is now $now.',
          (final old?, null) => '$what: $fact $old is gone.',
          _ => '$what: $fact changed from $before to $after.',
        },
      };
}
