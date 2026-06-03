import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class LocalOcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.korean,
  );

  static final RegExp _latinOnlyPattern = RegExp(
    r"^[A-Za-z0-9\s.,'!?&()+:/\-]+$",
  );

  Future<String> recognizeText(InputImage inputImage) async {
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      return _postProcess(recognizedText.text);
    } catch (e) {
      debugPrint('OCR Vision Error: $e');
      return '';
    }
  }

  String _postProcess(String raw) {
    return raw
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  bool isLatinOnly(String text) {
    final String normalized = text.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _latinOnlyPattern.hasMatch(normalized);
  }

  /// Papago source language for mixed Korean/Latin signage OCR results.
  String papagoSourceForText(String text) {
    return isLatinOnly(text) ? 'en' : 'ko';
  }

  void dispose() {
    _textRecognizer.close();
  }
}
