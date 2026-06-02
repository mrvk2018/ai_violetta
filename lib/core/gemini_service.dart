import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  final List<String> _apiKeys = <String>[
    'KEY_1',
    'KEY_2',
    'KEY_3',
  ];

  int _currentKeyIndex = 0;

  String _getNextKey() {
    final String key = _apiKeys[_currentKeyIndex];
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    return key;
  }

  Future<String> generateResponse(String prompt) async {
    for (int attempt = 0; attempt < _apiKeys.length; attempt++) {
      final GenerativeModel model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _getNextKey(),
      );

      try {
        final GenerateContentResponse response =
            await model.generateContent(<Content>[Content.text(prompt)]);
        final String? text = response.text?.trim();
        if (text != null && text.isNotEmpty) {
          return text;
        }
        throw GenerativeAIException('Gemini returned an empty response.');
      } on GenerativeAIException catch (error) {
        if (_isRateLimitError(error.message) && attempt < _apiKeys.length - 1) {
          continue;
        }
        rethrow;
      }
    }

    throw GenerativeAIException(
      'All Gemini API keys are temporarily unavailable.',
    );
  }

  bool _isRateLimitError(String message) {
    final String normalized = message.toLowerCase();
    return normalized.contains('429') ||
        normalized.contains('rate limit') ||
        normalized.contains('resource exhausted') ||
        normalized.contains('quota');
  }
}
