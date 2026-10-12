import '../diagnostics/json_pointer.dart';
import '../model/server.dart';
import 'object_reader.dart';
import 'parse_context.dart';

/// Reads Server Objects and their Server Variable Objects.
final class ServerParser {
  /// Creates a parser that reads from [_context].
  const ServerParser(this._context);

  final ParseContext _context;

  /// Reads the server [raw] at [pointer].
  Server? server(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'A server', _server);

  Server _server(ObjectReader r) {
    if (r.has('name')) _context.note(.serverName, r.pointer.child('name'));
    return _context.register(
      Server(
        location: r.location,
        url: r.requiredString('url'),
        name: r.string('name'),
        description: r.string('description'),
        variables: r.map('variables', _variableAt) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ServerVariable? _variableAt(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'A server variable', _variable);

  ServerVariable _variable(ObjectReader r) => _context.register(
    ServerVariable(
      location: r.location,
      enumValues: r.strings('enum'),
      defaultValue: r.requiredString('default'),
      description: r.string('description'),
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    ),
  );
}
