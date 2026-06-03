import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class LocalOcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.korean,
  );

  Future<String> recognizeText(InputImage inputImage) async {
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      return recognizedText.text.trim();
    } catch (e) {
      debugPrint('OCR Vision Error: $e');
      return '';
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
