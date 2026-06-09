// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:violetta_app/core/presentation/layout/responsive_layout_info.dart';
import 'package:violetta_app/features/ar_avatar/domain/avatar_state.dart';
import 'package:violetta_app/features/avatar/application/hand_state_machine_controller.dart';
import 'package:violetta_app/features/avatar/application/violetta_gesture_binding_controller.dart';
import 'package:violetta_app/features/avatar/application/violetta_lipsync_controller.dart';
import 'package:violetta_app/models/message_model.dart';
import 'package:violetta_app/repositories/chat_repository.dart';
import 'package:violetta_app/services/audio_processor_service.dart';
import 'package:violetta_app/services/eleven_labs_service.dart';
import 'package:violetta_app/ui/widgets/violetta_view.dart';
import 'package:violetta_app/features/assistant/application/violetta_command_service.dart';
import 'package:violetta_app/features/ai_brain/services/violetta_gemini_service.dart';
import 'package:violetta_app/features/assistant/domain/assistant_state.dart';
import 'package:violetta_app/features/main_hud/domain/models/spatial_marker.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_controller.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_scope.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';
import 'package:violetta_app/features/onboarding/presentation/widgets/violetta_locale_toggle_button.dart';
import 'package:violetta_app/features/navigation/presentation/widgets/naver_map_hud_widget.dart';
import 'package:violetta_app/features/translator/data/papago_scraping_service.dart';
import 'package:violetta_app/features/translator/data/repositories/cached_translator_repository.dart';
import 'package:violetta_app/features/gestures/data/services/air_gesture_service.dart';
import 'package:violetta_app/features/vision/data/services/local_ocr_service.dart';
import 'package:violetta_app/features/voice_control/data/services/native_bridge_service.dart';
import 'package:violetta_app/features/voice_control/data/services/local_stt_service.dart';
import 'package:violetta_app/features/auth/presentation/byok_keys_panel.dart';
import 'package:violetta_app/features/voice_output/data/services/local_tts_service.dart';

class HudMainScreen extends StatefulWidget {
  const HudMainScreen({super.key});

  @override
  State<HudMainScreen> createState() => _HudMainScreenState();
}

class _HudMainScreenState extends State<HudMainScreen> with TickerProviderStateMixin {
  static const bool _papagoSmokeTestEnabled = bool.fromEnvironment(
    'PAPAGO_SMOKE_TEST',
    defaultValue: false,
  );
  static const String _userSenderId = 'user';
  static const String _violettaSenderId = 'violetta';
  static const String _defaultElevenLabsVoiceId = 'EXAVITQu4vr4xnSDxMaL';

  late final CachedTranslatorRepository _translatorRepository;
  late final LocalSttService _localSttService;
  late final LocalTtsService _ttsService;
  late final ViolettaLipsyncController _lipsyncController;
  late final ViolettaGestureBindingController _gestureBindingController;
  late final ViolettaGeminiService _geminiService;
  late final ViolettaCommandService _commandService;
  late final LocalOcrService _ocrService;
  late final ChatRepository _chatRepository;
  late final HandStateMachineController _handController;
  late final ElevenLabsService _elevenLabsService;
  late final AudioProcessorService _audioProcessorService;
  final AirGestureService _airGestureService = AirGestureService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  CameraController? _cameraController;
  CameraController? _frontCameraController;
  bool _isGestureStreamActive = false;
  Timer? _sttWatchdogTimer;
  Timer? _speakingFallbackTimer;
  Timer? _markerPulseTimer;

  AssistantState _assistantState = AssistantState.idle;
  AvatarAnimationState _currentAvatarState = AvatarAnimationState.idle;
  bool _isChatMode = true;
  bool _isListening = false;
  bool _isOcrScanning = false;
  bool _isMarkerPulseExpanded = false;
  List<SpatialMarker> _spatialMarkers = <SpatialMarker>[];
  List<MessageModel> _messages = <MessageModel>[];

  @override
  void initState() {
    super.initState();
    _geminiService = ViolettaGeminiService();
    _commandService = ViolettaCommandService();
    _chatRepository = ChatRepository(Hive.box<MessageModel>('messages_box'));
    _handController = HandStateMachineController();
    _elevenLabsService = ElevenLabsService();
    _audioProcessorService = AudioProcessorService();
    _translatorRepository = CachedTranslatorRepository(PapagoScrapingService());
    _localSttService = LocalSttService();
    _localSttService.init();
    _ttsService = LocalTtsService();
    unawaited(_audioProcessorService.init());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final ViolettaLocaleController localeController =
          ViolettaLocaleScope.of(context);
      await _geminiService.applyLocale(localeController.locale);
      await _bootstrapChatHistory(localeController);
    });
    _lipsyncController = ViolettaLipsyncController();
    _lipsyncController.attach(_ttsService);
    _gestureBindingController = ViolettaGestureBindingController(vsync: this);
    _gestureBindingController.attach(_airGestureService);
    _ttsService.setCompletionHandler(_onSpeechCompleted);
    _ttsService.init();
    _ocrService = LocalOcrService();
    _initCameras();
    _startMarkerPulse();
    if (_papagoSmokeTestEnabled) {
      _runPapagoSmokeTest();
    }
  }

  Future<void> _initCameras() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        return;
      }

      final CameraDescription backCamera = cameras.firstWhere(
        (CameraDescription camera) =>
            camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController backController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await backController.initialize();

      CameraController? frontController;
      try {
        final CameraDescription frontCamera = cameras.firstWhere(
          (CameraDescription camera) =>
              camera.lensDirection == CameraLensDirection.front,
        );
        frontController = CameraController(
          frontCamera,
          ResolutionPreset.low,
          enableAudio: false,
        );
        await frontController.initialize();
      } catch (_) {
        await frontController?.dispose();
        frontController = null;
      }

      if (!mounted) {
        await backController.dispose();
        await frontController?.dispose();
        return;
      }

      setState(() {
        _cameraController = backController;
        _frontCameraController = frontController;
      });

      if (_isChatMode) {
        await _startGestureStream();
      }
    } catch (error) {
      debugPrint('[HUD] camera_init_error="$error"');
    }
  }

  Future<void> _startGestureStream() async {
    if (!_isChatMode) {
      return;
    }
    final CameraController? camera = _frontCameraController;
    if (camera == null ||
        !camera.value.isInitialized ||
        _isGestureStreamActive ||
        camera.value.isStreamingImages) {
      return;
    }

    try {
      await camera.startImageStream(_onGestureCameraImage);
      _isGestureStreamActive = true;
      debugPrint('[HUD] gesture_stream_started');
    } catch (error) {
      debugPrint('[HUD] gesture_stream_start_error="$error"');
    }
  }

  Future<void> _stopGestureStream() async {
    final CameraController? camera = _frontCameraController;
    if (camera == null || !_isGestureStreamActive) {
      return;
    }

    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } catch (error) {
      debugPrint('[HUD] gesture_stream_stop_error="$error"');
    } finally {
      _isGestureStreamActive = false;
      debugPrint('[HUD] gesture_stream_stopped');
    }
  }

  void _onGestureCameraImage(CameraImage image) {
    if (!_isChatMode) {
      return;
    }
    final signal = _airGestureService.processFrame(image);
    if (signal.airSwipeUp) {
      _handleAirSwipeDetected(swipeUp: true);
    } else if (signal.airSwipeDown) {
      _handleAirSwipeDetected(swipeUp: false);
    }
  }

  void _handleAirSwipeDetected({required bool swipeUp}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _currentAvatarState = AvatarAnimationState.loading;
    });
    NativeBridgeService.performSystemSwipe(swipeUp: swipeUp);
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      if (_currentAvatarState == AvatarAnimationState.loading) {
        setState(() {
          _currentAvatarState = AvatarAnimationState.idle;
        });
      }
    });
  }

  Future<void> _runPapagoSmokeTest() async {
    final String translated = await _translatorRepository.translate(
      '안녕하세요',
      source: 'ko',
      target: 'ru',
    );
    if (!mounted) {
      return;
    }
    debugPrint('[HUD] papago_translation="$translated"');
  }

  @override
  void dispose() {
    _sttWatchdogTimer?.cancel();
    _speakingFallbackTimer?.cancel();
    _markerPulseTimer?.cancel();
    _localSttService.stopListening();
    _ttsService.stop();
    _lipsyncController.dispose();
    _gestureBindingController.dispose();
    _handController.dispose();
    _chatScrollController.dispose();
    unawaited(_audioProcessorService.dispose());
    _airGestureService.dispose();
    _ocrService.dispose();
    _stopGestureStream();
    _cameraController?.dispose();
    _frontCameraController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _performOcrScan() async {
    final CameraController? camera = _cameraController;
    if (camera == null || !camera.value.isInitialized || _isOcrScanning) {
      return;
    }

    await _ttsService.stop();
    _speakingFallbackTimer?.cancel();

    setState(() {
      _isOcrScanning = true;
      _assistantState = AssistantState.loading;
      _currentAvatarState = AvatarAnimationState.loading;
    });

    try {
      final XFile file = await camera.takePicture();
      final InputImage inputImage = InputImage.fromFilePath(file.path);
      final String text = await _ocrService.recognizeText(inputImage);

      if (!mounted) {
        return;
      }

      if (text.isEmpty) {
        final ViolettaLocaleController localeController =
            ViolettaLocaleScope.of(context);
        setState(() {
          _assistantState = AssistantState.idle;
          _currentAvatarState = AvatarAnimationState.idle;
        });
        await _appendAssistantMessage(
          '[OCR]: Текст на кадре не обнаружен.',
          localeController: localeController,
          playVoice: false,
        );
        return;
      }

      _textController.text = text;
      final String ocrSource = _ocrService.papagoSourceForText(text);
      debugPrint('[HUD] ocr_text="$text" source="$ocrSource"');

      final String translated = await _translatorRepository.translate(
        text,
        source: ocrSource,
        target: 'ru',
      );

      if (!mounted) {
        return;
      }

      final ViolettaLocaleController localeController =
          ViolettaLocaleScope.of(context);
      setState(() {
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
        _spatialMarkers = _generateSpatialMarkers();
      });
      await _appendAssistantMessage(
        translated,
        localeController: localeController,
        useElevenLabs: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] ocr_scan_error="$error"');
      final ViolettaLocaleController localeController =
          ViolettaLocaleScope.of(context);
      setState(() {
        _assistantState = AssistantState.error;
        _currentAvatarState = AvatarAnimationState.idle;
      });
      await _appendAssistantMessage(
        '[OCR]: Не удалось отсканировать текст. Повтори попытку.',
        localeController: localeController,
        playVoice: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOcrScanning = false;
        });
      }
    }
  }

  void _startMarkerPulse() {
    _markerPulseTimer?.cancel();
    _markerPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _isMarkerPulseExpanded = !_isMarkerPulseExpanded;
      });
    });
  }

  List<SpatialMarker> _generateSpatialMarkers() {
    final Random random = Random();
    final int markerCount = 2 + random.nextInt(2);
    return List<SpatialMarker>.generate(markerCount, (int index) {
      final String labelPrefix = index == 0
          ? 'TARGET_POI'
          : index == 1
          ? 'SCAN_NODE'
          : 'AR_TRACE';
      return SpatialMarker(
        id: 'marker_$index',
        title: '${labelPrefix}_${String.fromCharCode(65 + index)}',
        topRatio: 0.2 + random.nextDouble() * 0.52,
        leftRatio: 0.1 + random.nextDouble() * 0.72,
      );
    });
  }

  void _onSpeechCompleted() {
    if (!mounted) {
      return;
    }
    _speakingFallbackTimer?.cancel();
    _handController.setHandDown();
    setState(() {
      _currentAvatarState = AvatarAnimationState.idle;
      if (_assistantState == AssistantState.speaking ||
          _assistantState == AssistantState.sleeping) {
        _assistantState = AssistantState.idle;
      }
    });
  }

  void _scheduleSpeakingFallback(String spokenText) {
    _speakingFallbackTimer?.cancel();
    final int estimatedMs = (spokenText.length * 85).clamp(2500, 9000);
    _speakingFallbackTimer = Timer(Duration(milliseconds: estimatedMs), () {
      _onSpeechCompleted();
    });
  }

  void _handleSttResult(String recognizedText) {
    if (!mounted) {
      return;
    }
    setState(() {
      _textController.text = recognizedText;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    });
  }

  void _startSttWatchdog() {
    _sttWatchdogTimer?.cancel();
    _sttWatchdogTimer = Timer.periodic(const Duration(milliseconds: 350), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isListening && !_localSttService.isListening) {
        timer.cancel();
        setState(() {
          _isListening = false;
        });
        _sendMessage();
      }
    });
  }

  void _toggleVoiceInput() {
    if (_isListening) {
      _stopVoiceInputAndSend();
      return;
    }
    _localSttService.startListening(
      onResult: _handleSttResult,
      localeId: 'ko-KR',
    );
    setState(() {
      _isListening = true;
    });
    _startSttWatchdog();
  }

  void _stopVoiceInputAndSend() {
    _sttWatchdogTimer?.cancel();
    _localSttService.stopListening();
    if (!mounted) {
      return;
    }
    setState(() {
      _isListening = false;
    });
    _sendMessage();
  }

  /// Hands-free OS commands — only in ВИОЛЕТТА ИИ mode; never in translator mode.
  Future<bool> _interceptChatModeVoiceCommand(String rawMessage) async {
    final String lowerMessage = rawMessage.toLowerCase();

    if (lowerMessage.contains('дальше') ||
        lowerMessage.contains('пролистай') ||
        lowerMessage.contains('следующий') ||
        lowerMessage.contains('свайп')) {
      if (!mounted) {
        return true;
      }
      setState(() {
        _textController.clear();
      });
      await NativeBridgeService.performSystemSwipe();
      return true;
    }

    return false;
  }

  bool _containsHangul(String text) {
    return RegExp(r'[\uAC00-\uD7AF]').hasMatch(text);
  }

  String _idleDialogTextFor(ViolettaAppLocale locale) {
    return locale.isKorean
        ? '비올레타가 대기 중입니다. 아래에 메시지를 입력하세요.'
        : 'Виолетта на связи. Напиши сообщение ниже.';
  }

  String get _elevenLabsVoiceId =>
      dotenv.env['ELEVEN_LABS_VOICE_ID']?.trim() ?? _defaultElevenLabsVoiceId;

  Future<void> _bootstrapChatHistory(
    ViolettaLocaleController localeController,
  ) async {
    final List<MessageModel> stored = _chatRepository.getAllMessages();
    if (stored.isEmpty) {
      await _appendAssistantMessage(
        _idleDialogTextFor(localeController.locale),
        localeController: localeController,
        playVoice: false,
        raiseHand: false,
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _messages = stored;
    });
    _scrollChatToBottom();
  }

  void _reloadMessages() {
    setState(() {
      _messages = _chatRepository.getAllMessages();
    });
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) {
        return;
      }
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _languageCodeForText(String text, ViolettaAppLocale locale) {
    if (_containsHangul(text)) {
      return 'ko';
    }
    return locale.isKorean ? 'ko' : 'ru';
  }

  Future<void> _persistUserMessage(
    String text,
    ViolettaLocaleController localeController,
  ) async {
    final MessageModel message = MessageModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: _userSenderId,
      originalText: text,
      sourceLanguageCode: _languageCodeForText(text, localeController.locale),
      translations: <String, String>{},
      timestamp: DateTime.now(),
      isAudio: _isListening,
    );
    await _chatRepository.saveMessage(message);
    _reloadMessages();
  }

  Future<void> _appendAssistantMessage(
    String text, {
    required ViolettaLocaleController localeController,
    bool playVoice = true,
    bool raiseHand = true,
    bool useElevenLabs = true,
  }) async {
    if (text.trim().isEmpty) {
      return;
    }

    final MessageModel message = MessageModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: _violettaSenderId,
      originalText: text,
      sourceLanguageCode: _languageCodeForText(text, localeController.locale),
      translations: <String, String>{},
      timestamp: DateTime.now(),
      isAudio: useElevenLabs && playVoice && _elevenLabsService.canUseElevenLabs,
    );
    await _chatRepository.saveMessage(message);
    _reloadMessages();

    if (!playVoice) {
      return;
    }

    if (raiseHand) {
      _handController.setHandUp();
    }

    if (_isChatMode && useElevenLabs) {
      await _playAssistantVoicePipeline(
        text,
        localeController: localeController,
      );
      return;
    }

    await _ttsService.speak(text, _resolveChatTtsLocale(messageHint: text));
    _scheduleSpeakingFallback(text);
    _handController.setHandDown();
  }

  Future<void> _playAssistantVoicePipeline(
    String text, {
    required ViolettaLocaleController localeController,
  }) async {
    final String ttsLocale = _resolveChatTtsLocale(messageHint: text);
    try {
      final VoiceSynthesisResult synthesis =
          await _elevenLabsService.synthesizeSpeech(
        text: text,
        voiceId: _elevenLabsVoiceId,
        fallbackTts: _ttsService,
        fallbackLocale: ttsLocale,
      );

      if (synthesis.usedLocalTts) {
        _scheduleSpeakingFallback(text);
        _handController.setHandDown();
        return;
      }

      final Stream<List<int>>? audioStream = synthesis.audioStream;
      if (audioStream == null) {
        await _ttsService.speak(text, ttsLocale);
        _scheduleSpeakingFallback(text);
        _handController.setHandDown();
        return;
      }

      final String audioPath =
          await _elevenLabsService.saveStreamToTempFile(audioStream);
      await _audioProcessorService.playVoiceWithEffects(audioPath, pitch: 1.05);
      if (!mounted) {
        return;
      }
      setState(() {
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
      });
      _handController.setHandDown();
      _speakingFallbackTimer?.cancel();
      _speakingFallbackTimer = Timer(const Duration(seconds: 6), _onSpeechCompleted);
    } catch (error) {
      debugPrint('[HUD] eleven_labs_pipeline_error="$error"');
      await _ttsService.speak(text, ttsLocale);
      _scheduleSpeakingFallback(text);
      _handController.setHandDown();
    }
  }

  Future<void> _translateAssistantMessage(MessageModel message) async {
    if (message.senderId != _violettaSenderId) {
      return;
    }

    final String source = message.sourceLanguageCode;
    final String target = source == 'ko' ? 'ru' : 'ko';

    try {
      final String translated = await _translatorRepository.translate(
        message.originalText,
        source: source,
        target: target,
      );
      await _chatRepository.addTranslation(message.id, target, translated);
      _reloadMessages();
    } catch (error) {
      debugPrint('[HUD] message_translation_error="$error"');
    }
  }

  Future<void> _toggleLocaleFromUi() async {
    final ViolettaLocaleController controller =
        ViolettaLocaleScope.of(context);
    await _ttsService.stop();
    _speakingFallbackTimer?.cancel();
    final ViolettaGeminiTurnResult turn = await _commandService.switchLocale(
      controller.locale.toggled,
      localeController: controller,
      ttsService: _ttsService,
    );
    if (!mounted || !turn.localeSwitched || turn.switchedLocale == null) {
      return;
    }
    await _geminiService.applyLocale(turn.switchedLocale!);
    if (!mounted) {
      return;
    }
    setState(() {
      _assistantState = AssistantState.sleeping;
      _currentAvatarState = AvatarAnimationState.idle;
      _spatialMarkers = <SpatialMarker>[];
    });
    await _appendAssistantMessage(
      turn.confirmationSpeech,
      localeController: controller,
      useElevenLabs: false,
    );
  }

  Future<void> _handleSystemUtilitySleeping(
    String confirmationSpeech, {
    required ViolettaLocaleController localeController,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _assistantState = AssistantState.sleeping;
      _currentAvatarState = AvatarAnimationState.idle;
      _spatialMarkers = <SpatialMarker>[];
    });
    await _appendAssistantMessage(
      confirmationSpeech,
      localeController: localeController,
      useElevenLabs: false,
    );
  }

  Future<void> _handleLocaleSwitchTurn(ViolettaGeminiTurnResult turn) async {
    if (!mounted) {
      return;
    }
    final ViolettaLocaleController localeController =
        ViolettaLocaleScope.of(context);
    if (turn.switchedLocale != null) {
      await _geminiService.applyLocale(turn.switchedLocale!);
    }
    setState(() {
      _assistantState = AssistantState.sleeping;
      _currentAvatarState = AvatarAnimationState.idle;
      _spatialMarkers = <SpatialMarker>[];
    });
    await _appendAssistantMessage(
      turn.confirmationSpeech,
      localeController: localeController,
      useElevenLabs: false,
    );
    debugPrint('[HUD] system_switch_locale="${turn.switchedLocale?.code}"');
  }

  String _resolveChatTtsLocale({String? messageHint}) {
    try {
      final ViolettaLocaleController controller =
          ViolettaLocaleScope.of(context);
      if (messageHint != null &&
          _containsHangul(messageHint) &&
          !controller.locale.isKorean) {
        return ViolettaAppLocale.korean.ttsLocaleId;
      }
      return controller.ttsLocaleId;
    } catch (_) {
      return ViolettaAppLocale.russian.ttsLocaleId;
    }
  }

  Future<void> _sendMessage() async {
    final String message = _textController.text.trim();
    if (message.isEmpty) {
      return;
    }

    final ViolettaLocaleController localeController =
        ViolettaLocaleScope.of(context);

    await _ttsService.stop();
    await _audioProcessorService.stopPlayback();
    _speakingFallbackTimer?.cancel();

    if (_isChatMode) {
      final bool commandHandled = await _interceptChatModeVoiceCommand(message);
      if (commandHandled) {
        debugPrint('[HUD] hands_free_command="$message"');
        return;
      }

      final ViolettaIncomingSttResult localUtility =
          await _commandService.processIncomingSTT(
        message,
        localeController: localeController,
        ttsService: null,
      );
      if (localUtility.handled) {
        _textController.clear();
        await _persistUserMessage(message, localeController);
        _handController.setHandUp();
        if (!mounted) {
          return;
        }
        await _handleSystemUtilitySleeping(
          localUtility.confirmationSpeech,
          localeController: localeController,
        );
        debugPrint('[HUD] local_utility="$message"');
        return;
      }
    }

    setState(() {
      _assistantState = AssistantState.loading;
      _currentAvatarState = AvatarAnimationState.loading;
    });

    _textController.clear();
    debugPrint('[HUD] user_message="$message"');

    if (_isChatMode) {
      await _persistUserMessage(message, localeController);
      _handController.setHandUp();
    }

    try {
      if (_isChatMode) {
        final ViolettaGeminiTurnResult turn =
            await _commandService.processGeminiStream(
          _geminiService,
          message,
          localeController: localeController,
          ttsService: _ttsService,
        );
        if (turn.localeSwitched) {
          await _geminiService.cancelActiveStream();
          await _handleLocaleSwitchTurn(turn);
          return;
        }
        if (turn.alarmSet) {
          await _geminiService.cancelActiveStream();
          await _handleSystemUtilitySleeping(
            turn.confirmationSpeech,
            localeController: localeController,
          );
          debugPrint(
            '[HUD] system_set_alarm="${turn.alarmHour}:${turn.alarmMinute}"',
          );
          return;
        }
        if (turn.commandExecuted && turn.packageName != null) {
          await _geminiService.cancelActiveStream();
          if (!mounted) {
            return;
          }
          setState(() {
            _assistantState = AssistantState.sleeping;
            _currentAvatarState = AvatarAnimationState.idle;
            _spatialMarkers = <SpatialMarker>[];
          });
          await _appendAssistantMessage(
            _idleDialogTextFor(localeController.locale),
            localeController: localeController,
            playVoice: false,
          );
          _handController.setHandDown();
          debugPrint('[HUD] system_open_app="${turn.packageName}"');
          return;
        }
        if (turn.appNotInstalled) {
          await _geminiService.cancelActiveStream();
          if (!mounted) {
            return;
          }
          final bool prefersKorean = _containsHangul(message) ||
              _resolveChatTtsLocale() == ViolettaAppLocale.korean.ttsLocaleId;
          final String notInstalledText = prefersKorean
              ? '앱이 설치되어 있지 않습니다'
              : 'Приложение не установлено';
          setState(() {
            _assistantState = AssistantState.speaking;
            _currentAvatarState = AvatarAnimationState.speaking;
            _spatialMarkers = <SpatialMarker>[];
          });
          await _appendAssistantMessage(
            notInstalledText,
            localeController: localeController,
            useElevenLabs: false,
          );
          debugPrint('[HUD] system_open_app_missing="${turn.packageName}"');
          return;
        }

        final String replyText = turn.displayText;
        if (replyText.isEmpty) {
          if (!mounted) {
            return;
          }
          setState(() {
            _assistantState = AssistantState.idle;
            _currentAvatarState = AvatarAnimationState.idle;
          });
          await _appendAssistantMessage(
            'Я на связи, но ответ не успел дойти. Давай попробуем еще раз?',
            localeController: localeController,
            useElevenLabs: false,
          );
          return;
        }

        if (!mounted) {
          return;
        }
        debugPrint('[HUD] mode=chat response="$replyText"');
        setState(() {
          _assistantState = AssistantState.speaking;
          _currentAvatarState = AvatarAnimationState.speaking;
          _spatialMarkers = _generateSpatialMarkers();
        });
        await _appendAssistantMessage(
          replyText,
          localeController: localeController,
          raiseHand: false,
        );
        return;
      }

      final bool latinOnly = _ocrService.isLatinOnly(message);
      final String source = latinOnly ? 'en' : 'ru';
      final String target = latinOnly ? 'ru' : 'ko';
      final String replyText = await _translatorRepository.translate(
        message,
        source: source,
        target: target,
      );

      if (replyText.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _assistantState = AssistantState.idle;
          _currentAvatarState = AvatarAnimationState.idle;
        });
        return;
      }

      if (!mounted) {
        return;
      }
      debugPrint('[HUD] mode=translate response="$replyText"');
      setState(() {
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
        _spatialMarkers = _generateSpatialMarkers();
      });
      await _appendAssistantMessage(
        replyText,
        localeController: localeController,
        useElevenLabs: false,
        raiseHand: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] request_error="$error"');
      await _ttsService.stop();
      setState(() {
        _assistantState = AssistantState.error;
        _currentAvatarState = AvatarAnimationState.idle;
      });
      await _appendAssistantMessage(
        _isChatMode
            ? 'Связь с ИИ немного нестабильна. Давай повторим запрос.'
            : 'Перевод временно недоступен. Работаю в fallback-режиме.',
        localeController: localeController,
        useElevenLabs: false,
        playVoice: false,
      );
      _handController.setHandDown();
    } finally {
      debugPrint('[HUD] request_completed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ResponsiveLayoutInfo layout = ResponsiveLayoutInfo.fromContext(
      context,
    );
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final Color neonCyan = const Color(0xFF00F5FF);
    final Color neonPink = const Color(0xFFFF4FCB);

    if (layout.formFactor == DeviceFormFactor.flat) {
      return Scaffold(
        backgroundColor: Colors.black.withOpacity(0.4),
        body: SafeArea(
          child: Stack(
            children: [
              const NaverMapHudWidget(),
              _buildHiddenCameraPreview(),
              _buildSpatialMarkersOverlay(),
              _buildHudStatusBar(
                neonCyan: neonCyan,
                neonPink: neonPink,
                formFactor: layout.formFactor,
              ),
              _buildCharacterView(
                availableHeight:
                    mediaQuery.size.height -
                    mediaQuery.padding.top -
                    mediaQuery.padding.bottom,
              ),
              _buildDialogOverlay(neonCyan: neonCyan, neonPink: neonPink),
              Positioned(
                top: 72,
                right: 16,
                child: ViolettaLocaleToggleButton(
                  onToggle: _toggleLocaleFromUi,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SizedBox(
            height: layout.topPanelHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const NaverMapHudWidget(),
                _buildHiddenCameraPreview(),
                _buildSpatialMarkersOverlay(),
                SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      _buildHudStatusBar(
                        neonCyan: neonCyan,
                        neonPink: neonPink,
                        formFactor: layout.formFactor,
                      ),
                      _buildCharacterView(
                        availableHeight: layout.topPanelHeight,
                      ),
                      Positioned(
                        top: 8,
                        right: 16,
                        child: ViolettaLocaleToggleButton(
                          onToggle: _toggleLocaleFromUi,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.hingeHeight),
          SizedBox(
            height: layout.bottomPanelHeight,
            child: _buildFlexedConsole(neonCyan: neonCyan, neonPink: neonPink),
          ),
        ],
      ),
    );
  }

  Widget _buildHudStatusBar({
    required Color neonCyan,
    required Color neonPink,
    required DeviceFormFactor formFactor,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: neonCyan.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(color: neonCyan.withOpacity(0.2), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.battery_full_rounded, color: neonCyan, size: 20),
            const SizedBox(width: 6),
            Text(
              '89%',
              style: TextStyle(color: neonCyan, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.network_wifi_rounded, color: neonPink, size: 20),
            const SizedBox(width: 6),
            Text(
              'Online',
              style: TextStyle(color: neonPink, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.location_on_rounded, color: neonCyan, size: 20),
            const SizedBox(width: 6),
            Text(
              'Seoul, KR',
              style: TextStyle(color: neonCyan, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'BYOK-ключи и голос',
              iconSize: 20,
              splashRadius: 18,
              color: neonCyan,
              onPressed: () => showByokKeysPanel(context),
              icon: const Icon(Icons.settings_voice_rounded),
            ),
            if (kDebugMode) ...[
              const SizedBox(width: 8),
              _buildFormFactorDebugBadge(formFactor: formFactor),
              IconButton(
                tooltip: 'Avatar 2.5D Debug HUD',
                iconSize: 20,
                splashRadius: 18,
                color: neonPink,
                onPressed: () {
                  Navigator.of(context).pushNamed('/avatar-debug');
                },
                icon: const Icon(Icons.bug_report_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormFactorDebugBadge({required DeviceFormFactor formFactor}) {
    final bool isFlexed = formFactor == DeviceFormFactor.flexed;
    final Color badgeColor = isFlexed
        ? const Color(0xFFFF4FCB)
        : const Color(0xFF47FF8A);
    final String label = isFlexed ? '[FLEXED]' : '[FLAT]';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.75)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildCharacterView({required double availableHeight}) {
    final double avatarSize = (availableHeight * 0.48).clamp(150.0, 320.0);
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: ViolettaView(
          controller: _handController,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildDialogOverlay({
    required Color neonCyan,
    required Color neonPink,
  }) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.38),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: neonPink.withOpacity(0.7)),
          boxShadow: [
            BoxShadow(color: neonPink.withOpacity(0.25), blurRadius: 14),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Диалог',
              style: TextStyle(color: neonCyan, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _buildAvatarStateControlsInline(),
            const SizedBox(height: 8),
            _buildChatHistory(
              neonCyan: neonCyan,
              neonPink: neonPink,
              maxHeight: 220,
            ),
            const SizedBox(height: 12),
            _buildMessageInputRow(
              neonCyan: neonCyan,
              neonPink: neonPink,
              textFillOpacity: 0.25,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlexedConsole({
    required Color neonCyan,
    required Color neonPink,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.92), const Color(0xFF12061B)],
        ),
        border: Border(
          top: BorderSide(color: neonPink.withOpacity(0.45), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: neonPink.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Консоль Виолетты',
                style: TextStyle(color: neonCyan, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _buildAvatarStateControlsInline(),
              const SizedBox(height: 10),
              _buildChatHistory(
                neonCyan: neonCyan,
                neonPink: neonPink,
                maxHeight: 180,
              ),
              const SizedBox(height: 12),
              _buildMessageInputRow(
                neonCyan: neonCyan,
                neonPink: neonPink,
                textFillOpacity: 0.35,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatHistory({
    required Color neonCyan,
    required Color neonPink,
    required double maxHeight,
  }) {
    return SizedBox(
      height: maxHeight,
      child: Stack(
        children: <Widget>[
          ListView.builder(
            controller: _chatScrollController,
            itemCount: _messages.length,
            itemBuilder: (BuildContext context, int index) {
              final MessageModel message = _messages[index];
              return _buildMessageBubble(
                message: message,
                neonCyan: neonCyan,
                neonPink: neonPink,
              );
            },
          ),
          if (_assistantState == AssistantState.loading)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.black.withOpacity(0.45),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: neonCyan,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Виолетта думает...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required MessageModel message,
    required Color neonCyan,
    required Color neonPink,
  }) {
    final bool isUser = message.senderId == _userSenderId;
    final Color bubbleColor = isUser
        ? neonPink.withOpacity(0.22)
        : neonCyan.withOpacity(0.18);
    final Color borderColor =
        isUser ? neonPink.withOpacity(0.65) : neonCyan.withOpacity(0.65);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    message.originalText,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ),
                if (!isUser)
                  IconButton(
                    tooltip: 'Перевести',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _translateAssistantMessage(message),
                    icon: const Text('🌐', style: TextStyle(fontSize: 16)),
                  ),
              ],
            ),
            if (message.translations.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              ...message.translations.entries.map(
                (MapEntry<String, String> entry) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${entry.key.toUpperCase()}: ${entry.value}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStateControlsInline() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Idle',
            iconSize: 18,
            splashRadius: 16,
            color: Colors.white70,
            onPressed: () async {
              _speakingFallbackTimer?.cancel();
              await _ttsService.stop();
              if (!mounted) {
                return;
              }
              setState(() {
                _currentAvatarState = AvatarAnimationState.idle;
                if (_assistantState == AssistantState.speaking ||
                    _assistantState == AssistantState.sleeping) {
                  _assistantState = AssistantState.idle;
                }
              });
            },
            icon: const Icon(Icons.pause_circle_outline_rounded),
          ),
          IconButton(
            tooltip: 'Loading',
            iconSize: 18,
            splashRadius: 16,
            color: Colors.white70,
            onPressed: () {
              setState(() {
                _currentAvatarState = AvatarAnimationState.loading;
              });
            },
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: 'Speaking',
            iconSize: 18,
            splashRadius: 16,
            color: Colors.white70,
            onPressed: () {
              setState(() {
                _currentAvatarState = AvatarAnimationState.speaking;
              });
            },
            icon: const Icon(Icons.record_voice_over_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputRow({
    required Color neonCyan,
    required Color neonPink,
    required double textFillOpacity,
  }) {
    final bool canSend = _assistantState != AssistantState.loading;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Напиши сообщение Виолетте...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black.withOpacity(textFillOpacity),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: neonCyan.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: neonCyan),
              ),
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        _buildScanButton(),
        const SizedBox(width: 8),
        _buildInteractionModeToggle(neonCyan: neonCyan, neonPink: neonPink),
        const SizedBox(width: 8),
        IconButton(
          tooltip: _isListening ? 'Stop voice input' : 'Start voice input',
          icon: const Icon(Icons.mic),
          color: _isListening ? const Color(0xFFFF4FCB) : Colors.white70,
          onPressed: canSend ? _toggleVoiceInput : null,
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: canSend ? _sendMessage : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: neonPink.withOpacity(0.9),
            foregroundColor: Colors.white,
            minimumSize: const Size(52, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }

  Widget _buildHiddenCameraPreview() {
    final CameraController? camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(opacity: 0.01, child: CameraPreview(camera)),
      ),
    );
  }

  Widget _buildScanButton() {
    const Color neonYellow = Color(0xFFFFE566);
    final bool canScan =
        !_isOcrScanning &&
        _assistantState != AssistantState.loading &&
        (_cameraController?.value.isInitialized ?? false);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canScan ? _performOcrScan : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: neonYellow.withOpacity(0.13),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: neonYellow.withOpacity(0.75)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.document_scanner,
                color: canScan ? neonYellow : Colors.white38,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'СКАН',
                style: TextStyle(
                  color: canScan ? neonYellow : Colors.white38,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractionModeToggle({
    required Color neonCyan,
    required Color neonPink,
  }) {
    final IconData icon = _isChatMode ? Icons.psychology : Icons.translate;
    final String label = _isChatMode ? 'ВИОЛЕТТА ИИ' : 'ПЕРЕВОД';
    final Color accentColor = _isChatMode ? neonPink : neonCyan;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (_assistantState == AssistantState.loading) {
            return;
          }
          final bool nextChatMode = !_isChatMode;
          setState(() {
            _isChatMode = nextChatMode;
          });
          if (nextChatMode) {
            _startGestureStream();
          } else {
            _stopGestureStream();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.13),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withOpacity(0.75)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accentColor, size: 18),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpatialMarkersOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Color neonMarker = const Color(0xFF00F5FF);
            return Stack(
              children: _spatialMarkers.map((SpatialMarker marker) {
                final double top = constraints.maxHeight * marker.topRatio;
                final double left = constraints.maxWidth * marker.leftRatio;
                return Positioned(
                  top: top,
                  left: left,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: _isMarkerPulseExpanded ? 1.18 : 0.92,
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeInOut,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: neonMarker.withOpacity(0.9),
                            boxShadow: [
                              BoxShadow(
                                color: neonMarker.withOpacity(0.95),
                                blurRadius: 14,
                                spreadRadius: 1.2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: neonMarker.withOpacity(0.8),
                          ),
                        ),
                        child: Text(
                          marker.title,
                          style: TextStyle(
                            color: neonMarker,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
