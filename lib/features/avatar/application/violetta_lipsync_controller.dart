import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:violetta_app/features/voice_output/data/services/local_tts_service.dart';

/// Bridges on-device TTS playback with [Violetta3DRenderEngine.mouthVolume].
///
/// Prefers a native RMS / decibel stream when available. Otherwise drives a
/// phoneme-shaped speech envelope that tracks utterance progress and rate.
class ViolettaLipsyncController extends ChangeNotifier {
  static const Duration _envelopeTick = Duration(milliseconds: 50);
  static const Duration _smoothTick = Duration(milliseconds: 16);
  static const double _attackLerp = 0.42;
  static const double _decayLerp = 0.14;
  static const double _silenceThreshold = 0.004;

  final math.Random _random = math.Random();

  double _currentMouthVolume = 0.0;
  double _targetAmplitude = 0.0;
  double _smoothedAmplitude = 0.0;

  Timer? _envelopeTimer;
  Timer? _smoothTimer;
  StreamSubscription<double>? _amplitudeSubscription;

  bool _isSpeaking = false;
  bool _usesNativeAmplitude = false;
  double _speechRate = 0.5;
  int _elapsedEnvelopeMs = 0;
  int _syllablePeriodMs = 145;
  int _phonemeStep = 0;
  double _progressHint = 0.45;

  LocalTtsService? _ttsService;

  /// Low-pass filtered mouth opening in `[0.0, 1.0]`.
  double get currentMouthVolume => _currentMouthVolume;

  bool get isSpeaking => _isSpeaking;

  /// Binds lifecycle hooks on [tts]. Safe to call once per service instance.
  void attach(LocalTtsService tts) {
    if (!identical(_ttsService, tts)) {
      detach();
      _ttsService = tts;
    }

    tts.onSpeechStarted = _handleSpeechStarted;
    tts.onSpeechEnded = _handleSpeechEnded;
    tts.onSpeechProgress = _handleSpeechProgress;
  }

  void detach() {
    _ttsService
      ?..onSpeechStarted = null
      ..onSpeechEnded = null
      ..onSpeechProgress = null;
    _ttsService = null;
  }

  /// Optional hook for a native PCM/RMS stream exposed by platform TTS code.
  void bindAmplitudeStream(Stream<double> amplitudeStream) {
    _amplitudeSubscription?.cancel();
    _usesNativeAmplitude = true;
    _amplitudeSubscription = amplitudeStream.listen(
      ingestAmplitudeSample,
      onError: (_) => _fallbackToEnvelope(),
      onDone: _fallbackToEnvelope,
    );
  }

  /// Accepts RMS `[0..1]`, linear amplitude, or decibels `[-80..0]`.
  void ingestAmplitudeSample(double sample) {
    if (!_isSpeaking) {
      return;
    }

    _usesNativeAmplitude = true;
    _targetAmplitude = _normalizeAmplitude(sample);
  }

  void _handleSpeechStarted(TtsSpeechSession session) {
    _speechRate = session.speechRate;
    _elapsedEnvelopeMs = 0;
    _phonemeStep = 0;
    _progressHint = 0.45;
    _syllablePeriodMs = _estimateSyllablePeriodMs(session.text, session.speechRate);
    _isSpeaking = true;

    if (!_usesNativeAmplitude) {
      _targetAmplitude = 0.18;
      _startEnvelopeLoop();
    }
    _startSmoothingLoop();
    notifyListeners();
  }

  void _handleSpeechProgress(
    String text,
    int start,
    int end,
    String word,
  ) {
    if (!_isSpeaking) {
      return;
    }

    final String grapheme = _extractActiveGrapheme(text, start, end, word);
    _progressHint = _phonemeOpenness(grapheme);
    if (!_usesNativeAmplitude) {
      _targetAmplitude = _blendEnvelopeWithHint(_computeEnvelopeTarget(), _progressHint);
    }
  }

  void _handleSpeechEnded() {
    _isSpeaking = false;
    _targetAmplitude = 0.0;
    _stopEnvelopeLoop();
    _startSmoothingLoop();
  }

  void _fallbackToEnvelope() {
    _usesNativeAmplitude = false;
    if (_isSpeaking) {
      _startEnvelopeLoop();
    }
  }

  void _startEnvelopeLoop() {
    _envelopeTimer?.cancel();
    _envelopeTimer = Timer.periodic(_envelopeTick, (Timer timer) {
      if (!_isSpeaking || _usesNativeAmplitude) {
        return;
      }

      _elapsedEnvelopeMs += _envelopeTick.inMilliseconds;
      if (_elapsedEnvelopeMs >= _syllablePeriodMs) {
        _elapsedEnvelopeMs = 0;
        _phonemeStep++;
      }

      _targetAmplitude = _blendEnvelopeWithHint(
        _computeEnvelopeTarget(),
        _progressHint,
      );
    });
  }

  void _stopEnvelopeLoop() {
    _envelopeTimer?.cancel();
    _envelopeTimer = null;
  }

  void _startSmoothingLoop() {
    if (_smoothTimer != null) {
      return;
    }

    _smoothTimer = Timer.periodic(_smoothTick, (Timer timer) {
      final double lerpFactor =
          _targetAmplitude >= _smoothedAmplitude ? _attackLerp : _decayLerp;
      final double? nextValue = lerpDouble(
        _smoothedAmplitude,
        _targetAmplitude,
        lerpFactor,
      );
      if (nextValue == null) {
        return;
      }

      _smoothedAmplitude = nextValue.clamp(0.0, 1.0);

      if (!_isSpeaking &&
          _targetAmplitude <= 0.0 &&
          _smoothedAmplitude <= _silenceThreshold) {
        _smoothedAmplitude = 0.0;
        _currentMouthVolume = 0.0;
        _stopSmoothingLoop();
        notifyListeners();
        return;
      }

      if ((_smoothedAmplitude - _currentMouthVolume).abs() >= 0.001) {
        _currentMouthVolume = _smoothedAmplitude;
        notifyListeners();
      }
    });
  }

  void _stopSmoothingLoop() {
    _smoothTimer?.cancel();
    _smoothTimer = null;
  }

  double _computeEnvelopeTarget() {
    const List<double> vowelOpenness = <double>[0.88, 0.76, 0.92, 0.68, 0.84];
    const List<double> consonantOpenness = <double>[0.11, 0.08, 0.24, 0.06, 0.16];
    const List<double> phaseWeights = <double>[0.58, 0.22, 0.14, 0.06];

    final int cycleIndex = _phonemeStep % 5;
    final double phaseRatio =
        (_elapsedEnvelopeMs / _syllablePeriodMs).clamp(0.0, 1.0);

    final double vowel = vowelOpenness[cycleIndex];
    final double consonant = consonantOpenness[cycleIndex];
    final double microWobble =
        math.sin((_elapsedEnvelopeMs + cycleIndex * 17) * 0.045) * 0.035;

    double openness;
    if (phaseRatio < phaseWeights[0]) {
      openness = lerpDouble(consonant, vowel, phaseRatio / phaseWeights[0])!;
    } else if (phaseRatio < phaseWeights[0] + phaseWeights[1]) {
      openness = vowel;
    } else if (phaseRatio < phaseWeights[0] + phaseWeights[1] + phaseWeights[2]) {
      final double t = (phaseRatio - phaseWeights[0] - phaseWeights[1]) /
          phaseWeights[2];
      openness = lerpDouble(vowel, consonant * 1.4, t)!;
    } else {
      openness = consonant;
    }

    final double speechRateBias = 0.92 + (_speechRate * 0.12);
    return (openness * speechRateBias + microWobble).clamp(0.0, 1.0);
  }

  double _blendEnvelopeWithHint(double envelope, double hint) {
    return (envelope * 0.58 + hint * 0.42).clamp(0.0, 1.0);
  }

  double _normalizeAmplitude(double sample) {
    if (sample.isNaN || sample.isInfinite) {
      return 0.0;
    }

    if (sample >= 0.0 && sample <= 1.0) {
      return sample.clamp(0.0, 1.0);
    }

    if (sample <= 0.0) {
      const double minDb = -80.0;
      const double maxDb = -8.0;
      final double clampedDb = sample.clamp(minDb, maxDb);
      return ((clampedDb - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    }

    return (math.log(sample + 1.0) / math.log(101.0)).clamp(0.0, 1.0);
  }

  int _estimateSyllablePeriodMs(String text, double speechRate) {
    final int graphemeCount = text.trim().length.clamp(1, 400);
    final int estimatedSyllables = math.max(1, (graphemeCount / 2.6).round());
    final double baseMs = 4300 / estimatedSyllables;
    final double rateFactor = 0.72 + speechRate.clamp(0.2, 1.0);
    return (baseMs / rateFactor).round().clamp(95, 220);
  }

  String _extractActiveGrapheme(
    String text,
    int start,
    int end,
    String word,
  ) {
    if (word.isNotEmpty) {
      return word[0].toLowerCase();
    }
    if (text.isEmpty || start < 0 || start >= text.length) {
      return ' ';
    }
    return text[start].toLowerCase();
  }

  double _phonemeOpenness(String grapheme) {
    const String vowels = 'aeiouyàáâãäåæèéêëìíîïòóôõöùúûüýÿ'
        'аеёиоуыэюя';
    const String fricatives = 'sfvzšžçhхфвszшщ';
    const String plosives = 'pbtdkgqпбтдкг';
    const String nasalsLiquids = 'mnlrljнмлрй';

    if (vowels.contains(grapheme)) {
      return 0.82 + _random.nextDouble() * 0.12;
    }
    if (fricatives.contains(grapheme)) {
      return 0.34 + _random.nextDouble() * 0.16;
    }
    if (plosives.contains(grapheme)) {
      return 0.06 + _random.nextDouble() * 0.1;
    }
    if (nasalsLiquids.contains(grapheme)) {
      return 0.42 + _random.nextDouble() * 0.14;
    }
    if (grapheme.trim().isEmpty) {
      return 0.05;
    }
    return 0.38;
  }

  @override
  void dispose() {
    detach();
    _stopEnvelopeLoop();
    _stopSmoothingLoop();
    _amplitudeSubscription?.cancel();
    super.dispose();
  }
}
