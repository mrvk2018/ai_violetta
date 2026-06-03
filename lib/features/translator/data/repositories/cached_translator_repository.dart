import 'package:hive_flutter/hive_flutter.dart';
import 'package:violetta_app/features/translator/data/papago_scraping_service.dart';

class CachedTranslatorRepository {
  final PapagoScrapingService _scrapingService;
  late Box<String> _cacheBox;
  bool _isInitialized = false;

  CachedTranslatorRepository(this._scrapingService);

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    await Hive.initFlutter();
    _cacheBox = await Hive.openBox<String>('translations_cache');
    _isInitialized = true;
  }

  Future<String> translate(
    String text, {
    required String source,
    required String target,
  }) async {
    await init();

    final String cacheKey = '${text.trim().toLowerCase()}_${source}_$target';

    if (_cacheBox.containsKey(cacheKey)) {
      final String? cachedResult = _cacheBox.get(cacheKey);
      if (cachedResult != null && cachedResult.isNotEmpty) {
        return cachedResult;
      }
    }

    final String remoteResult = await _scrapingService.translate(
      text: text,
      source: source,
      target: target,
    );

    if (remoteResult.isNotEmpty) {
      await _cacheBox.put(cacheKey, remoteResult);
    }

    return remoteResult;
  }
}
