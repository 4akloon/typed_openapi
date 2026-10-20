/// OpenAPI 3.x to Dart client generator.
///
/// The engine that reads and checks a spec is `package:typed_openapi_core`;
/// this library writes the client for what the engine checked. [ApiLibrary]
/// and [ModelLibrary] turn a client's IR into files, [OutputWriter] installs
/// them atomically, and [TypedOpenApiCli] runs the commands.
library;

// Transitional: removed by the task that moves the tool to the core.
export 'package:typed_openapi_core/typed_openapi_core.dart';
export 'src/cli/cli.dart' show TypedOpenApiCli;
export 'src/emit/api_library.dart' show ApiLibrary;
export 'src/emit/model_library.dart' show ModelLibrary;
export 'src/generate/output_writer.dart' show OutputChanges, OutputWriter;
