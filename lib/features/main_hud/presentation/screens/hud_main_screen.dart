// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:violetta_app/core/presentation/layout/responsive_layout_info.dart';
import 'package:violetta_app/features/ar_avatar/domain/avatar_state.dart';
import 'package:violetta_app/features/avatar/application/violetta_gesture_binding_controller.dart';
import 'package:violetta_app/features/avatar/application/violetta_lipsync_controller.dart';
import 'package:violetta_app/features/avatar/presentation/widgets/violetta_3d_view.dart';
import 'package:violetta_app/features/assistant/data/gemini_service.dart';
import 'package:violetta_app/features/assistant/domain/assistant_state.dart';
import 'package:violetta_app/features/main_hud/domain/models/spatial_marker.dart';
import 'package:violetta_app/features/navigation/presentation/widgets/naver_map_hud_widget.dart';
import 'package:violetta_app/features/translator/data/papago_scraping_service.dart';
import 'package:violetta_app/features/translator/data/repositories/cached_translator_repository.dart';
import 'package:violetta_app/features/gestures/data/services/air_gesture_service.dart';
import 'package:violetta_app/features/vision/data/services/local_ocr_service.dart';
import 'package:violetta_app/features/voice_control/data/services/native_bridge_service.dart';
import 'package:violetta_app/features/voice_control/data/services/local_stt_service.dart';
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

  late final CachedTranslatorRepository _translatorRepository;
  late final LocalSttService _localSttService;
  late final LocalTtsService _ttsService;
  late final ViolettaLipsyncController _lipsyncController;
  late final ViolettaGestureBindingController _gestureBindingController;
  late final ViolettaGeminiService _geminiService;
  late final LocalOcrService _ocrService;
  final AirGestureService _airGestureService = AirGestureService();
  final TextEditingController _textController = TextEditingController();
  CameraController? _cameraController;
  CameraController? _frontCameraController;
  bool _isGestureStreamActive = false;
  Timer? _sttWatchdogTimer;
  Timer? _speakingFallbackTimer;
  Timer? _markerPulseTimer;

  AssistantState _assistantState = AssistantState.idle;
  AvatarAnimationState _currentAvatarState = AvatarAnimationState.idle;
  bool _isChatMode = false;
  bool _isListening = false;
  bool _isOcrScanning = false;
  bool _isMarkerPulseExpanded = false;
  List<SpatialMarker> _spatialMarkers = <SpatialMarker>[];
  String _dialogText = 'Виолетта на связи. Напиши сообщение ниже.';

  @override
  void initState() {
    super.initState();
    _geminiService = ViolettaGeminiService();
    _translatorRepository = CachedTranslatorRepository(PapagoScrapingService());
    _localSttService = LocalSttService();
    _localSttService.init();
    _ttsService = LocalTtsService();
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
      _handleAirSwipeDetected();
    }
  }

  void _handleAirSwipeDetected() {
    if (!mounted) {
      return;
    }
    setState(() {
      _dialogText = '[ЖЕСТ]: Air Swipe вверх!';
      _currentAvatarState = AvatarAnimationState.loading;
    });
    NativeBridgeService.performSystemSwipe();
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      if (_currentAvatarState == AvatarAnimationState.loading &&
          _dialogText == '[ЖЕСТ]: Air Swipe вверх!') {
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
        setState(() {
          _dialogText = '[OCR]: Текст на кадре не обнаружен.';
          _assistantState = AssistantState.idle;
          _currentAvatarState = AvatarAnimationState.idle;
        });
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

      setState(() {
        _dialogText = translated;
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
        _spatialMarkers = _generateSpatialMarkers();
      });
      await _ttsService.speak(translated, 'ru-RU');
      _scheduleSpeakingFallback(translated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] ocr_scan_error="$error"');
      setState(() {
        _dialogText = '[OCR]: Не удалось отсканировать текст. Повтори попытку.';
        _assistantState = AssistantState.error;
        _currentAvatarState = AvatarAnimationState.idle;
      });
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
    setState(() {
      _currentAvatarState = AvatarAnimationState.idle;
      if (_assistantState == AssistantState.speaking) {
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

    if (lowerMessage.contains('открой тикток') ||
        lowerMessage.contains('open tiktok') ||
        lowerMessage.contains('включи тикток')) {
      await _ttsService.stop();
      _speakingFallbackTimer?.cancel();
      if (!mounted) {
        return true;
      }
      setState(() {
        _textController.clear();
        _spatialMarkers = <SpatialMarker>[];
        _dialogText = '[СИСТЕМА]: Запуск TikTok...';
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
      });
      await _ttsService.speak('Открываю Тикток', 'ru-RU');
      _scheduleSpeakingFallback('Открываю Тикток');
      await NativeBridgeService.openApp('com.zhiliaoapp.musically');
      return true;
    }

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

    if (lowerMessage.contains('открой ютуб') ||
        lowerMessage.contains('open youtube') ||
        lowerMessage.contains('включи ютуб')) {
      await _ttsService.stop();
      _speakingFallbackTimer?.cancel();
      if (!mounted) {
        return true;
      }
      setState(() {
        _textController.clear();
        _dialogText = '[СИСТЕМА]: Запуск YouTube...';
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
      });
      await _ttsService.speak('Запускаю Ютуб', 'ru-RU');
      _scheduleSpeakingFallback('Запускаю Ютуб');
      await NativeBridgeService.openApp('com.google.android.youtube');
      return true;
    }

    return false;
  }

  Future<void> _sendMessage() async {
    final String message = _textController.text.trim();
    if (message.isEmpty) {
      return;
    }

    await _ttsService.stop();
    _speakingFallbackTimer?.cancel();

    if (_isChatMode) {
      final bool commandHandled = await _interceptChatModeVoiceCommand(message);
      if (commandHandled) {
        debugPrint('[HUD] hands_free_command="$message"');
        return;
      }
    }

    setState(() {
      _assistantState = AssistantState.loading;
      _currentAvatarState = AvatarAnimationState.loading;
    });

    _textController.clear();
    debugPrint('[HUD] user_message="$message"');

    try {
      final String replyText;
      final String ttsLocaleId;
      if (_isChatMode) {
        replyText = await _geminiService.sendMessage(message);
        ttsLocaleId = 'ru-RU';
      } else {
        final bool latinOnly = _ocrService.isLatinOnly(message);
        final String source = latinOnly ? 'en' : 'ru';
        final String target = latinOnly ? 'ru' : 'ko';
        replyText = await _translatorRepository.translate(
          message,
          source: source,
          target: target,
        );
        ttsLocaleId = latinOnly ? 'ru-RU' : 'ko-KR';
      }
      if (!mounted) {
        return;
      }
      debugPrint(
        '[HUD] mode=${_isChatMode ? 'chat' : 'translate'} response="$replyText"',
      );
      setState(() {
        _dialogText = replyText;
        _assistantState = AssistantState.speaking;
        _currentAvatarState = AvatarAnimationState.speaking;
        _spatialMarkers = _generateSpatialMarkers();
      });
      await _ttsService.speak(replyText, ttsLocaleId);
      _scheduleSpeakingFallback(replyText);
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] papago_translation_error="$error"');
      await _ttsService.stop();
      setState(() {
        _dialogText = 'Перевод временно недоступен. Работаю в fallback-режиме.';
        _assistantState = AssistantState.error;
        _currentAvatarState = AvatarAnimationState.idle;
      });
    } finally {
      debugPrint('[HUD] papago_request_completed');
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
        child: Violetta3DView(
          lipsyncController: _lipsyncController,
          gestureController: _gestureBindingController,
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _assistantState == AssistantState.loading
                  ? Row(
                      key: const ValueKey('loading'),
                      children: [
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
                    )
                  : Text(
                      _dialogText,
                      key: const ValueKey('dialog'),
                      style: const TextStyle(color: Colors.white),
                    ),
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _assistantState == AssistantState.loading
                    ? Row(
                        key: const ValueKey('loading_console'),
                        children: [
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
                      )
                    : Text(
                        _dialogText,
                        key: const ValueKey('dialog_console'),
                        style: const TextStyle(color: Colors.white),
                      ),
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
                if (_assistantState == AssistantState.speaking) {
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
