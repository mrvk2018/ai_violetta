import 'dart:convert';

import 'package:dio/dio.dart';

class PapagoTranslatorService {
  PapagoTranslatorService({Dio? dio}) : _dio = dio ?? Dio();

  static const String _endpoint = 'https://papago.naver.com/apis/nmt/translate';
  static const String _mobileUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 '
      'Mobile/15E148 Safari/604.1';

  final Dio _dio;

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final String payload = Uri(
      queryParameters: <String, String>{
        'source': sourceLang,
        'target': targetLang,
        'text': text,
      },
    ).query;

    try {
      final Response<dynamic> response = await _dio.post(
        _endpoint,
        data: payload,
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'User-Agent': _mobileUserAgent,
            'Accept': 'application/json, text/plain, */*',
            'Origin': 'https://naver.com',
            'Referer': 'https://naver.com/',
            'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
          },
        ),
      );

      final String translatedText = _extractTranslatedText(response.data);
      return translatedText;
    } on DioException catch (error) {
      final String message =
          error.message ?? 'Network error while requesting Papago translation.';
      throw Exception(message);
    } catch (error) {
      throw Exception('Failed to translate text: $error');
    }
  }

  String _extractTranslatedText(dynamic responseData) {
    final dynamic decoded = _decodeResponse(responseData);

    if (decoded is Map<String, dynamic>) {
      final dynamic direct = decoded['translatedText'];
      if (direct is String && direct.isNotEmpty) {
        return direct;
      }

      final dynamic nestedMessage = decoded['message'];
      if (nestedMessage is Map<String, dynamic>) {
        final dynamic nestedResult = nestedMessage['result'];
        if (nestedResult is Map<String, dynamic>) {
          final dynamic translatedText = nestedResult['translatedText'];
          if (translatedText is String && translatedText.isNotEmpty) {
            return translatedText;
          }
        }
      }

      final dynamic nestedResult = decoded['result'];
      if (nestedResult is Map<String, dynamic>) {
        final dynamic translatedText = nestedResult['translatedText'];
        if (translatedText is String && translatedText.isNotEmpty) {
          return translatedText;
        }
      }
    }

    throw const FormatException('Translated text was not found in response JSON.');
  }

  dynamic _decodeResponse(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      return responseData;
    }

    if (responseData is String) {
      final dynamic decoded = jsonDecode(responseData);
      return decoded;
    }

    throw const FormatException('Unexpected response format from Papago endpoint.');
  }
}
