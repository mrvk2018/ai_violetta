import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:violetta_app/core/platform/violetta_desktop_test_host.dart';

class NativeBridgeService {
  static const MethodChannel _platform = MethodChannel(
    'package:violetta_app/native_bridge',
  );
  static const MethodChannel _systemControl = MethodChannel(
    'com.violetta.ar/system_control',
  );

  static Future<bool> openApp(String packageName) async {
    if (!violettaHasNativeAndroidBridge) {
      debugPrint(
        '[system_control] openApp package=$packageName '
        '(stub: ${defaultTargetPlatform.name})',
      );
      return true;
    }
    try {
      final bool? launched = await _systemControl.invokeMethod<bool>(
        'openApp',
        <String, String>{'package': packageName},
      );
      return launched ?? true;
    } on PlatformException catch (error) {
      if (error.code == 'NOT_INSTALLED') {
        return false;
      }
      print('Ошибка открытия приложения: ${error.message}');
      return false;
    }
  }

  static Future<bool> performSystemSwipe({bool swipeUp = true}) async {
    if (!violettaHasNativeAndroidBridge) {
      debugPrint(
        '[native_bridge] performSwipe swipeUp=$swipeUp '
        '(stub: ${defaultTargetPlatform.name})',
      );
      return false;
    }
    try {
      final bool? dispatched = await _platform.invokeMethod<bool>(
        'performSwipe',
        <String, bool>{'swipeUp': swipeUp},
      );
      return dispatched ?? true;
    } on PlatformException catch (e) {
      print('Ошибка выполнения свайпа: ${e.message}');
      return false;
    }
  }

  static Future<void> openAccessibilitySettings() async {
    if (!violettaHasNativeAndroidBridge) {
      debugPrint(
        '[native_bridge] openAccessibilitySettings '
        '(stub: ${defaultTargetPlatform.name})',
      );
      return;
    }
    try {
      await _platform.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException catch (e) {
      print('Ошибка открытия настроек доступности: ${e.message}');
    }
  }

  static Future<bool> isAccessibilityServiceEnabled() async {
    if (violettaBypassNativePermissions) {
      return true;
    }
    if (!violettaHasNativeAndroidBridge) {
      return false;
    }
    try {
      final bool? enabled = await _platform.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return enabled ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
