import 'package:flutter/material.dart';

enum ViolettaAppLocale {
  russian('ru', Locale('ru', 'RU'), 'ru-RU'),
  korean('ko', Locale('ko', 'KR'), 'ko-KR');

  final String code;
  final Locale flutterLocale;
  final String ttsLocaleId;

  const ViolettaAppLocale(this.code, this.flutterLocale, this.ttsLocaleId);

  static ViolettaAppLocale fromCode(String? code) {
    return ViolettaAppLocale.values.firstWhere(
      (ViolettaAppLocale locale) => locale.code == code,
      orElse: () => ViolettaAppLocale.russian,
    );
  }

  bool get isKorean => this == ViolettaAppLocale.korean;

  ViolettaAppLocale get toggled => isKorean ? russian : korean;

  String get localeSwitchConfirmation => switch (this) {
        ViolettaAppLocale.russian => 'Язык изменен на русский',
        ViolettaAppLocale.korean => '한국어로 변경되었습니다',
      };
}
