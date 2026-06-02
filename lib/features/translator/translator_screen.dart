import 'package:flutter/material.dart';

import 'papago_translator_service.dart';

class TranslatorScreen extends StatefulWidget {
  TranslatorScreen({
    super.key,
    PapagoTranslatorService? translatorService,
  }) : _translatorService = translatorService ?? PapagoTranslatorService();

  final PapagoTranslatorService _translatorService;

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isLoading = false;
  String _translatedText = 'Результат перевода появится здесь';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _translate({required String targetLang}) async {
    final String text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _translatedText = 'Введите текст для перевода.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String sourceLang = targetLang == 'ko' ? 'ru' : 'ko';
      final String result = await widget._translatorService.translateText(
        text: text,
        sourceLang: sourceLang,
        targetLang: targetLang,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _translatedText = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _translatedText = 'Ошибка перевода: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Переводчик')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _inputController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Введите фразу на русском или корейском',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _translate(targetLang: 'ko'),
                      child: const Text('Перевести на Корейский'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _translate(targetLang: 'ru'),
                      child: const Text('Перевести на Русский'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Center(
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _translatedText,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
