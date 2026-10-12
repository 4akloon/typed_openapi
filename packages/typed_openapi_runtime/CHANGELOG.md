## 0.0.1 - Unreleased

### Added
- `Patch<T>` for three-state request fields.
- `JsonReader`, `JsonDecodeException` and `JsonValue`: strict JSON decoding
  that reports the JSON pointer of the first mismatch.
- `Date` for `format: date`, with `JsonReader.asDate`.
- `Result<T, E>` with `Success`, `HttpError`, `UndocumentedStatus`,
  `DecodeError`, `TransportError` and `Cancelled`.
- Encoders for OpenAPI path, query, header and cookie parameter styles.
- `OperationInfo`, `OperationRequest` and `RawResponse`.
- `DioRequestSender` and `CallOptions`: requests through the user's Dio.
- `SseDecoder` (WHATWG event stream format), `SseItemDecoder` and the
  `SseItem` stream items; `DioRequestSender.openEvents`.
- For generated models: `DeepEquality` (deep `==` and `hashCode` of lists,
  maps and patches), `JsonReader.constant`, `JsonReader.additional`,
  `JsonReader.asBytes`, and `immutable` re-exported from `package:meta`.
- For generated operations: `FileUpload` (bytes or a stream, with a file
  name and a media type), `FormBody` and `FormEncoding`
  (`application/x-www-form-urlencoded` with the spec's `encoding`),
  `MultipartBody` (also `MultipartBody.fromJson`) and `MultipartPart`
  (a file part takes the spec's media type when the file has none);
  `DioRequestSender` turns them into
  what Dio sends, so generated signatures have no Dio types.
- Security metadata for interceptors: `OperationInfo.security` with
  `SecurityUse`, `SecurityScheme`, `SecuritySchemeType` (with `unknown` for
  a scheme the spec names but does not define) and `SecurityLocation`.
- `RawResponse.parsedJson` (a JSON error body of a text or binary
  operation), `RawResponse.text` of a body read as bytes, a depth check in
  `RawResponse.parse`, and `OperationRequest.pathVariable`, the one pattern
  of a path variable (`{}` is a variable with an empty name).
