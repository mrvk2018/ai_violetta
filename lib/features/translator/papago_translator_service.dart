import 'package:violetta_app/features/translator/data/papago_scraping_service.dart';

/// Papago translator facade with BYOK Naver keys and free fallbacks.
class PapagoTranslatorService {
  PapagoTranslatorService({PapagoScrapingService? scrapingService})
      : _scrapingService = scrapingService ?? PapagoScrapingService();

  final PapagoScrapingService _scrapingService;

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    return _scrapingService.translate(
      text: text,
      source: sourceLang,
      target: targetLang,
    );
  }
}
