import 'package:flutter/material.dart';
import 'package:violetta_app/features/onboarding/data/repositories/onboarding_vault_repository.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';

/// Runtime locale state shared by onboarding, Gemini chat tone, and TTS output.
class ViolettaLocaleController extends ChangeNotifier {
  ViolettaLocaleController(this._vault) {
    _instance = this;
  }

  static ViolettaLocaleController? _instance;

  /// Global accessor for command services that run outside widget scope.
  static ViolettaLocaleController? get instance => _instance;

  final OnboardingVaultRepository _vault;
  ViolettaAppLocale _locale = ViolettaAppLocale.russian;

  ViolettaAppLocale get locale => _locale;
  Locale get flutterLocale => _locale.flutterLocale;
  String get ttsLocaleId => _locale.ttsLocaleId;
  String get localeToggleLabel => _locale.isKorean ? 'KO' : 'RU';

  Future<void> loadPersistedLocale() async {
    await _vault.init();
    _locale = _vault.savedLocale;
    notifyListeners();
  }

  Future<void> setLocale(ViolettaAppLocale locale) async {
    if (_locale == locale) {
      return;
    }
    _locale = locale;
    await _vault.saveLocale(locale);
    notifyListeners();
  }

  Future<void> toggleLocale() => setLocale(_locale.toggled);
}
