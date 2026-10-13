import 'package:typed_openapi/typed_openapi.dart';

import 'sample.dart';

/// The examples of a spec, each as a [Sample] of the class the IR gives its
/// schema: `example` and `examples` of every declaration's schema, and of
/// the JSON media type of every response whose body is a declaration.
///
/// The IR says which class a value belongs to; the reader only looks up the
/// example keys at the locations the IR names.
final class ExampleReader {
  /// Creates the reader; documents are loaded once per file.
  ExampleReader();

  final _documents = <Uri, SpecDocument?>{};

  /// The examples of the client [ir].
  List<Sample> of(ClientIr ir) {
    final names = {for (final d in ir.declarations) d.id: d.name};
    return [
      for (final d in ir.declarations)
        if (d.id.variant == DeclVariant.base)
          for (final value in _schemaExamples(d.id.location))
            Sample(d.name, value, isExample: true),
      for (final group in ir.groups)
        for (final operation in group.operations)
          for (final response in operation.responses)
            if (response.type case NamedType(:final id))
              if (names[id] case final name?)
                for (final value in _mediaExamples(response))
                  Sample(name, value, isExample: true),
    ];
  }

  List<Object?> _schemaExamples(SpecLocation location) {
    final schema = _node(location.document, location.pointer);
    if (schema is! Map<String, Object?>) return const [];
    return [
      ?schema['example'],
      if (schema['examples'] case final List<Object?> examples)
        for (final example in examples) ?example,
    ];
  }

  List<Object?> _mediaExamples(ResponseIr response) {
    final type = response.contentType;
    if (type == null || !type.contains('json')) return const [];
    final location = response.location;
    final media = _node(
      location.document,
      location.pointer.child('content').child(type),
    );
    if (media is! Map<String, Object?>) return const [];
    final values = [
      ?media['example'],
      if (media['examples'] case final Map<String, Object?> examples)
        for (final example in examples.values)
          if (_resolve(location.document, example) case {'value': final v?}) v,
    ];
    final key = response.envelopeKey;
    return [
      for (final value in values)
        if (key == null)
          value
        else if (value case final Map<String, Object?> envelope)
          ?envelope[key],
    ];
  }

  Object? _resolve(Uri document, Object? node) => switch (node) {
    {r'$ref': final String ref} when ref.startsWith('#/') => _node(
      document,
      JsonPointer.parse(ref),
    ),
    _ => node,
  };

  Object? _node(Uri document, JsonPointer pointer) {
    final loaded = _documents.putIfAbsent(
      document,
      () => SpecLoader(DiagnosticBag()).load(document.toFilePath()),
    );
    return loaded?.valueAt(pointer)?.$1;
  }
}
