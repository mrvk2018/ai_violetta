import 'dart:convert';

import 'package:http/http.dart' as http;

class PapagoScrapingService {
  static final Uri _endpoint = Uri.parse(
    'https://papago.naver.com/apis/n2mt/translate',
  );

  Future<String> translate({
    required String text,
    String source = 'ko',
    String target = 'ru',
  }) async {
    try {
      final http.Response response = await http.post(
        _endpoint,
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        },
        body: <String, String>{
          'deviceId': 'violetta-hud-device',
          'dict': 'true',
          'dictDisplay': '3',
          'honorific': 'false',
          'instant': 'false',
          'paging': 'false',
          'source': source,
          'target': target,
          'text': text,
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Papago status ${response.statusCode}');
      }

      final dynamic data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final dynamic translatedText = data['translatedText'];
        if (translatedText is String && translatedText.isNotEmpty) {
          return translatedText;
        }
      }

      throw const FormatException('Papago JSON schema changed');
    } catch (_) {
      return '$text\n\nВиолетта: переводчик сейчас недоступен, но я рядом и продолжаю помогать.';
    }
  }
}
