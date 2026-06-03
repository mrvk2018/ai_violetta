// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:violetta_app/core/presentation/layout/responsive_layout_info.dart';
import 'package:violetta_app/features/ar_avatar/domain/avatar_state.dart';
import 'package:violetta_app/features/ar_avatar/presentation/widgets/violetta_3d_view.dart';
import 'package:violetta_app/features/assistant/data/gemini_service.dart';
import 'package:violetta_app/features/assistant/domain/assistant_state.dart';
import 'package:violetta_app/features/main_hud/domain/models/spatial_marker.dart';
import 'package:violetta_app/features/navigation/presentation/widgets/naver_map_hud_widget.dart';
import 'package:violetta_app/features/translator/data/papago_scraping_service.dart';
import 'package:violetta_app/features/translator/data/repositories/cached_translator_repository.dart';
import 'package:violetta_app/features/voice_control/data/services/local_stt_service.dart';
import 'package:violetta_app/features/voice_output/data/services/local_tts_service.dart';

class HudMainScreen extends StatefulWidget {
  const HudMainScreen({super.key});

  @override
  State<HudMainScreen> createState() => _HudMainScreenState();
}

class _HudMainScreenState extends State<HudMainScreen> {
  static const bool _papagoSmokeTestEnabled = bool.fromEnvironment(
    'PAPAGO_SMOKE_TEST',
    defaultValue: false,
  );

  late final CachedTranslatorRepository _translatorRepository;
  late final LocalSttService _localSttService;
  late final LocalTtsService _ttsService;
  late final ViolettaGeminiService _geminiService;
  final TextEditingController _textController = TextEditingController();
  Timer? _sttWatchdogTimer;
  Timer? _speakingFallbackTimer;
  Timer? _markerPulseTimer;

  AssistantState _assistantState = AssistantState.idle;
  AvatarAnimationState _currentAvatarState = AvatarAnimationState.idle;
  bool _isChatMode = false;
  bool _isListening = false;
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
    _ttsService.setCompletionHandler(_onSpeechCompleted);
    _ttsService.init();
    _startMarkerPulse();
    if (_papagoSmokeTestEnabled) {
      _runPapagoSmokeTest();
    }
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
    _textController.dispose();
    super.dispose();
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

  Future<void> _sendMessage() async {
    final String message = _textController.text.trim();
    if (message.isEmpty) {
      return;
    }

    await _ttsService.stop();
    _speakingFallbackTimer?.cancel();

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
        replyText = await _translatorRepository.translate(
          message,
          source: 'ru',
          target: 'ko',
        );
        ttsLocaleId = 'ko-KR';
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
        child: Violetta3DView(currentState: _currentAvatarState),
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
          setState(() {
            _isChatMode = !_isChatMode;
          });
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
