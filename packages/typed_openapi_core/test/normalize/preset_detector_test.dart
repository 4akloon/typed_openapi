import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

void main() {
  PresetDetection detect(Map<String, Object?> root) =>
      const PresetDetector().detect(root);

  Map<String, Object?> operation(String id) => {
    'paths': {
      '/p': {
        'get': {'operationId': id},
      },
    },
  };

  Map<String, Object?> schemas(List<String> names) => {
    'components': {
      'schemas': {for (final n in names) n: <String, Object?>{}},
    },
  };

  test('a Controller_method operationId is NestJS', () {
    final detection = detect(operation('AppController_getHello'));
    expect(detection.preset, Preset.nestjs);
    expect(detection.reason, contains('AppController_getHello'));
    expect(detection.isFramework, isTrue);
  });

  test('an empty info.contact is NestJS, a filled one is not', () {
    expect(
      detect({
        'info': {'contact': {}},
      }).preset,
      Preset.nestjs,
    );
    expect(
      detect({
        'info': {
          'contact': {'name': 'x'},
        },
      }).preset,
      Preset.generic,
    );
  });

  test('an id that only looks like a controller is not NestJS', () {
    expect(detect(operation('controller_getHello')).preset, Preset.generic);
  });

  test('both 422 schemas are FastAPI, one alone is not', () {
    expect(
      detect(schemas(['HTTPValidationError', 'ValidationError'])).preset,
      Preset.fastapi,
    );
    expect(detect(schemas(['HTTPValidationError'])).preset, Preset.generic);
    expect(detect(schemas(['ValidationError'])).preset, Preset.generic);
  });

  test('the default title or server of springdoc is springdoc', () {
    expect(
      detect({
        'info': {'title': 'OpenAPI definition'},
      }).preset,
      Preset.springdoc,
    );
    expect(
      detect({
        'servers': [
          {'url': '/', 'description': 'Generated server url'},
        ],
      }).preset,
      Preset.springdoc,
    );
    expect(
      detect({
        'info': {'title': 'Pets'},
      }).preset,
      Preset.generic,
    );
  });

  test(
    'ProblemDetails with a text/json body is ASP.NET, either alone is not',
    () {
      final media = {
        'paths': {
          '/p': {
            'get': {
              'responses': {
                '200': {
                  'content': {'text/json': <String, Object?>{}},
                },
              },
            },
          },
        },
      };
      expect(
        detect({
          ...media,
          ...schemas(['ProblemDetails']),
        }).preset,
        Preset.aspnet,
      );
      expect(detect(schemas(['ProblemDetails'])).preset, Preset.generic);
      expect(detect(media).preset, Preset.generic);
    },
  );

  test('two frameworks together are generic and the reason names both', () {
    final detection = detect({
      ...operation('AppController_getHello'),
      ...schemas(['HTTPValidationError', 'ValidationError']),
    });
    expect(detection.preset, Preset.generic);
    expect(detection.reason, contains('nestjs and fastapi'));
  });

  test('a document with no marks is generic', () {
    final detection = detect({});
    expect(detection.preset, Preset.generic);
    expect(detection.reason, 'no framework marks were found');
  });

  test('values of the wrong type are no marks and never throw', () {
    expect(detect({'info': 5}).preset, Preset.generic);
    expect(detect({'paths': <Object?>[]}).preset, Preset.generic);
    expect(
      detect({
        'components': {'schemas': 3},
      }).preset,
      Preset.generic,
    );
    expect(detect({'servers': {}}).preset, Preset.generic);
    expect(
      detect({
        'paths': {
          '/p': [1],
          '/q': {'get': 4},
        },
        'servers': [3],
        'info': {'contact': <Object?>[], 'title': <Object?>[]},
      }).preset,
      Preset.generic,
    );
  });
}
