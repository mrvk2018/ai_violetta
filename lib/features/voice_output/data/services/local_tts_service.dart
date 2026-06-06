import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsSpeechSession {
  final String text;
  final double speechRate;

  const TtsSpeechSession({
    required this.text,
    required this.speechRate,
  });
}

class LocalTtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _handlersRegistered = false;

  TtsSpeechSession? _pendingSession;
  VoidCallback? _completionHandler;

  void Function(TtsSpeechSession session)? onSpeechStarted;
  VoidCallback? onSpeechEnded;
  void Function(String text, int start, int end, String word)? onSpeechProgress;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      <IosTextToSpeechAudioCategoryOptions>[
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      ],
    );
    _registerHandlers();
    _isInitialized = true;
  }

  void _registerHandlers() {
    if (_handlersRegistered) {
      return;
    }

    _flutterTts.setStartHandler(() {
      final TtsSpeechSession? session = _pendingSession;
      if (session != null) {
        onSpeechStarted?.call(session);
      }
    });

    _flutterTts.setCompletionHandler(() {
      onSpeechEnded?.call();
      _pendingSession = null;
      _completionHandler?.call();
    });

    _flutterTts.setCancelHandler(() {
      onSpeechEnded?.call();
      _pendingSession = null;
    });

    _flutterTts.setProgressHandler((
      String text,
      int start,
      int end,
      String word,
    ) {
      onSpeechProgress?.call(text, start, end, word);
    });

    _handlersRegistered = true;
  }

  void setCompletionHandler(void Function() onComplete) {
    _completionHandler = onComplete;
  }

  Future<void> speak(String text, String languageCode) async {
    await init();
    await _flutterTts.setLanguage(languageCode);

    const double speechRate = 0.5;
    await _flutterTts.setSpeechRate(speechRate);
    await _flutterTts.setPitch(1.1);

    if (text.isEmpty) {
      return;
    }

    _pendingSession = TtsSpeechSession(text: text, speechRate: speechRate);
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    onSpeechEnded?.call();
    _pendingSession = null;
  }
}
