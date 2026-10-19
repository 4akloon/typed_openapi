// Code in the shape the generator (M8, M9, M10) is expected to emit, to
// check that the runtime API composes. Illustrative, not a contract.
import 'package:typed_openapi_client/typed_openapi_client.dart';

/// `components.schemas.Tag`.
final class Tag {
  /// Creates a tag.
  const Tag({required this.name});

  /// Decodes a tag; throws [JsonDecodeException].
  factory Tag.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Tag');
    return Tag(name: r.required('name', JsonReader.asString));
  }

  /// `name`.
  final String name;

  /// Encodes the tag.
  Map<String, Object?> toJson() => {'name': name};
}

/// `components.schemas.Pet`.
final class Pet {
  /// Creates a pet.
  const Pet({
    required this.id,
    required this.name,
    required this.bornAt,
    this.birthday,
    this.tags,
    this.metadata = const JsonValue(null),
  });

  /// Decodes a pet; throws [JsonDecodeException].
  factory Pet.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Pet');
    return Pet(
      id: r.required('id', JsonReader.asInt),
      name: r.required('name', JsonReader.asString),
      bornAt: r.required('bornAt', JsonReader.asDateTime),
      birthday: r.optional('birthday', JsonReader.asDate),
      tags: r.optional(
        'tags',
        JsonReader.listOf(JsonReader.objectOf(Tag.fromJson)),
      ),
      metadata: r.optionalValue('metadata'),
    );
  }

  /// `id`.
  final int id;

  /// `name`.
  final String name;

  /// `bornAt`, `format: date-time`.
  final DateTime bornAt;

  /// `birthday`, `format: date`.
  final Date? birthday;

  /// `tags`.
  final List<Tag>? tags;

  /// `metadata`, any JSON.
  final JsonValue metadata;

  /// Encodes the pet; optional fields that are not set are not sent.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bornAt': bornAt.toUtc().toIso8601String(),
    'birthday': ?birthday?.toJson(),
    'tags': ?tags?.map((t) => t.toJson()).toList(),
    'metadata': ?metadata.raw,
  };
}

/// `components.schemas.UpdatePet`: the body of a PATCH, three-state fields.
final class UpdatePet {
  /// Creates a patch.
  const UpdatePet({this.name, this.tag});

  /// `name`.
  final Patch<String>? name;

  /// `tag`.
  final Patch<String>? tag;

  /// Encodes only the fields that are set.
  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
  };
}

/// `components.schemas.ApiError`, the error of every operation.
final class ApiError {
  /// Creates an error.
  const ApiError({required this.code});

  /// Decodes an error; throws [JsonDecodeException].
  factory ApiError.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'ApiError');
    return ApiError(code: r.required('code', JsonReader.asString));
  }

  /// `code`.
  final String code;
}

/// The data of one `text/event-stream` event of `watchPet`.
final class PetChange {
  /// Creates a change.
  const PetChange({required this.name});

  /// Decodes the data of one event; throws [JsonDecodeException].
  factory PetChange.fromEvent(SseMessage message) {
    final r = JsonReader(message.jsonObject, schema: 'PetChange');
    return PetChange(name: r.required('name', JsonReader.asString));
  }

  /// `name`.
  final String name;
}

/// The `pets` tag: a plain class, so `implements PetsApi` mocks it (R10.7).
class PetsApi {
  /// Calls the API through [transport].
  PetsApi(ClientTransport transport) : _sender = ClientSender(transport);

  final ClientSender _sender;

  static const _getPetById = OperationInfo(
    operationId: 'getPetById',
    method: 'GET',
    pathTemplate: '/pets/{petId}',
    tags: ['pets'],
  );

  static const _updatePet = OperationInfo(
    operationId: 'updatePet',
    method: 'PATCH',
    pathTemplate: '/pets/{petId}',
    tags: ['pets'],
  );

  static const _watchPet = OperationInfo(
    operationId: 'watchPet',
    method: 'GET',
    pathTemplate: '/pets/{petId}/changes',
    tags: ['pets'],
  );

  /// GET /pets/{petId}
  Future<Result<Pet, ApiError>> getPetById({
    required int petId,
    List<String>? fields,
    CallOptions? call,
  }) => _sender.send(
    OperationRequest(
      _getPetById,
      path: [PathParameter('petId', petId)],
      query: [QueryParameter('fields', fields, explode: false)],
    ),
    (r) => switch (r.statusCode) {
      200 => r.success(Pet.fromJson(r.jsonObject)),
      >= 400 && < 600 => r.error(ApiError.fromJson(r.jsonObject)),
      _ => r.undocumented(),
    },
    call: call,
  );

  /// PATCH /pets/{petId}
  Future<Result<void, ApiError>> updatePet({
    required int petId,
    required UpdatePet body,
    CallOptions? call,
  }) => _sender.send(
    OperationRequest(
      _updatePet,
      path: [PathParameter('petId', petId)],
      body: body.toJson(),
      contentType: 'application/json',
    ),
    (r) => switch (r.statusCode) {
      204 => r.success(null),
      >= 400 && < 600 => r.error(ApiError.fromJson(r.jsonObject)),
      _ => r.undocumented(),
    },
    call: call,
  );

  /// GET /pets/{petId}/changes, `text/event-stream`; no documented errors.
  Future<Result<Stream<SseItem<PetChange>>, Never>> watchPet({
    required int petId,
    CallOptions? call,
  }) => _sender.openEvents(
    OperationRequest(
      _watchPet,
      path: [PathParameter('petId', petId)],
      streamStatuses: const {200},
    ),
    PetChange.fromEvent,
    (r) => r.undocumented(),
    call: call,
  );
}
