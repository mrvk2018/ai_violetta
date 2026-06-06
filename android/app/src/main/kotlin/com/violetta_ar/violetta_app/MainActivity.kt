package com.violetta_ar.violetta_app

import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "VIOLETTA_NATIVE"
        private const val SYSTEM_CONTROL_CHANNEL = "com.violetta.ar/system_control"
        private const val NATIVE_BRIDGE_CHANNEL = "package:violetta_app/native_bridge"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CONTROL_CHANNEL,
        ).setMethodCallHandler(::onSystemControlMethodCall)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NATIVE_BRIDGE_CHANNEL,
        ).setMethodCallHandler(::onNativeBridgeMethodCall)
    }

    private fun onSystemControlMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openApp" -> {
                val packageName = call.argument<String>("package")
                    ?: call.argument<String>("packageName")
                openInstalledApp(packageName, result)
            }

            else -> result.notImplemented()
        }
    }

    private fun onNativeBridgeMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "performSwipe" -> performAccessibilitySwipe(call, result)
            else -> result.notImplemented()
        }
    }

    private fun openInstalledApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("INVALID_PACKAGE", "Package name is required", null)
            return
        }

        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent == null) {
                result.error("NOT_INSTALLED", "App not found", null)
                return
            }

            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )

            startActivity(launchIntent)
            Log.d(TAG, "openApp success package=$packageName")
            result.success(true)
        } catch (error: Exception) {
            Log.e(TAG, "openApp failed package=$packageName", error)
            result.error(
                "OPEN_APP_FAILED",
                error.message ?: "Failed to open app",
                null,
            )
        }
    }

    private fun performAccessibilitySwipe(call: MethodCall, result: MethodChannel.Result) {
        val swipeUp = call.argument<Boolean>("swipeUp") ?: true
        val accessibilityService = ViolettaAccessibilityService.instance
        if (accessibilityService != null) {
            val dispatched = accessibilityService.dispatchScrollGesture(swipeUp)
            if (dispatched) {
                Log.d(
                    TAG,
                    "Native scroll gesture dispatched direction=${if (swipeUp) "UP" else "DOWN"}",
                )
                result.success(true)
            } else {
                result.error(
                    "NOT_SCROLLABLE",
                    "Foreground app is not TikTok or YouTube, or gesture is throttled",
                    null,
                )
            }
            return
        }

        result.error(
            "UNAVAILABLE",
            "Accessibility Service не запущен. Включите его в настройках телефона.",
            null,
        )
    }
}
