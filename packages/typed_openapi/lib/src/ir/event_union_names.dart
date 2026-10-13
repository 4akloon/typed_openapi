import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'type_claims.dart';

/// Names the event union of a stream method (decision 2 of M10) in the
/// library scope, after the declarations and the M9 status types: the
/// sealed class `<Method>Event`, its unknown variant `<Union>Unknown`, then
/// a variant per event, `<Union><Event>` (`<Union>Event<n>` for an event
/// name without an ASCII letter or digit, TOA668). The unknown variant is
/// named before the others, so an event named `unknown` is the one that
/// gets a suffix.
final class EventUnionNames {
  /// Creates the namer; it claims through [_claims].
  const EventUnionNames(this._context, this._claims);

  static const _names = DartNames();

  final IrContext _context;
  final TypeClaims _claims;

  /// The events of [operation] with their union named after [prefix]; null
  /// when the events are not a union.
  EventStreamIr? name(OperationIr operation, String prefix) {
    final events = operation.events;
    final union = events?.union;
    if (events == null || union == null) return null;
    final name = _claims.claim(
      '${prefix}Event',
      'the events of ${operation.name}',
      operation.location,
      override: operation,
    );
    final unknown = union.keepUnknown
        ? _claims.claim(
            '${name}Unknown',
            'the unknown events of ${operation.name}',
            operation.location,
            override: operation,
          )
        : '';
    return events.withUnion(
      union.named(name, unknown, [
        for (final (index, variant) in union.variants.indexed)
          variant.named(_variantName(name, variant, index, operation, union)),
      ]),
    );
  }

  String _variantName(
    String union,
    EventVariantIr variant,
    int index,
    OperationIr operation,
    EventUnionIr ir,
  ) {
    final words = _names.pascal(variant.event);
    final candidate = '$union${words ?? 'Event${index + 1}'}';
    if (words == null) {
      _context.report(
        .eventNameUnrepresentable,
        'Event "${variant.event}" has no ASCII letter or digit; its class is '
        'named after its place.',
        ir.location,
        fix: 'Name the event with letters at the source.',
      );
    } else {
      _context.checkLossyName(
        variant.event,
        words,
        ir.location,
        what: 'Event name',
      );
    }
    return _claims.claim(
      candidate,
      'the class of the event "${variant.event}"',
      operation.location,
      override: operation,
    );
  }
}
