import 'package:flutter_tts/flutter_tts.dart';

class LocalTtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

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
    _isInitialized = true;
  }

  void setCompletionHandler(void Function() onComplete) {
    _flutterTts.setCompletionHandler(onComplete);
  }

  Future<void> speak(String text, String languageCode) async {
    await init();
    await _flutterTts.setLanguage(languageCode);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.1);

    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
