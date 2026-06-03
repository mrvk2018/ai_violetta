import 'package:speech_to_text/speech_to_text.dart';

class LocalSttService {
  final SpeechToText _speech = SpeechToText();
  bool _isAvailable = false;

  Future<bool> init() async {
    if (_isAvailable) {
      return true;
    }
    _isAvailable = await _speech.initialize(
      onError: (val) => print('STT Error: $val'),
      onStatus: (val) => print('STT Status: $val'),
    );
    return _isAvailable;
  }

  void startListening({
    required Function(String) onResult,
    required String localeId,
  }) async {
    final bool available = await init();
    if (available) {
      _speech.listen(
        onResult: (result) => onResult(result.recognizedWords),
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onDevice: true,
      );
    }
  }

  void stopListening() {
    _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
