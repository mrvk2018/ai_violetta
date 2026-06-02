import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class ViolettaGeminiService {
  ViolettaGeminiService() : _model = _buildModel() {
    _chatSession = _model?.startChat();
  }

  static const String _systemPrompt =
      "Ты — Виолетта, кроссплатформенный AR-ассистент, помогающий пользователю в Южной Корее. "
      "Твой характер: заботливая, дружелюбная, общаешься как близкий друг, носишь стильную шапочку-бини. "
      "Твои ответы должны быть очень короткими и емкими (максимум 2-3 коротких предложения), так как они выводятся на AR-экран. "
      "Если пользователь прощается с тобой или диалог завершается, ты ОБЯЗАТЕЛЬНО должна закончить свой ответ одной из фраз: "
      "'Я рядышком, на связи! 🎧' или 'Я тут, в ушке! 🌸'.";

  final GenerativeModel? _model;
  ChatSession? _chatSession;

  static GenerativeModel? _buildModel() {
    final String? apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }

    return GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(_systemPrompt),
    );
  }

  Future<String> sendMessage(String message) async {
    if (_chatSession == null) {
      return 'Я рядом, но пока не вижу ключ Gemini. Добавь GEMINI_API_KEY в .env и я сразу продолжу.';
    }

    try {
      final GenerateContentResponse response =
          await _chatSession!.sendMessage(Content.text(message));
      final String? text = response.text?.trim();
      if (text == null || text.isEmpty) {
        return 'Я на связи, но ответ не успел дойти. Давай попробуем еще раз?';
      }
      return text;
    } on InvalidApiKey {
      return 'Похоже, ключ Gemini сейчас не подошел. Обнови ключ, и я сразу продолжу помогать.';
    } on UnsupportedUserLocation {
      return 'Я рядом! В этом регионе Gemini сейчас ограничен, но мы можем повторить запрос чуть позже.';
    } on GenerativeAIException {
      return 'Связь с ИИ немного нестабильна. Давай повторим запрос через пару секунд.';
    } catch (_) {
      return 'Я рядом, но сеть сейчас капризничает. Попробуй еще раз, и я отвечу.';
    }
  }
}
