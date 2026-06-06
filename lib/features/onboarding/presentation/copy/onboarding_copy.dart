import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';

class OnboardingCopy {
  final ViolettaAppLocale locale;

  const OnboardingCopy(this.locale);

  String get wizardTitle => locale.isKorean ? 'Violetta AR 설정' : 'Настройка Violetta AR';

  String get stepLanguageTitle =>
      locale.isKorean ? '언어를 선택하세요' : 'Выберите язык';

  String get stepLanguageSubtitle => locale.isKorean
      ? 'AR HUD와 음성 엔진이 선택한 언어로 동작합니다.'
      : 'AR HUD и голосовой движок будут работать на выбранном языке.';

  String get stepPrivacyTitle =>
      locale.isKorean ? '개인정보 처리방침' : 'Политика конфиденциальности';

  String get stepPrivacyHint => locale.isKorean
      ? '아래 문서를 끝까지 읽어야 계속할 수 있습니다.'
      : 'Прокрутите документ до конца, чтобы продолжить.';

  String get acceptContinue =>
      locale.isKorean ? '동의하고 계속' : 'Принять и продолжить';

  String get stepPermissionsTitle =>
      locale.isKorean ? '권한 설정' : 'Настройка разрешений';

  String get stepPermissionsSubtitle => locale.isKorean
      ? 'Violetta AR의 핵심 기능을 위해 아래 권한이 필요합니다.'
      : 'Для работы Violetta AR нужны следующие разрешения.';

  String get cameraLabel => locale.isKorean ? '카메라' : 'Камера';
  String get microphoneLabel => locale.isKorean ? '마이크' : 'Микрофон';
  String get accessibilityLabel =>
      locale.isKorean ? '접근성 서비스' : 'Служба доступности';

  String get grantAction => locale.isKorean ? '허용' : 'Разрешить';
  String get openSettingsAction => locale.isKorean ? '설정 열기' : 'Открыть настройки';
  String get finishAction => locale.isKorean ? '완료' : 'Готово';

  String get privacyPolicyText => locale.isKorean ? _privacyKo : _privacyRu;
}

const String _privacyRu = '''
ПОЛИТИКА КОНФИДЕНЦИАЛЬНОСТИ VIOLETTA AR (РЕСПУБЛИКА КОРЕЯ)

1. ОБЩИЕ ПОЛОЖЕНИЯ
Настоящая Политика описывает порядок обработки персональных данных сервисом Violetta AR Assistant при использовании AR HUD, камеры, микрофона и локальных AI-модулей на территории Республики Корея.

2. СБОР ДАННЫХ
Приложение может обрабатывать: голосовые команды, кадры камеры для OCR и air-gesture, технические метаданные устройства. Данные используются для предоставления функций ассистента и не продаются третьим лицам.

3. ПРАВОВЫЕ ОСНОВАНИЯ (PIPA)
Обработка осуществляется на основании согласия пользователя, необходимости исполнения договора оказания цифровых услуг и соблюдения требований законодательства РК.

4. ХРАНЕНИЕ И БЕЗОПАСНОСТЬ
Локальный кэш (Hive) хранит языковые настройки и флаг onboarding. Чувствительные ключи API хранятся только в защищённом .env на устройстве разработчика/сборки.

5. ПЕРЕДАЧА ТРЕТЬИМ ЛИЦАМ
Внешние вызовы могут включать Google Gemini API, Papago scraping pipeline и Naver Map SDK исключительно для функций, явно запрошенных пользователем.

6. ПРАВА ПОЛЬЗОВАТЕЛЯ
Вы вправе запросить доступ, исправление, удаление данных и отзыв согласия через службу поддержки Violetta.

7. МОНЕТИЗАЦИЯ MVP
Интеграции YouTube, TikTok, Telegram, WhatsApp и Facebook запускаются только по явной команде пользователя через системные intent Android.

8. КОНТАКТ
Data Protection Officer: privacy@violetta.ar
Последнее обновление: 2026-06-06
''';

const String _privacyKo = '''
VIOLETTA AR 개인정보 처리방침 (대한민국)

1. 총칙
본 방침은 Violetta AR Assistant가 AR HUD, 카메라, 마이크, 온디바이스 AI 모듈을 사용할 때 개인정보를 처리하는 방법을 설명합니다.

2. 수집 항목
음성 명령, OCR 및 에어 제스처용 카메라 프레임, 기기 기술 메타데이터가 처리될 수 있습니다. 데이터는 어시스턴트 기능 제공 목적으로만 사용되며 제3자에게 판매되지 않습니다.

3. 법적 근거 (개인정보보호법 PIPA)
사용자 동의, 디지털 서비스 제공 계약 이행, 대한민국 법령 준수를 근거로 처리합니다.

4. 보관 및 보안
로컬 Hive 캐시에는 언어 설정과 onboarding 완료 플래그만 저장됩니다. API 키는 빌드 환경의 .env에만 존재합니다.

5. 제3자 제공
Google Gemini API, Papago 파이프라인, Naver Map SDK는 사용자가 명시적으로 요청한 기능에 한해 호출됩니다.

6. 이용자 권리
열람, 정정, 삭제, 동의 철회를 privacy@violetta.ar 로 요청할 수 있습니다.

7. MVP 수익화
YouTube, TikTok, Telegram, WhatsApp, Facebook 연동은 사용자의 명시적 Android intent 명령으로만 실행됩니다.

8. 문의
개인정보보호책임자: privacy@violetta.ar
최종 업데이트: 2026-06-06
''';
