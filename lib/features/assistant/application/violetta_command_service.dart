import 'dart:async';

import 'package:flutter/services.dart';
import 'package:violetta_app/features/ai_brain/services/violetta_gemini_service.dart';
import 'package:violetta_app/features/assistant/application/local_utility_formatter.dart';
import 'package:violetta_app/features/onboarding/application/violetta_locale_controller.dart';
import 'package:violetta_app/features/onboarding/domain/models/violetta_app_locale.dart';
import 'package:violetta_app/features/voice_output/data/services/local_tts_service.dart';

/// Parsed system-action token extracted from a Gemini response buffer.
class ViolettaCommandParseResult {
  final String? packageName;
  final ViolettaAppLocale? switchLocale;
  final int? alarmHour;
  final int? alarmMinute;
  final String? rawToken;

  const ViolettaCommandParseResult({
    this.packageName,
    this.switchLocale,
    this.alarmHour,
    this.alarmMinute,
    this.rawToken,
  });

  bool get isOpenAppCommand =>
      packageName != null && packageName!.trim().isNotEmpty;

  bool get isSwitchLocaleCommand => switchLocale != null;

  bool get isSetAlarmCommand => alarmHour != null && alarmMinute != null;
}

/// Fast local STT intercept result (time/date) before Gemini is invoked.
class ViolettaIncomingSttResult {
  final bool handled;
  final String confirmationSpeech;
  final String displayText;

  const ViolettaIncomingSttResult({
    required this.handled,
    this.confirmationSpeech = '',
    this.displayText = '',
  });
}

/// Result of a streamed Gemini turn after command-token interception.
class ViolettaGeminiTurnResult {
  final bool commandExecuted;
  final bool appNotInstalled;
  final bool localeSwitched;
  final bool alarmSet;
  final String? packageName;
  final ViolettaAppLocale? switchedLocale;
  final int? alarmHour;
  final int? alarmMinute;
  final String confirmationSpeech;
  final String displayText;

  const ViolettaGeminiTurnResult({
    required this.commandExecuted,
    this.appNotInstalled = false,
    this.localeSwitched = false,
    this.alarmSet = false,
    this.packageName,
    this.switchedLocale,
    this.alarmHour,
    this.alarmMinute,
    this.confirmationSpeech = '',
    this.displayText = '',
  });
}

/// Parses `[SYSTEM_ACTION:...]` tokens and dispatches native OS intents.
class ViolettaCommandService {
  ViolettaCommandService({
    ViolettaLocaleController? localeController,
    LocalTtsService? ttsService,
  })  : _localeController = localeController,
        _ttsService = ttsService;

  final ViolettaLocaleController? _localeController;
  final LocalTtsService? _ttsService;

  static const MethodChannel _systemControlChannel = MethodChannel(
    'com.violetta.ar/system_control',
  );

  static final RegExp openAppTokenPattern = RegExp(
    r'\[SYSTEM_ACTION:OPEN_APP:([^\]]+)\]',
    caseSensitive: false,
  );

  static final RegExp switchLocaleTokenPattern = RegExp(
    r'\[SYSTEM_ACTION:SWITCH_LOCALE:(KOREAN|RUSSIAN)\]',
    caseSensitive: false,
  );

  static final RegExp setAlarmTokenPattern = RegExp(
    r'\[SYSTEM_ACTION:SET_ALARM:(\d{2}):(\d{2})\]',
    caseSensitive: false,
  );

  /// Zero-latency local route for time/date queries before Gemini is called.
  Future<ViolettaIncomingSttResult> processIncomingSTT(
    String rawText, {
    ViolettaLocaleController? localeController,
    LocalTtsService? ttsService,
    DateTime Function()? clock,
  }) async {
    final ViolettaLocaleController? locale =
        localeController ?? _localeController ?? ViolettaLocaleController.instance;
    final LocalTtsService? tts = ttsService ?? _ttsService;
    final String normalized = rawText.trim().toLowerCase();

    if (normalized.isEmpty || locale == null) {
      return const ViolettaIncomingSttResult(handled: false);
    }

    final DateTime now = (clock ?? DateTime.now)();
    final ViolettaAppLocale activeLocale = locale.locale;
    String? speech;

    if (LocalUtilityFormatter.matchesDateQuery(normalized)) {
      speech = LocalUtilityFormatter.formatDate(now, activeLocale);
    } else if (LocalUtilityFormatter.matchesTimeQuery(normalized)) {
      speech = LocalUtilityFormatter.formatTime(now, activeLocale);
    }

    if (speech == null) {
      return const ViolettaIncomingSttResult(handled: false);
    }

    if (tts != null) {
      await tts.stop();
      await tts.speak(speech, activeLocale.ttsLocaleId);
    }

    return ViolettaIncomingSttResult(
      handled: true,
      confirmationSpeech: speech,
      displayText: speech,
    );
  }

  ViolettaCommandParseResult parse(String text) {
    final RegExpMatch? localeMatch = switchLocaleTokenPattern.firstMatch(text);
    if (localeMatch != null) {
      final String token = localeMatch.group(1)!.toUpperCase();
      final ViolettaAppLocale locale = token == 'KOREAN'
          ? ViolettaAppLocale.korean
          : ViolettaAppLocale.russian;
      return ViolettaCommandParseResult(
        switchLocale: locale,
        rawToken: localeMatch.group(0),
      );
    }

    final RegExpMatch? alarmMatch = setAlarmTokenPattern.firstMatch(text);
    if (alarmMatch != null) {
      final int? hour = int.tryParse(alarmMatch.group(1)!);
      final int? minute = int.tryParse(alarmMatch.group(2)!);
      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return ViolettaCommandParseResult(
          alarmHour: hour,
          alarmMinute: minute,
          rawToken: alarmMatch.group(0),
        );
      }
    }

    final RegExpMatch? openMatch = openAppTokenPattern.firstMatch(text);
    if (openMatch == null) {
      return const ViolettaCommandParseResult();
    }

    final String? packageName = openMatch.group(1)?.trim();
    if (packageName == null || packageName.isEmpty) {
      return const ViolettaCommandParseResult();
    }

    return ViolettaCommandParseResult(
      packageName: packageName,
      rawToken: openMatch.group(0),
    );
  }

  Future<ViolettaGeminiTurnResult> processGeminiStream(
    ViolettaGeminiService gemini,
    String message, {
    ViolettaLocaleController? localeController,
    LocalTtsService? ttsService,
  }) async {
    final ViolettaLocaleController? locale = localeController ?? _localeController;
    final LocalTtsService? tts = ttsService ?? _ttsService;
    final StringBuffer buffer = StringBuffer();

    try {
      await for (final String chunk in gemini.sendMessageStream(message)) {
        buffer.write(chunk);
        final String aggregate = buffer.toString();
        final ViolettaCommandParseResult parsed = parse(aggregate);

        if (parsed.isSwitchLocaleCommand) {
          await gemini.cancelActiveStream();
          return _executeLocaleSwitch(
            parsed.switchLocale!,
            localeController: locale,
            ttsService: tts,
          );
        }

        if (parsed.isSetAlarmCommand) {
          await gemini.cancelActiveStream();
          return _executeSetAlarm(
            parsed.alarmHour!,
            parsed.alarmMinute!,
            localeController: locale,
            ttsService: tts,
          );
        }

        if (parsed.isOpenAppCommand) {
          await gemini.cancelActiveStream();
          final bool launched = await executeOpenApp(parsed.packageName!);
          return ViolettaGeminiTurnResult(
            commandExecuted: launched,
            appNotInstalled: !launched,
            packageName: parsed.packageName,
          );
        }
      }
    } catch (_) {
      await gemini.cancelActiveStream();
      rethrow;
    }

    return ViolettaGeminiTurnResult(
      commandExecuted: false,
      displayText: _stripSystemTokens(buffer.toString()).trim(),
    );
  }

  Future<ViolettaGeminiTurnResult> switchLocale(
    ViolettaAppLocale locale, {
    ViolettaLocaleController? localeController,
    LocalTtsService? ttsService,
  }) {
    return _executeLocaleSwitch(
      locale,
      localeController: localeController ?? _localeController,
      ttsService: ttsService ?? _ttsService,
    );
  }

  Future<ViolettaGeminiTurnResult> _executeLocaleSwitch(
    ViolettaAppLocale locale, {
    required ViolettaLocaleController? localeController,
    required LocalTtsService? ttsService,
  }) async {
    final ViolettaLocaleController? controller =
        localeController ?? ViolettaLocaleController.instance;
    if (controller == null) {
      return const ViolettaGeminiTurnResult(commandExecuted: false);
    }

    await controller.setLocale(locale);
    final String confirmation = locale.localeSwitchConfirmation;
    if (ttsService != null) {
      await ttsService.stop();
      await ttsService.speak(confirmation, locale.ttsLocaleId);
    }

    return ViolettaGeminiTurnResult(
      commandExecuted: true,
      localeSwitched: true,
      switchedLocale: locale,
      confirmationSpeech: confirmation,
    );
  }

  Future<ViolettaGeminiTurnResult> _executeSetAlarm(
    int hour,
    int minute, {
    required ViolettaLocaleController? localeController,
    required LocalTtsService? ttsService,
  }) async {
    final ViolettaLocaleController? controller =
        localeController ?? ViolettaLocaleController.instance;
    final ViolettaAppLocale activeLocale =
        controller?.locale ?? ViolettaAppLocale.russian;

    await executeCreateAlarm(hour, minute);
    final String confirmation =
        LocalUtilityFormatter.formatAlarmConfirmation(hour, minute, activeLocale);

    if (ttsService != null) {
      await ttsService.stop();
      await ttsService.speak(confirmation, activeLocale.ttsLocaleId);
    }

    return ViolettaGeminiTurnResult(
      commandExecuted: true,
      alarmSet: true,
      alarmHour: hour,
      alarmMinute: minute,
      confirmationSpeech: confirmation,
      displayText: confirmation,
    );
  }

  Future<bool> executeOpenApp(String packageName) async {
    final String normalizedPackage = packageName.trim();
    if (normalizedPackage.isEmpty) {
      throw PlatformException(
        code: 'INVALID_PACKAGE',
        message: 'Package name is empty',
      );
    }

    try {
      final bool? launched = await _systemControlChannel.invokeMethod<bool>(
        'openApp',
        <String, String>{'package': normalizedPackage},
      );
      return launched ?? true;
    } on PlatformException catch (error) {
      if (error.code == 'NOT_INSTALLED') {
        return false;
      }
      rethrow;
    }
  }

  Future<void> executeCreateAlarm(int hour, int minutes) async {
    await _systemControlChannel.invokeMethod<void>(
      'createAlarm',
      <String, int>{
        'hour': hour,
        'minutes': minutes,
      },
    );
  }

  String _stripSystemTokens(String text) {
    return text
        .replaceAll(openAppTokenPattern, '')
        .replaceAll(switchLocaleTokenPattern, '')
        .replaceAll(setAlarmTokenPattern, '')
        .trim();
  }
}
