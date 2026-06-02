import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';

const List<String> _wakePhrases = <String>[
  'эй, виолетта',
  'хэй, виолетта',
];

class BackgroundWakeWordService {
  final FlutterBackgroundService _service = FlutterBackgroundService();

  Future<void> initializeService() async {
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: false,
        autoStart: true,
        autoStartOnBoot: true,
      ),
    );

    await _service.startService();
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  unawaited(_listenWakeWordLoop(service));
}

Future<void> _listenWakeWordLoop(ServiceInstance service) async {
  while (true) {
    // 1.5-second lightweight in-memory buffer simulation.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final String? detectedPhrase = _detectWakePhraseFromLocalBuffer();
    if (detectedPhrase == null) {
      continue;
    }

    // Signal app/UI wake-up event to the main isolate.
    service.invoke('wake_word_detected', <String, dynamic>{
      'phrase': detectedPhrase,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Android bridge can bring app to front (intent-like wake behavior).
    if (service is AndroidServiceInstance) {
      await service.openApp();
    }
  }
}

String? _detectWakePhraseFromLocalBuffer() {
  // TODO: Replace with on-device wake-word model over microphone PCM buffer.
  const String? recognizedText = null;
  if (recognizedText == null) {
    return null;
  }

  final String normalized = recognizedText.toLowerCase().trim();
  for (final String phrase in _wakePhrases) {
    if (normalized.contains(phrase)) {
      return phrase;
    }
  }
  return null;
}
