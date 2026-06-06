import 'package:hive_flutter/hive_flutter.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';

class OnboardingVaultRepository {
  static const String boxName = 'onboarding_vault';
  static const String isFirstLaunchKey = 'isFirstLaunch';
  static const String localeCodeKey = 'localeCode';

  Box<dynamic>? _box;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    await Hive.initFlutter();
    _box = await Hive.openBox<dynamic>(boxName);
    _isInitialized = true;
  }

  bool get isFirstLaunch {
    _ensureReady();
    return (_box!.get(isFirstLaunchKey, defaultValue: true) as bool?) ?? true;
  }

  ViolettaAppLocale get savedLocale {
    _ensureReady();
    final String? code = _box!.get(localeCodeKey) as String?;
    return ViolettaAppLocale.fromCode(code);
  }

  Future<void> saveLocale(ViolettaAppLocale locale) async {
    _ensureReady();
    await _box!.put(localeCodeKey, locale.code);
  }

  Future<void> completeOnboarding() async {
    _ensureReady();
    await _box!.put(isFirstLaunchKey, false);
  }

  void _ensureReady() {
    if (_box == null) {
      throw StateError('OnboardingVaultRepository.init() must be called first.');
    }
  }
}
