import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:violetta_app/features/auth/auth_service.dart';
import 'package:violetta_app/features/voice_output/data/services/local_tts_service.dart';

enum VoiceSynthesisBackend {
  elevenLabs,
  localTts,
}

class VoiceSynthesisResult {
  const VoiceSynthesisResult({
    required this.backend,
    this.audioStream,
  });

  final VoiceSynthesisBackend backend;
  final Stream<List<int>>? audioStream;

  bool get usedElevenLabs => backend == VoiceSynthesisBackend.elevenLabs;
  bool get usedLocalTts => backend == VoiceSynthesisBackend.localTts;
}

class ElevenLabsService {
  static const String _baseUrl = 'https://api.elevenlabs.io/v1';

  final Dio _dio;
  final AuthService _authService;

  ElevenLabsService({
    AuthService? authService,
    Dio? dio,
  })  : _authService = authService ?? AuthService.instance,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 2),
              ),
            );

  /// True when the signed-in user supplied a personal ElevenLabs API key (BYOK).
  bool get canUseElevenLabs {
    final String? key = _authService.userElevenLabsKey;
    return key != null && key.isNotEmpty;
  }

  String? get _resolvedApiKey {
    final String? userKey = _authService.userElevenLabsKey?.trim();
    if (userKey == null || userKey.isEmpty) {
      return null;
    }
    return userKey;
  }

  /// BYOK voice pipeline: ElevenLabs stream when user key exists, otherwise free LocalTts.
  Future<VoiceSynthesisResult> synthesizeSpeech({
    required String text,
    required String voiceId,
    required LocalTtsService fallbackTts,
    required String fallbackLocale,
  }) async {
    final String? apiKey = _resolvedApiKey;
    if (apiKey == null) {
      await fallbackTts.speak(text, fallbackLocale);
      return const VoiceSynthesisResult(
        backend: VoiceSynthesisBackend.localTts,
      );
    }

    final Stream<List<int>> stream =
        await _streamTextToSpeech(text, voiceId, apiKey: apiKey);
    return VoiceSynthesisResult(
      backend: VoiceSynthesisBackend.elevenLabs,
      audioStream: stream,
    );
  }

  Future<Stream<List<int>>> streamTextToSpeech(
    String text,
    String voiceId,
  ) async {
    final String? apiKey = _resolvedApiKey;
    if (apiKey == null) {
      throw StateError(
        'ElevenLabs BYOK key is not configured. Use synthesizeSpeech() for automatic LocalTts fallback.',
      );
    }
    return _streamTextToSpeech(text, voiceId, apiKey: apiKey);
  }

  Future<Stream<List<int>>> _streamTextToSpeech(
    String text,
    String voiceId, {
    required String apiKey,
  }) async {
    final Response<ResponseBody> response = await _dio.post<ResponseBody>(
      '/text-to-speech/$voiceId/stream',
      data: <String, dynamic>{
        'text': text,
        'model_id': 'eleven_multilingual_v2',
        'voice_settings': <String, double>{
          'stability': 0.5,
          'similarity_boost': 0.75,
        },
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, String>{
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
      ),
    );

    final ResponseBody? responseBody = response.data;
    if (responseBody == null) {
      throw StateError('ElevenLabs returned an empty audio stream.');
    }

    return responseBody.stream;
  }

  Future<String> saveStreamToTempFile(
    Stream<List<int>> audioStream, {
    String fileName = 'eleven_labs_tts.mp3',
  }) async {
    final Directory tempDirectory = await getTemporaryDirectory();
    final File outputFile = File('${tempDirectory.path}/$fileName');
    final IOSink sink = outputFile.openWrite();

    try {
      await audioStream.forEach(sink.add);
    } finally {
      await sink.close();
    }

    return outputFile.path;
  }
}
