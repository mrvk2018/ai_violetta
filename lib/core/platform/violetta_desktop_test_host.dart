import 'package:flutter/foundation.dart';

/// True on Flutter Web and Windows desktop — native Android gates are bypassed for PC testing.
bool get violettaBypassNativePermissions =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

/// True only when the Android MethodChannel handlers are present.
bool get violettaHasNativeAndroidBridge =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
