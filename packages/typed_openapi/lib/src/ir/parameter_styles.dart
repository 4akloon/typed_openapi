import '../model/operation.dart';

/// The styles OpenAPI allows for each placement of a parameter.
extension type const ParameterStyles(ParameterLocation placement) {
  /// The styles of each placement, the default style first (`style: cookie`
  /// is OpenAPI 3.2's second style for cookies); a `querystring` parameter
  /// has none.
  static const allowed = {
    ParameterLocation.path: [
      ParameterStyle.simple,
      ParameterStyle.label,
      ParameterStyle.matrix,
    ],
    ParameterLocation.query: [
      ParameterStyle.form,
      ParameterStyle.spaceDelimited,
      ParameterStyle.pipeDelimited,
      ParameterStyle.deepObject,
    ],
    ParameterLocation.header: [ParameterStyle.simple],
    ParameterLocation.cookie: [ParameterStyle.form, ParameterStyle.cookie],
  };
}
