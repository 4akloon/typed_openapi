# typed_openapi example

A small pet shop: one OpenAPI 3.1 spec (`specs/petshop.yaml`) and the config
that generates a client from it (`typed_openapi.yaml`).

Run these in this directory:

```sh
dart run typed_openapi check      # errors: 0, warnings: 0, infos: 0
dart run typed_openapi generate   # writes lib/src/petshop
dart run typed_openapi diff       # what changed in the API since the last generate
```

The generated client needs `typed_openapi_client` and a transport, here
`typed_openapi_dio` over your `Dio`:

```dart
import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'src/petshop/petshop.dart';

Future<void> main() async {
  final client = PetshopClient(
    DioTransport(Dio(BaseOptions(baseUrl: 'https://api.example.com'))),
  );
  switch (await client.pets.getPet(id: 1)) {
    case Success(:final data):
      print(data.name);
    case HttpError(:final body):
      print(body.title);
    case Failure():
      print('the call failed');
  }
}
```

`Result` is a sealed type, so the `switch` must handle every outcome.
