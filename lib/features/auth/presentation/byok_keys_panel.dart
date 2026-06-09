import 'package:flutter/material.dart';
import 'package:violetta_app/features/auth/auth_service.dart';

Future<void> showByokKeysPanel(BuildContext context) async {
  final AuthService authService = AuthService.instance;
  final TextEditingController elevenLabsController = TextEditingController(
    text: authService.userElevenLabsKey ?? '',
  );
  final TextEditingController naverClientIdController = TextEditingController(
    text: authService.naverClientId ?? '',
  );
  final TextEditingController naverClientSecretController =
      TextEditingController(
    text: authService.naverClientSecret ?? '',
  );

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C222B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Панель BYOK-ключей',
                style: TextStyle(
                  color: Color(0xFF00F5FF),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Подключите личные квоты сервисов. Пустые поля — бесплатные режимы по умолчанию.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('Премиум-голос (ElevenLabs)'),
              const SizedBox(height: 8),
              const Text(
                'Оставьте пустым для бесплатного базового голоса (flutter_tts).',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: elevenLabsController,
                label: 'ElevenLabs API Key',
                obscure: true,
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('Naver Map + Papago'),
              const SizedBox(height: 8),
              const Text(
                'Без ключей карта покажет подсказку, перевод — scraping/Google Translate.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: naverClientIdController,
                label: 'Naver Client ID',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: naverClientSecretController,
                label: 'Naver Client Secret',
                obscure: true,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await authService.saveByokKeys(
                      userElevenLabsKey: elevenLabsController.text,
                      naverClientId: naverClientIdController.text,
                      naverClientSecret: naverClientSecretController.text,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('BYOK-ключи сохранены в зашифрованном Hive.'),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5FF),
                    foregroundColor: const Color(0xFF141920),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Сохранить',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  elevenLabsController.dispose();
  naverClientIdController.dispose();
  naverClientSecretController.dispose();
}

Widget _buildSectionTitle(String text) {
  return Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );
}

Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  bool obscure = false,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.35),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0x5500F5FF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00F5FF)),
      ),
    ),
  );
}
