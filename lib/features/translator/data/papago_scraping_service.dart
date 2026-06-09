import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:violetta_app/features/auth/auth_service.dart';
import 'package:violetta_app/features/translator/data/google_translate_fallback_service.dart';

class PapagoScrapingService {
  PapagoScrapingService({
    AuthService? authService,
    http.Client? httpClient,
    GoogleTranslateFallbackService? googleFallback,
  })  : _authService = authService ?? AuthService.instance,
        _httpClient = httpClient ?? http.Client(),
        _googleFallback = googleFallback ?? GoogleTranslateFallbackService();

  static final Uri _scrapingEndpoint = Uri.parse(
    'https://papago.naver.com/apis/n2mt/translate',
  );

  static const String _officialEndpoint =
      'https://openapi.naver.com/v1/papago/n2mt';

  final AuthService _authService;
  final http.Client _httpClient;
  final GoogleTranslateFallbackService _googleFallback;

  Future<String> translate({
    required String text,
    String source = 'ko',
    String target = 'ru',
  }) async {
    if (_authService.hasNaverKeys) {
      try {
        return await _translateViaOfficialApi(
          text: text,
          source: source,
          target: target,
          clientId: _authService.naverClientId!,
          clientSecret: _authService.naverClientSecret!,
        );
      } on Object catch (error) {
        debugPrint('[BYOK] Papago official API failed: $error');
      }
    }

    try {
      return await _translateViaScraping(
        text: text,
        source: source,
        target: target,
      );
    } on Object catch (error) {
      debugPrint('[BYOK] Papago scraping failed: $error');
    }

    try {
      return await _googleFallback.translate(
        text: text,
        source: source,
        target: target,
      );
    } on Object catch (error) {
      debugPrint('[BYOK] Google Translate fallback failed: $error');
    }

    return '$text\n\nВиолетта: переводчик сейчас недоступен, но я рядом и продолжаю помогать.';
  }

  Future<String> _translateViaOfficialApi({
    required String text,
    required String source,
    required String target,
    required String clientId,
    required String clientSecret,
  }) async {
    final http.Response response = await _httpClient.post(
      Uri.parse(_officialEndpoint),
      headers: <String, String>{
        'X-Naver-Client-Id': clientId,
        'X-Naver-Client-Secret': clientSecret,
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
      body: <String, String>{
        'source': source,
        'target': target,
        'text': text,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Papago official status ${response.statusCode}');
    }

    final dynamic data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      final dynamic translatedText =
          data['message']?['result']?['translatedText'] ?? data['translatedText'];
      if (translatedText is String && translatedText.isNotEmpty) {
        return translatedText;
      }
    }

    throw const FormatException('Papago official JSON schema changed');
  }

  Future<String> _translateViaScraping({
    required String text,
    required String source,
    required String target,
  }) async {
    final http.Response response = await _httpClient.post(
      _scrapingEndpoint,
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
  }
}
