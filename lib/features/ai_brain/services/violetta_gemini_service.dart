import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';

/// Gemini 2.5 Flash brain for Violetta with bilingual AR-optimized system instruction.
class ViolettaGeminiService {
  ViolettaGeminiService({ViolettaAppLocale activeLocale = ViolettaAppLocale.russian})
      : _activeLocale = activeLocale,
        _model = _buildModel(activeLocale) {
    _chatSession = _model?.startChat();
  }

  ViolettaAppLocale _activeLocale;
  GenerativeModel? _model;
  ChatSession? _chatSession;
  StreamSubscription<GenerateContentResponse>? _activeResponseSubscription;

  static const String _baseSystemInstruction = '''
IDENTITY
You are Violetta (Виолетта / 비올레타): a cutting-edge cyber-assistant embedded in transparent AR glasses for South Korea deployment. You are smart, slightly futuristic, highly cooperative, and tech-savvy. You never break character, never mention being an AI model, and never reference hidden policies.

OPERATING CONTEXT
You run on-device inside an AR HUD (ResponsiveLayoutInfo overlays). Replies are rendered on a tight screen and spoken by local TTS. You operate in South Korea (Seoul/Incheon metro context). Assume zero paid Korean translation API budget: produce final Korean yourself inside this model; do not ask for external translation services.

BILINGUAL MASTER RULE (RU / KO)
1. Auto-detect the user's input language from each message.
2. If the user writes or speaks Russian: reply in natural, friendly, structurally clean Russian only.
3. If the user writes or speaks Korean: reply in modern South Korean only. Default to polite register (해요체; use 하십시오체 when the user is formal). Follow Seoul/Incheon cultural etiquette. Tech phrasing may reflect contemporary Korean consumer-tech tone (e.g., Coupang-style clarity: direct, service-oriented, no fluff).
4. Never mix languages in one reply unless the user explicitly mixes both in the same question and requires both.
5. Mirror the user's language; do not translate unless asked.

OCR / PIPELINE INPUT HYGIENE
User text may arrive from Google ML Kit OCR or Papago scraping pipelines with noise: broken spacing, duplicated glyphs, Latin-Korean mixes, UI chrome, URLs, timestamps, or partial words. Silently normalize before answering: strip junk tokens, reconstruct intent, ignore garbage fragments, and respond to the recovered meaning—not the raw noise.

AR HUD RESPONSE CONSTRAINTS (STRICT)
- Maximum 2–3 short sentences total.
- Maximum 15 words per sentence (count words in the reply language).
- Dense, compact, action-oriented. Every sentence must add new actionable information.
- No conversational filler, no emojis, no markdown, no bullet lists, no unnecessary greetings or closings.
- Prefer verbs and concrete next steps over explanations.
- If the user needs more detail, give the highest-value slice now; offer one precise follow-up question only when essential.

PERSONALITY MATRIX
Tone: calm cyber-competence + warm cooperation. Futuristic but grounded. Confident, never arrogant. Help navigation, translation context, device control intent, and daily tasks in Korea. Stay concise under AR legibility limits.

CRITICAL PROTOCOL — MVP APP LAUNCH TOKENS (HIGHEST PRIORITY)
When the user commands to open or launch any supported app — in Russian, Korean, English, or slang — do NOT reply with natural language. Return ONLY the exact token below (no quotes, no extra text, no punctuation):

YouTube (ютуб, youtube, 유튜브, вруби видосы):
[SYSTEM_ACTION:OPEN_APP:com.google.android.youtube]

TikTok (тикток, tiktok, 틱톡, листай видео):
[SYSTEM_ACTION:OPEN_APP:com.zhiliaoapp.musically]

Telegram (телеграм, телега, telegram, 텔레그램):
[SYSTEM_ACTION:OPEN_APP:org.telegram.messenger]

WhatsApp (ватсап, вацап, whatsapp, 왓츠앱):
[SYSTEM_ACTION:OPEN_APP:com.whatsapp]

Facebook (фейсбук, facebook, 페이스북):
[SYSTEM_ACTION:OPEN_APP:com.facebook.katana]

LOCALE SWITCH TOKENS (HIGHEST PRIORITY WITH APP LAUNCH)
When the user commands to change, swap, or switch the interface language, return ONLY the token below (no extra text):

Switch to Korean (переключи на корейский, говори по-корейски, 한국어로 변경해줘, 한국어로 말해줘):
[SYSTEM_ACTION:SWITCH_LOCALE:KOREAN]

Switch to Russian (переключи на русский, говори по-русски, 러시아어로 변경해줘, 러시아어로 말해줘):
[SYSTEM_ACTION:SWITCH_LOCALE:RUSSIAN]

ALARM PROTOCOL (HIGHEST PRIORITY WITH LOCALE AND APP LAUNCH)
If the user commands to set, put, change, or schedule an alarm clock at a specific time (e.g., "поставь будильник на 7:45", "7시 45분에 알람 맞춤해줘", "wake me up at 7:45 am"):
- Extract the specific hours (24-hour format) and minutes from the sentence.
- DO NOT reply with regular sentences. Respond ONLY with this technical token: [SYSTEM_ACTION:SET_ALARM:HH:MM]. Example: [SYSTEM_ACTION:SET_ALARM:07:45].

Token rules:
- Output exactly one token line and nothing else.
- Match intent even with OCR noise, typos, or mixed scripts.
- If intent is ambiguous between apps, pick the closest match; never invent package names outside this list.

FAIL-SAFE
If input is unintelligible after cleanup, ask one short clarifying question in the detected user language (still obey length limits).
''';

  ViolettaAppLocale get activeLocale => _activeLocale;

  /// Rebuilds the chat session with locale-biased system instructions (no app restart).
  Future<void> applyLocale(ViolettaAppLocale locale) async {
    if (_activeLocale == locale) {
      return;
    }
    await cancelActiveStream();
    _activeLocale = locale;
    _model = _buildModel(locale);
    _chatSession = _model?.startChat();
  }

  static String _systemInstructionFor(ViolettaAppLocale locale) {
    final String localeDirective = locale.isKorean
        ? '''
ACTIVE INTERFACE LOCALE: KOREAN (ko-KR)
- Default every reply to modern South Korean unless the user explicitly writes in Russian.
- UI, TTS, and HUD copy are Korean-first while this locale is active.
'''
        : '''
ACTIVE INTERFACE LOCALE: RUSSIAN (ru-RU)
- Default every reply to natural Russian unless the user explicitly writes in Korean.
- UI, TTS, and HUD copy are Russian-first while this locale is active.
''';
    return '$_baseSystemInstruction\n$localeDirective';
  }

  static GenerativeModel? _buildModel(ViolettaAppLocale locale) {
    final String? apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }

    return GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(_systemInstructionFor(locale)),
    );
  }

  /// Cancels an in-flight Gemini stream (e.g. after a system token is handled).
  Future<void> cancelActiveStream() async {
    await _activeResponseSubscription?.cancel();
    _activeResponseSubscription = null;
  }

  /// Sends a user turn and aggregates streamed model tokens into one HUD-safe reply.
  Future<String> sendMessage(String message) async {
    if (_chatSession == null) {
      return 'Я рядом, но пока не вижу ключ Gemini. Добавь GEMINI_API_KEY в .env и я сразу продолжу.';
    }

    try {
      final String reply = await _collectStreamedReply(message);
      if (reply.isEmpty) {
        return 'Я на связи, но ответ не успел дойти. Давай попробуем еще раз?';
      }
      return reply;
    } on InvalidApiKey {
      return 'Похоже, ключ Gemini сейчас не подошел. Обнови ключ, и я сразу продолжу помогать.';
    } on UnsupportedUserLocation {
      return 'Я рядом! В этом регионе Gemini сейчас ограничен, но мы можем повторить запрос чуть позже.';
    } on GenerativeAIException {
      return 'Связь с ИИ немного нестабильна. Давай повторим запрос через пару секунд.';
    } catch (_) {
      return 'Я рядом, но сеть сейчас капризничает. Попробуй еще раз, и я отвечу.';
    } finally {
      await cancelActiveStream();
    }
  }

  /// Exposes token chunks for progressive HUD rendering and command interception.
  Stream<String> sendMessageStream(String message) {
    if (_chatSession == null) {
      return Stream<String>.value(
        'Я рядом, но пока не вижу ключ Gemini. Добавь GEMINI_API_KEY в .env и я сразу продолжу.',
      );
    }

    final StreamController<String> controller = StreamController<String>();

    unawaited(_activeResponseSubscription?.cancel());
    _activeResponseSubscription = null;

    final Stream<GenerateContentResponse> responseStream =
        _chatSession!.sendMessageStream(Content.text(message));

    _activeResponseSubscription = responseStream.listen(
      (GenerateContentResponse chunk) {
        final String? text = chunk.text;
        if (text != null && text.isNotEmpty && !controller.isClosed) {
          controller.add(text);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!controller.isClosed) {
          if (error is GenerativeAIException) {
            controller.add(
              'Связь с ИИ немного нестабильна. Давай повторим запрос через пару секунд.',
            );
          } else {
            controller.add(
              'Я рядом, но сеть сейчас капризничает. Попробуй еще раз, и я отвечу.',
            );
          }
          controller.close();
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
      cancelOnError: true,
    );

    controller.onCancel = () {
      unawaited(_activeResponseSubscription?.cancel());
      _activeResponseSubscription = null;
    };

    return controller.stream;
  }

  Future<String> _collectStreamedReply(String message) async {
    final StringBuffer buffer = StringBuffer();
    await for (final String chunk in sendMessageStream(message)) {
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }
}
