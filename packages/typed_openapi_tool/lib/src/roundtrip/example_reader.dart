import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'sample.dart';

/// The examples of a client: the [samples] to decode, and how many examples
/// the reader [skipped] because it could not turn them into a value.
typedef ExampleSet = ({List<Sample> samples, int skipped});

/// The examples of a spec, each as a [Sample] of the class the IR gives its
/// schema: `example` and `examples` of every declaration's schema, and of
/// the JSON media type of every response whose body is a declaration.
///
/// The IR says which class a value belongs to; the reader only looks up the
/// example keys at the locations the IR names. An example it cannot read (a
/// `null`, a `$ref` to another file or beyond [maxReferenceHops], an entry
/// with no `value`, a document that does not load) is counted in
/// [ExampleSet.skipped], never dropped silently.
final class ExampleReader {
  /// Creates the reader; documents are loaded once per file.
  ExampleReader();

  /// How many `$ref`s in a row an `examples` entry is followed through.
  static const int maxReferenceHops = 10;

  final _documents = <Uri, SpecDocument?>{};

  /// The examples of the client [ir].
  ExampleSet of(ClientIr ir) {
    final names = {for (final d in ir.declarations) d.id: d.name};
    final samples = <Sample>[];
    var skipped = 0;
    void add(String name, _Found found) {
      samples.addAll([
        for (final value in found.values) Sample(name, value, isExample: true),
      ]);
      skipped += found.skipped;
    }

    for (final d in ir.declarations) {
      if (d.id.variant == DeclVariant.base) {
        add(d.name, _schemaExamples(d.id.location));
      }
    }
    for (final group in ir.groups) {
      for (final operation in group.operations) {
        for (final response in operation.responses) {
          if (response.type case NamedType(:final id)) {
            if (names[id] case final name?) add(name, _mediaExamples(response));
          }
        }
      }
    }
    return (samples: samples, skipped: skipped);
  }

  _Found _schemaExamples(SpecLocation location) {
    final schema = _node(location.document, location.pointer);
    if (schema is! Map<String, Object?>) {
      return (values: const [], skipped: _unreadable(location.document));
    }
    final found = _Collector();
    if (schema.containsKey('example')) found.take(schema['example']);
    switch (schema['examples']) {
      case final List<Object?> examples:
        examples.forEach(found.take);
      case null when !schema.containsKey('examples'):
        break;
      case _:
        found.skip();
    }
    return found.done;
  }

  _Found _mediaExamples(ResponseIr response) {
    final type = response.contentType;
    if (type == null || !type.contains('json')) return _Collector().done;
    final location = response.location;
    final media = _node(
      location.document,
      location.pointer.child('content').child(type),
    );
    if (media is! Map<String, Object?>) {
      return (values: const [], skipped: _unreadable(location.document));
    }
    final found = _Collector();
    if (media.containsKey('example')) found.take(media['example']);
    switch (media['examples']) {
      case final Map<String, Object?> examples:
        for (final example in examples.values) {
          final resolved = _resolve(location.document, example);
          if (resolved case {'value': final value}) {
            found.take(value);
          } else {
            found.skip();
          }
        }
      case null when !media.containsKey('examples'):
        break;
      case _:
        found.skip();
    }
    return _unwrapped(found.done, response.envelopeKey);
  }

  /// The values of [found] without their envelope: the property [key] of
  /// each; a value that has none is skipped.
  static _Found _unwrapped(_Found found, String? key) {
    if (key == null) return found;
    final unwrapped = _Collector()..skipped = found.skipped;
    for (final value in found.values) {
      if (value case final Map<String, Object?> envelope) {
        unwrapped.take(envelope[key]);
      } else {
        unwrapped.skip();
      }
    }
    return unwrapped.done;
  }

  /// The node an `examples` entry stands for: the entry itself, or what its
  /// `$ref`s into the same document lead to; null for another file or too
  /// long a chain.
  Object? _resolve(Uri document, Object? node) {
    var current = node;
    for (var hops = 0; hops <= maxReferenceHops; hops++) {
      if (current case {r'$ref': final String ref}) {
        if (!ref.startsWith('#/')) return null;
        current = _node(document, JsonPointer.parse(ref));
      } else {
        return current;
      }
    }
    return null;
  }

  /// 1 when [document] did not load, else 0.
  int _unreadable(Uri document) => _documents[document] == null ? 1 : 0;

  Object? _node(Uri document, JsonPointer pointer) {
    final loaded = _documents.putIfAbsent(
      document,
      () => SpecLoader(DiagnosticBag()).load(document.toFilePath()),
    );
    return loaded?.valueAt(pointer)?.$1;
  }
}

/// The values found at one place, and the examples there that gave none.
typedef _Found = ({List<Object?> values, int skipped});

/// Collects a [_Found] one example at a time.
final class _Collector {
  final values = <Object?>[];
  int skipped = 0;

  void take(Object? value) {
    if (value == null) {
      skip();
    } else {
      values.add(value);
    }
  }

  void skip() => skipped++;

  _Found get done => (values: values, skipped: skipped);
}
