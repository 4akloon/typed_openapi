# Client for a 3.1 service

This page takes a service that publishes an OpenAPI 3.1 document and builds a typed Dart client for it: install, configure, check, generate, call, and keep the client in step when the spec changes. A 3.1 document is read as it is, with a nullable written as a type list and the `application/problem+json` error body of RFC 9457.

> **Note:** The spec below is a small sample written for this page. It says nothing about the real API of any service called `grund`. Replace `specs/grund.yaml` with the service's own document and run the same commands. The output shown was produced from the sample.

## The sample spec

`specs/grund.yaml` has one operation. `note` is a nullable string written as a 3.1 type list, `status` is an enum, `itemId` is a path variable, and the 404 body is `application/problem+json`:

```yaml
openapi: 3.1.0
info:
  title: Sample service
  version: "1.0"
servers:
  - url: http://localhost:8080
paths:
  /items/{itemId}:
    get:
      operationId: getItem
      tags: [items]
      parameters:
        - name: itemId
          in: path
          required: true
          schema: {type: string}
      responses:
        "200":
          description: The item.
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Item"}
        "404":
          description: No such item.
          content:
            application/problem+json:
              schema: {$ref: "#/components/schemas/Problem"}
components:
  schemas:
    Item:
      type: object
      required: [id, name, status]
      properties:
        id: {type: string}
        name: {type: string}
        note:
          type: [string, "null"]
          description: A free-text note, null when there is none.
        status:
          type: string
          enum: [active, retired]
    Problem:
      type: object
      required: [title, status]
      properties:
        title: {type: string}
        status: {type: integer}
        detail: {type: string}
```

## Install

Add the packages from pub.dev (to follow `main` instead, use git dependencies as in the [README](../README.md#install)):

```sh
dart pub add typed_openapi_client typed_openapi_dio
dart pub add --dev typed_openapi
```

The first line adds the packages the app runs with: `typed_openapi_client` is what the generated code imports, `typed_openapi_dio` sends the requests through your `Dio`. The second adds the generator, which is only a development tool. The sample project of this page used path dependencies on a checkout, before the packages were published; the commands that follow were run there.

## Config

`typed_openapi.yaml` next to `pubspec.yaml` declares one client, `grund`. See [Configuration](configuration.md) for every key.

```yaml
clients:
  grund:
    input: specs/grund.yaml
    output: lib/src/grund
```

## Check, then generate

`check` reads the spec and reports problems without writing; `generate` checks again and writes the client. A clean 3.1 document has nothing to report:

```text
$ dart run typed_openapi check
errors: 0, warnings: 0, infos: 0
$ dart run typed_openapi generate
errors: 0, warnings: 0, infos: 0
Generated grund in lib/src/grund: 7 files, 7 written, 0 deleted.
API of grund: first snapshot in typed_openapi.lock.
```

The seven files are `grund.dart` (the client), `api.dart` and `api/items_api.dart` (the `items` group, from the operation's tag), and `models.dart` with `models/item.dart`, `models/item_status.dart` and `models/problem.dart`. Commit them together with `typed_openapi.lock`, which records the API and the names (see [Generated output](generate_output.md)).

## Use the client

The program below calls the client twice, once for an item that exists and once for one that does not. It starts a small `HttpServer` of its own as a stand-in for the service, so it runs alone; with the real service, leave the stand-in out and give `Dio` the service's base URL. The `switch` over the `Result` handles the success and the documented 404, which arrives as a typed `HttpError` with a `Problem` body, not as an exception.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:grund_sample/src/grund/grund.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

Future<void> main() async {
  final server = await _startStandIn();
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:${server.port}'));
  final client = GrundClient(DioTransport(dio));

  for (final id in ['a1', 'nope']) {
    switch (await client.items.getItem(itemId: id)) {
      case Success(:final data):
        stdout.writeln(
          '${data.name} is ${data.status.value}, note: ${data.note}',
        );
      case HttpError(:final body):
        stdout.writeln('${body.status}: ${body.title}');
      case Failure():
        stdout.writeln('request failed');
    }
  }
  await server.close();
}

// A stand-in for the service, so the example runs alone.
Future<HttpServer> _startStandIn() async {
  final server = await HttpServer.bind('localhost', 0);
  server.listen((request) {
    final found = request.uri.path == '/items/a1';
    request.response
      ..statusCode = found ? 200 : 404
      ..headers.contentType = ContentType.parse(
        found ? 'application/json' : 'application/problem+json',
      )
      ..write(
        jsonEncode(
          found
              ? {'id': 'a1', 'name': 'Lamp', 'note': null, 'status': 'active'}
              : {'title': 'No such item', 'status': 404},
        ),
      )
      ..close();
  });
  return server;
}
```

It printed:

```text
Lamp is active, note: null
404: No such item
```

`data.status.value` is the enum's JSON value; a value the spec does not list would arrive as `ItemStatusUnknown` instead of failing (see [Enums](generated/enums.md)). `Failure()` covers the rest: a status the spec does not document, a body that does not decode, a transport error, a cancel (see [Responses and errors](generated/responses_and_errors.md)).

## When the spec changes

The service adds `archived` to the enum: `enum: [active, retired, archived]`. Before regenerating, `diff` shows what that does to code that uses the client, and `generate --locked` (the check for CI) refuses to go on until the lock is updated:

```text
$ dart run typed_openapi diff --fail-on switch-breaking
grund: 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs.
  switch-breaking: Enum value ItemStatus.archived was added.
$ echo $?
1
$ dart run typed_openapi generate --locked
error TOA834 api-lock-differs: typed_openapi.lock differs from the API of client "grund": 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs. Run generate without --locked and commit the lock; typed_openapi diff lists the changes.
  --> typed_openapi.lock
  at #/clients/grund
errors: 1, warnings: 0, infos: 0
Skipped grund: its API differs from typed_openapi.lock (TOA834).
$ echo $?
1
```

`switch-breaking` means a `switch` over the enum that has no `default` stops compiling until it handles `archived`; that is what the exhaustive types are for. Run `dart run typed_openapi generate` (no `--locked`) to write the new client and lock, fix the `switch`es the analyzer points at, and commit. The workflow is in [Automation](automation.md).

## Check from Dart

The same check as `typed_openapi check`, from a script, using `typed_openapi_core` (a dev dependency; the generator depends on it). This is for a build script or a test that wants the diagnostics as data; see [Programmatic API](programmatic_api.md).

```dart
import 'dart:io';

import 'package:typed_openapi_core/typed_openapi_core.dart';

void main() {
  final diagnostics = DiagnosticBag();
  final config = ConfigLoader(diagnostics).load('typed_openapi.yaml');
  if (config != null) {
    SpecChecker(diagnostics).check(config);
  }
  stdout.writeln(const TextReporter().format(diagnostics));
  exitCode = diagnostics.hasErrors ? 1 : 0;
}
```

With the sample it prints `errors: 0, warnings: 0, infos: 0` and exits `0`. With the path variable renamed to `{id}` in the path only, it prints the findings and exits `1`:

```text
warning TOA501 missing-path-parameter: The path /items/{id} has {id}, but this operation declares no path parameter "id"; it is added as a required string path parameter.
  --> specs/grund.yaml:10:7
  at #/paths/~1items~1{id}/get
  fix: Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}.
error TOA502 path-parameter-not-in-template: Path parameter "itemId" is not in the path template /items/{id}.
  --> specs/grund.yaml:13:11
  at #/paths/~1items~1{id}/get/parameters/0
  fix: Make the parameter name and the template variable the same at the source; until then, override the name of this parameter.
errors: 1, warnings: 1, infos: 0
```

## What is not covered

The client builds requests and reads responses; everything about the connection is the transport's, which here is your `Dio`: authentication (the spec's security schemes are metadata only), retries, caching, timeouts and base URL. Constructs the generator does not turn into code, such as callbacks, per-operation servers and `in: querystring` parameters, are reported with a code and listed, with the proof for each, in the [support matrix](support_matrix.md).

## See also

- [Getting started](getting_started.md): the same path with a 3.0 spec.
- [Automation](automation.md): `diff` and `generate --locked` in a task, a hook and CI.
- [Support matrix](support_matrix.md): what is and is not read.
- [Generated client](generated/overview.md): the layout of what `generate` wrote.
