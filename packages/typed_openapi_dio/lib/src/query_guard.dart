/// Keeps a `//` in the query of a request target from Dio, which joins the
/// base URL and a relative path and then collapses every `//` of the whole
/// string, query included (`RequestOptions.uri`): an `allowReserved` value
/// such as `next=/a//b` would change.
final class QueryGuard {
  /// Creates the guard for the Dio's [baseUrl].
  const QueryGuard(this.baseUrl);

  /// The base URL of the user's Dio.
  final String baseUrl;

  /// What to pass to Dio for [target]: when its query holds `//`, the base
  /// URL is joined here, collapsing `//` in the path part only, and Dio
  /// leaves the absolute URL alone. Otherwise the relative target, so
  /// interceptors that change `baseUrl` keep working; interceptors see the
  /// finished URI either way.
  String target(String target) {
    final queryStart = target.indexOf('?');
    if (queryStart < 0 ||
        !target.substring(queryStart).contains('//') ||
        !_absolute.hasMatch(baseUrl)) {
      return target;
    }
    final joined = (baseUrl + target.substring(0, queryStart)).split(':/');
    final path = joined.length == 2
        ? '${joined[0]}:/${joined[1].replaceAll('//', '/')}'
        : joined.join(':/');
    return path + target.substring(queryStart);
  }

  static final RegExp _absolute = RegExp('^https?:');
}
