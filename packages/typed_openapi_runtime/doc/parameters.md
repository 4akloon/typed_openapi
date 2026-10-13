# Parameters

A generated method builds an `OperationRequest` from its arguments, and the
runtime encodes them: `PathParameter` into the path, `QueryParameter` into
the query string, `HeaderParameter` into headers and `CookieParameter` into
one `Cookie` header. Encoding follows the OpenAPI `style` and `explode`
rules, RFC 6570 expansion and RFC 3986 percent-encoding. You rarely build
these yourself, but the tables below tell you exactly what goes on the wire.

```dart
const op = OperationInfo(
  operationId: 'x', method: 'GET', pathTemplate: '/users/{id}/files/{name}',
);
OperationRequest(
  op,
  path: const [PathParameter('id', 7), PathParameter('name', 'a b.txt')],
  query: const [
    QueryParameter('tags', ['x', 'y']),
    QueryParameter('skip', null),          // undefined: not sent
    QueryParameter('limit', 10),
  ],
  headers: const [HeaderParameter('X-Trace', 'abc'), HeaderParameter('X-None', null)],
  cookies: const [CookieParameter('session', 'abc'), CookieParameter('theme', 'dark')],
).resolvePath();
// /users/7/files/a%20b.txt?tags=x&tags=y&limit=10
// resolveHeaders(): {X-Trace: abc, Cookie: session=abc; theme=dark}
```

Parameter values are the **JSON form** of the value (`toJson` already
applied): `null`, a `String`, a `num`, a `bool`, a list of those, or a
string-keyed map of those. Anything else - a `DateTime`, a nested list or
object, `NaN` or an infinity - throws `ArgumentError`
(`Not a finite JSON scalar; convert parameter values with toJson`, or
`nested objects/arrays are not supported in a form parameter`).

`null` items of a list and `null` values of a map are skipped. A `null`, an
empty list and an empty map are **undefined**: the parameter is not sent.

## Path parameters

`PathParameter(name, value, {style = simple, explode = false})` replaces
`{name}` in the template. Every character but the unreserved ones
(`A-Z a-z 0-9 - . _ ~`) is percent-encoded as UTF-8 with upper-case hex, so a
value can never add a path segment: `a b/c?d#é` becomes
`a%20b%2Fc%3Fd%23%C3%A9`.

Inputs below: scalar `blue`, list `[blue, black, brown]`, object
`{R: 100, G: 200, B: 150}`, parameter name `color`. All outputs are from the
real encoder.

| Style | Explode | Scalar | List | Object |
| --- | --- | --- | --- | --- |
| `simple` (default) | `false` (default) | `blue` | `blue,black,brown` | `R,100,G,200,B,150` |
| `simple` | `true` | `blue` | `blue,black,brown` | `R=100,G=200,B=150` |
| `label` | `false` | `.blue` | `.blue,black,brown` | `.R,100,G,200,B,150` |
| `label` | `true` | `.blue` | `.blue.black.brown` | `.R=100.G=200.B=150` |
| `matrix` | `false` | `;color=blue` | `;color=blue,black,brown` | `;color=R,100,G,200,B,150` |
| `matrix` | `true` | `;color=blue` | `;color=blue;color=black;color=brown` | `;R=100;G=200;B=150` |

### Values that throw

A client drops an empty path segment (`//`) and normalizes `.` and `..`
away, and percent-encoding does not help, so a value that would change the
path throws `ArgumentError` instead of silently turning
`/users/{id}/sessions` into `/users/sessions`:

- the expansion is empty: `''`, `null`, an empty list or map, or a list of
  one empty string with `simple`;
- the expansion is a dot segment (`.` or `..`): `label` of `''`, or of two
  empty strings with explode;
- a scalar, a list item, an object key or a property value is exactly `.` or
  `..`.

```text
A path parameter value cannot be empty: it would change the request path
A path parameter value cannot be a dot segment ("."): it would change the request path
A path parameter value cannot be a dot segment (".."): it would change the request path
```

Neighbours are valid: `.a`, `a..b`, `...`, `.a.b` (`label` of `a` and `b`)
and `;id` (`matrix` of `''`). A placeholder with no parameter at all
(`{name}` in the template but no `PathParameter('name', ...)`) is a mistake
of the calling code and throws `ArgumentError`: `No value for {name}`. These
are thrown from the method, before any request is sent; they are `Error`s and
are not turned into a `Result` ([Results and errors](results_and_errors.md)).

## Query parameters

`QueryParameter(name, value, {style = form, explode, allowReserved = false})`.
The default `explode` is `true` for `form` and `false` for the other styles.
The result is the `name=value` pairs joined by `&`; `OperationRequest`
drops undefined (empty) ones and joins the rest in order.

| Style | Explode | Scalar | List | Object |
| --- | --- | --- | --- | --- |
| `form` (default) | `true` (default) | `color=blue` | `color=blue&color=black&color=brown` | `R=100&G=200&B=150` |
| `form` | `false` | `color=blue` | `color=blue,black,brown` | `color=R,100,G,200,B,150` |
| `spaceDelimited` | `false` | `color=blue` | `color=blue%20black%20brown` | `color=R%20100%20G%20200%20B%20150` |
| `spaceDelimited` | `true` | `color=blue` | `color=blue&color=black&color=brown` | `R=100&G=200&B=150` |
| `pipeDelimited` | `false` | `color=blue` | `color=blue%7Cblack%7Cbrown` | `color=R%7C100%7CG%7C200%7CB%7C150` |
| `pipeDelimited` | `true` | `color=blue` | `color=blue&color=black&color=brown` | `R=100&G=200&B=150` |
| `deepObject` | `true` | throws | throws | `color%5BR%5D=100&color%5BG%5D=200&color%5BB%5D=150` |

`deepObject` serializes objects only; a scalar or a list throws
`ArgumentError: deepObject serializes objects only`. The brackets are
percent-encoded (`%5B`, `%5D`), as RFC 3986 requires.

Other rules:

- Numbers and booleans are written in their JSON form: `1.5`, `true`, `42`.
- An empty string is `name=`; an empty list item is `name=` too
  (`['', 'x']` gives `e=&e=x`).
- Names are percent-encoded too.

### `allowReserved`

By default everything but unreserved characters is percent-encoded.
`allowReserved: true` keeps the reserved characters that are safe in a query
value (`: / ? @ ! $ ' ( ) * , ;`) and valid `%XX` triplets, while `[ ] #` and
`& = +` stay encoded, as OpenAPI 3.2 requires for the query.

```text
q=a b&c=d+e/é  default       -> q=a%20b%26c%3Dd%2Be%2F%C3%A9
q=a b&c=d+e/é  allowReserved -> q=a%20b%26c%3Dd%2Be/%C3%A9
next=/a//b?x=1#frag[1]       -> next=/a//b?x%3D1%23frag%5B1%5D
100%25 100%zz  allowReserved -> q=100%25%20100%25zz     (a valid triplet is kept, a bad one is encoded)
```

> **Note:** Dio collapses every `//` of the finished URL, query included.
> When a query holds `//` (the `next=/a//b` above) and the base URL is
> absolute, the runtime joins the base URL itself so the value is kept.
> Interceptors still see the finished URL.

## Header parameters

`HeaderParameter(name, value, {explode = false})` uses the `simple` style.
The result is `null` (no header) for an undefined value.

| Explode | Scalar | List | Object |
| --- | --- | --- | --- |
| `false` (default) | `blue` | `blue,black,brown` | `R,100,G,200,B,150` |
| `true` | `blue` | `blue,black,brown` | `R=100,G=200,B=150` |

Values are not percent-encoded, except what a header line cannot carry:
control characters and non-ASCII are percent-encoded (`plain text, é\n`
becomes `plain text, %C3%A9%0A`). The header parameters `Accept`,
`Content-Type` and `Authorization` are not generated as parameters (OpenAPI
says they are defined elsewhere); use the request's content type,
[`CallOptions.headers`](getting_started.md#4-calloptions) or an interceptor.
A header in `CallOptions.headers` wins over a header parameter of the same
name, case-insensitively; a `null` value in `CallOptions.headers` is not
sent.

## Cookie parameters

`CookieParameter(name, value, {explode = true})` gives one or more
`name=value` pairs of the `Cookie` header, percent-encoded; all cookie
parameters of a request are joined by `; ` into one header.

| Explode | Scalar | List | Object |
| --- | --- | --- | --- |
| `true` (default) | `color=blue` | `color=blue; color=black; color=brown` | `R=100; G=200; B=150` |
| `false` | `color=blue` | `color=blue,black,brown` | `color=R,100,G,200,B,150` |

> **Gotcha:** Browsers do not let a page set the `Cookie` header, so cookie
> parameters do nothing on the web: the browser keeps its own cookies and
> sends them itself, subject to its credentials settings. A Chrome test pins
> it (see [Web and platforms](web_and_platforms.md#cookies)).

## Defaults

A parameter's schema `default` is documented in the generated method but not
sent: the runtime sends what the method passes, and undefined values are
left out. If the server should see a default, pass it.

## See also

- [Request bodies](request_bodies.md) - form bodies use the query encoder.
- [Results and errors](results_and_errors.md) - why `ArgumentError` is not a `Result`.
- How the generator maps parameters:
  [generated operations](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/operations.md).
