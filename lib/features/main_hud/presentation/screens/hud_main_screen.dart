// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../../assistant/data/gemini_service.dart';
import '../../../assistant/domain/assistant_state.dart';
import '../../../navigation/presentation/widgets/naver_map_hud_widget.dart';

class HudMainScreen extends StatefulWidget {
  const HudMainScreen({super.key});

  @override
  State<HudMainScreen> createState() => _HudMainScreenState();
}

class _HudMainScreenState extends State<HudMainScreen> {
  late final ViolettaGeminiService _geminiService;
  final TextEditingController _textController = TextEditingController();

  AssistantState _assistantState = AssistantState.idle;
  String _dialogText = 'Виолетта на связи. Напиши сообщение ниже.';

  @override
  void initState() {
    super.initState();
    _geminiService = ViolettaGeminiService();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final String message = _textController.text.trim();
    if (message.isEmpty) {
      return;
    }

    setState(() {
      _assistantState = AssistantState.loading;
    });

    _textController.clear();
    debugPrint('[HUD] user_message="$message"');

    try {
      final String answer = await _geminiService.sendMessage(message);
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] model_response="$answer"');
      setState(() {
        _dialogText = answer;
        _assistantState = AssistantState.speaking;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      debugPrint('[HUD] model_response_error');
      setState(() {
        _dialogText = 'Я рядом, но сейчас не удалось ответить. Повтори запрос.';
        _assistantState = AssistantState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color neonCyan = const Color(0xFF00F5FF);
    final Color neonPink = const Color(0xFFFF4FCB);

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.4),
      body: SafeArea(
        child: Stack(
          children: [
            const NaverMapHudWidget(),
            _buildHudStatusBar(neonCyan: neonCyan, neonPink: neonPink),
            _buildCharacterPlaceholder(neonCyan: neonCyan),
            _buildDialogPanel(neonCyan: neonCyan, neonPink: neonPink),
          ],
        ),
      ),
    );
  }

  Widget _buildHudStatusBar({required Color neonCyan, required Color neonPink}) {
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
            Text('89%', style: TextStyle(color: neonCyan, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.network_wifi_rounded, color: neonPink, size: 20),
            const SizedBox(width: 6),
            Text('Online', style: TextStyle(color: neonPink, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.location_on_rounded, color: neonCyan, size: 20),
            const SizedBox(width: 6),
            Text('Seoul, KR', style: TextStyle(color: neonCyan, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterPlaceholder({required Color neonCyan}) {
    return Align(
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.94, end: 1.05),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOut,
        onEnd: () {
          if (mounted) {
            setState(() {});
          }
        },
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: neonCyan.withOpacity(0.08),
            border: Border.all(color: neonCyan.withOpacity(0.85), width: 2),
            boxShadow: [
              BoxShadow(color: neonCyan.withOpacity(0.35), blurRadius: 22, spreadRadius: 2),
            ],
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face_retouching_natural, size: 48, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'Виолетта 3D [Idle]',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogPanel({required Color neonCyan, required Color neonPink}) {
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Напиши сообщение Виолетте...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.25),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _assistantState == AssistantState.loading ? null : _sendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: neonPink.withOpacity(0.9),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
