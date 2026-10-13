import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'decoder_writer.dart';
import 'type_codec.dart';

/// Writes the event union of a stream method (decision 2 of M10, R12.2):
/// a sealed class whose `fromEvent` switches on the SSE event name, a
/// variant per event that wraps its data and is equal by value, and a
/// variant for an event no variant names, as M8 unions keep an unknown
/// value.
final class EventUnionEmitter {
  /// Creates an emitter that writes with [_codec].
  EventUnionEmitter(this._codec) : _decoder = DecoderWriter(_codec);

  final TypeCodec _codec;
  final DecoderWriter _decoder;

  static const _code = DartCode();

  /// Writes [union], the events of [operation] of [group].
  void write(
    DartWriter out,
    EventUnionIr union,
    OperationIr operation,
    GroupIr group,
  ) {
    _codec.imports
      ..fromRuntime('SseMessage')
      ..fromRuntime('immutable');
    final method = '${group.name}.${operation.name}';
    _base(out, union, method);
    for (final variant in union.variants) {
      out
        ..line()
        ..prose(
          '${variant.event.isEmpty ? 'The event with an empty name' : 'The '
                    '`${_code.docSpan(variant.event)}` event'} of [$method]'
          '${variant.hasData ? '.' : ', which has no data.'}',
        )
        ..block('class ${variant.name} extends ${union.name}', () {
          if (variant.hasData) {
            _withData(out, variant);
          } else {
            _withoutData(out, variant.name);
          }
        });
    }
    if (!union.keepUnknown) return;
    out.line();
    _unknown(out, union, method);
  }

  /// Writes the sealed class with `fromEvent`.
  void _base(DartWriter out, EventUnionIr union, String method) {
    out
      ..prose(
        'The events of [$method], by their event name: a `switch` names '
        'every one.',
      )
      ..line('@immutable')
      ..block('sealed class ${union.name}', () {
        out
          ..prose('Creates the value.')
          ..line('const ${union.name}();')
          ..line()
          ..prose('Decodes [message] by its event name.')
          ..line(
            'static ${union.name} fromEvent(SseMessage message) => '
            'switch (message.event) {',
          );
        out.indented(() {
          for (final variant in union.variants) {
            out.line('${_code.string(variant.event)} => ${_value(variant)},');
          }
          if (union.keepUnknown) {
            out.line(
              '_ => ${union.unknownName}(message.event, message.data),',
            );
          } else {
            _codec.imports.fromRuntime('SseEventIgnored');
            out.line('_ => throw const SseEventIgnored(),');
          }
        });
        out.line('};');
      });
  }

  /// The variant of one event, decoded from `message`.
  String _value(EventVariantIr variant) {
    if (!variant.hasData) return 'const ${variant.name}()';
    final data = variant.data;
    final value = data == null
        ? 'message.data'
        : _decoder.decode(data, 'message.json');
    return '${variant.name}($value)';
  }

  static void _withoutData(DartWriter out, String name) {
    out
      ..prose('Creates the value.')
      ..line('const $name();')
      ..line()
      ..line('@override')
      ..line('bool operator ==(Object other) => other is $name;')
      ..line()
      ..line('@override')
      ..line('int get hashCode => ($name).hashCode;')
      ..line()
      ..line('@override')
      ..line("String toString() => '${_code.escaped(name)}()';");
  }

  void _withData(DartWriter out, EventVariantIr variant) {
    final name = variant.name;
    final type = variant.data ?? const CoreType(.string);
    final deep = _codec.needsDeep(type);
    if (deep) _codec.imports.fromRuntime('DeepEquality');
    final shown = variant.sensitive ? '<redacted>' : r'$data';
    out
      ..prose('Wraps [data].')
      ..line('const $name(this.data);')
      ..line()
      ..prose('The data of the event.')
      ..line('final ${_codec.type(type)} data;')
      ..line()
      ..line('@override')
      ..chain('bool operator ==(Object other) =>', [
        'other is $name',
        if (deep)
          'const DeepEquality().equals(other.data, data)'
        else
          'other.data == data',
      ], '&&')
      ..line()
      ..line('@override')
      ..line(
        deep
            ? 'int get hashCode => const DeepEquality().hash(data);'
            : 'int get hashCode => data.hashCode;',
      )
      ..line()
      ..line('@override')
      ..line("String toString() => '${_code.escaped(name)}($shown)';");
  }

  static void _unknown(DartWriter out, EventUnionIr union, String method) {
    final name = union.unknownName;
    final shown = union.unknownSensitive ? '<redacted>' : r'$data';
    out
      ..prose(
        'An event of [$method] whose name no other variant has, with its '
        'data as text.',
      )
      ..block('class $name extends ${union.name}', () {
        out
          ..prose('Wraps an event named [event] with [data].')
          ..line('const $name(this.event, this.data);')
          ..line()
          ..prose('The event name.')
          ..line('final String event;')
          ..line()
          ..prose('The data as received.')
          ..line('final String data;')
          ..line()
          ..line('@override')
          ..chain('bool operator ==(Object other) =>', [
            'other is $name',
            'other.event == event',
            'other.data == data',
          ], '&&')
          ..line()
          ..line('@override')
          ..line('int get hashCode => Object.hash(event, data);')
          ..line()
          ..line('@override')
          ..line(
            "String toString() => '${_code.escaped(name)}(\$event, $shown)';",
          );
      });
  }
}
