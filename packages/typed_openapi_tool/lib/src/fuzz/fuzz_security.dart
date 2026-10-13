import 'fuzz_schemas.dart';
import 'hostile.dart';

/// The security schemes and requirements of a fuzz spec: an API key, an
/// OAuth 2 scheme and an HTTP scheme, each with hostile names, URLs and
/// scopes.
final class FuzzSecurity {
  /// Builds the schemes with the choices of [schemas].
  FuzzSecurity(FuzzSchemas schemas)
    : _apiKey = schemas.pick(['key', ...Hostile.names]),
      _oauth = schemas.pick(['oauth', ...Hostile.names]),
      _http = schemas.pick(['basic', ...Hostile.names]),
      _schemas = schemas;

  final String _apiKey;
  final String _oauth;
  final String _http;
  final FuzzSchemas _schemas;

  /// The root `security` requirements: every scheme with a hostile scope.
  List<Map<String, List<String>>> get requirements => [
    for (final name in {_apiKey, _oauth, _http})
      {
        name: [_schemas.pick(Hostile.names)],
      },
  ];

  /// The `components.securitySchemes` object.
  Map<String, Object?> get schemes => {
    _apiKey: {
      'type': 'apiKey',
      'in': 'header',
      'name': _schemas.pick(Hostile.names),
      'description': _schemas.pick(Hostile.texts),
    },
    _oauth: {
      'type': 'oauth2',
      'description': _schemas.pick(Hostile.texts),
      'flows': {
        'authorizationCode': {
          'authorizationUrl': _schemas.pick(Hostile.names),
          'tokenUrl': _schemas.pick(Hostile.names),
          'scopes': {
            _schemas.pick(Hostile.names): _schemas.pick(Hostile.texts),
          },
        },
      },
    },
    _http: {
      'type': 'http',
      'scheme': _schemas.pick(['bearer', ...Hostile.names]),
      'bearerFormat': _schemas.pick(Hostile.names),
      'description': _schemas.pick(Hostile.texts),
    },
  };
}
