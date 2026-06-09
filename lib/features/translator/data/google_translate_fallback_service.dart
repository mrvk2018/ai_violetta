import 'dart:convert';

import 'package:http/http.dart' as http;

/// Free unofficial Google Translate fallback when Naver/Papago BYOK keys are absent.
class GoogleTranslateFallbackService {
  GoogleTranslateFallbackService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> translate({
    required String text,
    required String source,
    required String target,
  }) async {
    final Uri uri = Uri.https(
      'translate.googleapis.com',
      '/translate_a/single',
      <String, String>{
        'client': 'gtx',
        'sl': source,
        'tl': target,
        'dt': 't',
        'q': text,
      },
    );

    final http.Response response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Google Translate status ${response.statusCode}');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic> || decoded.isEmpty) {
      throw const FormatException('Unexpected Google Translate payload');
    }

    final dynamic segments = decoded.first;
    if (segments is! List<dynamic>) {
      throw const FormatException('Google Translate segments missing');
    }

    final StringBuffer buffer = StringBuffer();
    for (final dynamic segment in segments) {
      if (segment is List<dynamic> && segment.isNotEmpty) {
        final dynamic piece = segment.first;
        if (piece is String && piece.isNotEmpty) {
          buffer.write(piece);
        }
      }
    }

    final String translated = buffer.toString().trim();
    if (translated.isEmpty) {
      throw const FormatException('Google Translate returned empty text');
    }
    return translated;
  }
}
