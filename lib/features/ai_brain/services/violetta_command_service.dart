import 'dart:async';

import 'package:flutter/services.dart';
import 'package:violetta_app/features/ai_brain/services/violetta_gemini_service.dart';

/// Parsed system-action token extracted from a Gemini response buffer.
class ViolettaCommandParseResult {
  final String? packageName;
  final String? rawToken;

  const ViolettaCommandParseResult({
    this.packageName,
    this.rawToken,
  });

  bool get isOpenAppCommand =>
      packageName != null && packageName!.trim().isNotEmpty;
}

/// Result of a streamed Gemini turn after command-token interception.
class ViolettaGeminiTurnResult {
  final bool commandExecuted;
  final bool appNotInstalled;
  final String? packageName;
  final String displayText;

  const ViolettaGeminiTurnResult({
    required this.commandExecuted,
    this.appNotInstalled = false,
    this.packageName,
    this.displayText = '',
  });
}

/// Parses `[SYSTEM_ACTION:...]` tokens and dispatches native OS intents.
class ViolettaCommandService {
  ViolettaCommandService();

  static const MethodChannel _systemControlChannel = MethodChannel(
    'com.violetta.ar/system_control',
  );

  static final RegExp openAppTokenPattern = RegExp(
    r'\[SYSTEM_ACTION:OPEN_APP:([^\]]+)\]',
    caseSensitive: false,
  );

  /// Searches [text] for an open-app system token and extracts the package id.
  ViolettaCommandParseResult parse(String text) {
    final RegExpMatch? match = openAppTokenPattern.firstMatch(text);
    if (match == null) {
      return const ViolettaCommandParseResult();
    }

    final String? packageName = match.group(1)?.trim();
    if (packageName == null || packageName.isEmpty) {
      return const ViolettaCommandParseResult();
    }

    return ViolettaCommandParseResult(
      packageName: packageName,
      rawToken: match.group(0),
    );
  }

  /// Streams Gemini output, stops early on token detection, and launches the app.
  Future<ViolettaGeminiTurnResult> processGeminiStream(
    ViolettaGeminiService gemini,
    String message,
  ) async {
    final StringBuffer buffer = StringBuffer();

    try {
      await for (final String chunk in gemini.sendMessageStream(message)) {
        buffer.write(chunk);
        final ViolettaCommandParseResult parsed = parse(buffer.toString());
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

  /// Returns `true` when the native app was launched to the foreground.
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

  String _stripSystemTokens(String text) {
    return text.replaceAll(openAppTokenPattern, '').trim();
  }
}
