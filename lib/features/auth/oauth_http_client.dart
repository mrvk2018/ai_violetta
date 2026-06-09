import 'package:http/http.dart' as http;

/// Injects `Authorization: Bearer` for Gemini BYOK requests via google_generative_ai.
class BearerAuthHttpClient extends http.BaseClient {
  BearerAuthHttpClient(this._accessToken, [http.Client? inner])
      : _inner = inner ?? http.Client();

  final String _accessToken;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
