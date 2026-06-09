import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

class AudioProcessorService {
  final SoLoud _soloud = SoLoud.instance;

  SoundHandle? _currentHandle;
  AudioSource? _currentSource;

  Future<void> init() async {
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
  }

  Future<void> playVoiceWithEffects(
    String filePath, {
    double pitch = 1.0,
  }) {
    return _playVoiceWithEffects(filePath, pitch: pitch);
  }

  Future<void> _playVoiceWithEffects(
    String filePath, {
    required double pitch,
  }) async {
    if (!_soloud.isInitialized) {
      await init();
    }

    await _stopCurrentPlayback();

    final AudioSource sound = await _soloud.loadFile(filePath);

    sound.filters.robotizeFilter.activate();
    sound.filters.biquadFilter.activate();

    final SoundHandle handle = await _soloud.play(sound);
    _currentHandle = handle;
    _currentSource = sound;

    _soloud.setRelativePlaySpeed(handle, pitch);

    sound.filters.robotizeFilter.wet(soundHandle: handle).value = 0.75;
    sound.filters.robotizeFilter.frequency(soundHandle: handle).value = 45;
    sound.filters.robotizeFilter.waveform(soundHandle: handle).value = 2;

    sound.filters.biquadFilter.type(soundHandle: handle).value = 2;
    sound.filters.biquadFilter.frequency(soundHandle: handle).value = 1800;
    sound.filters.biquadFilter.resonance(soundHandle: handle).value = 4;
    sound.filters.biquadFilter.wet(soundHandle: handle).value = 0.35;

    final Completer<void> playbackCompleter = Completer<void>();

    sound.allInstancesFinished.first.then((_) async {
      if (_currentSource == sound) {
        _currentHandle = null;
        _currentSource = null;
      }
      await _soloud.disposeSource(sound);
      if (!playbackCompleter.isCompleted) {
        playbackCompleter.complete();
      }
    });

    return playbackCompleter.future;
  }

  Future<void> stopPlayback() => _stopCurrentPlayback();

  Future<void> dispose() async {
    await _stopCurrentPlayback();

    if (_soloud.isInitialized) {
      _soloud.deinit();
    }
  }

  Future<void> _stopCurrentPlayback() async {
    final SoundHandle? handle = _currentHandle;
    if (handle != null && _soloud.getIsValidVoiceHandle(handle)) {
      await _soloud.stop(handle);
    }

    final AudioSource? source = _currentSource;
    if (source != null) {
      await _soloud.disposeSource(source);
    }

    _currentHandle = null;
    _currentSource = null;
  }
}
