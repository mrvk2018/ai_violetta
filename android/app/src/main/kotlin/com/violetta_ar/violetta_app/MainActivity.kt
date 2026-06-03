package com.violetta_ar.violetta_app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "package:violetta_app/native_bridge"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.error("INVALID_PACKAGE", "Package name is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val launchIntent =
                            packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            startActivity(launchIntent)
                            result.success(null)
                        } else {
                            result.error("APP_NOT_FOUND", "App not found: $packageName", null)
                        }
                    } catch (e: Exception) {
                        result.error(
                            "OPEN_APP_FAILED",
                            e.message ?: "Failed to open app",
                            null,
                        )
                    }
                }

                "performSwipe" -> {
                    if (ViolettaAccessibilityService.instance != null) {
                        ViolettaAccessibilityService.instance?.swipeUp()
                        Log.d(
                            "VIOLETTA_NATIVE",
                            "Native swipe up dispatched via Accessibility Service",
                        )
                        result.success(null)
                    } else {
                        result.error(
                            "UNAVAILABLE",
                            "Accessibility Service не запущен. Включите его в настройках телефона.",
                            null,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
