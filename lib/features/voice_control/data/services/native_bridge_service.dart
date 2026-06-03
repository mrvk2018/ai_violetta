import 'package:flutter/services.dart';

class NativeBridgeService {
  static const MethodChannel _platform = MethodChannel(
    'package:violetta_app/native_bridge',
  );

  static Future<void> openApp(String packageName) async {
    try {
      await _platform.invokeMethod('openApp', <String, String>{
        'packageName': packageName,
      });
    } on PlatformException catch (e) {
      print('Ошибка открытия приложения: ${e.message}');
    }
  }

  static Future<void> performSystemSwipe() async {
    try {
      await _platform.invokeMethod('performSwipe');
    } on PlatformException catch (e) {
      print('Ошибка выполнения свайпа: ${e.message}');
    }
  }
}
