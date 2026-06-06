package com.violetta_ar.violetta_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class ViolettaAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "VIOLETTA_A11Y"
        private const val GESTURE_DURATION_MS = 300L
        private const val GESTURE_COOLDOWN_MS = 450L

        private val SCROLL_TARGET_PACKAGES = setOf(
            "com.zhiliaoapp.musically",
            "com.google.android.youtube",
        )

        var instance: ViolettaAccessibilityService? = null
            private set
    }

    private data class GestureBounds(
        val centerX: Float,
        val startY: Float,
        val endY: Float,
    )

    private var lastGestureDispatchAtMs: Long = 0L
    private var gestureInFlight: Boolean = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        instance = null
        gestureInFlight = false
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {
        gestureInFlight = false
    }

    fun swipeUp(): Boolean = dispatchScrollGesture(swipeUp = true)

    fun swipeDown(): Boolean = dispatchScrollGesture(swipeUp = false)

    fun dispatchScrollGesture(swipeUp: Boolean): Boolean {
        if (gestureInFlight) {
            Log.d(TAG, "Gesture skipped: previous stroke still in flight")
            return false
        }

        val now = System.currentTimeMillis()
        if (now - lastGestureDispatchAtMs < GESTURE_COOLDOWN_MS) {
            Log.d(TAG, "Gesture skipped: cooldown active")
            return false
        }

        if (!isScrollableTargetForeground()) {
            Log.d(TAG, "Gesture skipped: foreground app is not TikTok or YouTube")
            return false
        }

        val bounds = resolveGestureBounds() ?: run {
            Log.w(TAG, "Gesture skipped: unable to resolve window bounds")
            return false
        }

        val path = Path().apply {
            if (swipeUp) {
                moveTo(bounds.centerX, bounds.startY)
                lineTo(bounds.centerX, bounds.endY)
            } else {
                moveTo(bounds.centerX, bounds.endY)
                lineTo(bounds.centerX, bounds.startY)
            }
        }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, GESTURE_DURATION_MS))
            .build()

        gestureInFlight = true
        lastGestureDispatchAtMs = now

        val dispatched = dispatchGesture(
            gesture,
            object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    gestureInFlight = false
                    Log.d(
                        TAG,
                        "Scroll gesture completed direction=${if (swipeUp) "UP" else "DOWN"}",
                    )
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    gestureInFlight = false
                    Log.w(
                        TAG,
                        "Scroll gesture cancelled direction=${if (swipeUp) "UP" else "DOWN"}",
                    )
                }
            },
            null,
        )

        if (!dispatched) {
            gestureInFlight = false
            Log.w(TAG, "dispatchGesture returned false")
        }

        return dispatched
    }

    private fun isScrollableTargetForeground(): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        return try {
            val packageName = rootNode.packageName?.toString().orEmpty()
            SCROLL_TARGET_PACKAGES.contains(packageName)
        } finally {
            rootNode.recycle()
        }
    }

    private fun resolveGestureBounds(): GestureBounds? {
        val displayMetrics: DisplayMetrics = resources.displayMetrics
        val windowBounds = readActiveWindowBounds()

        val left = windowBounds?.left?.toFloat() ?: 0f
        val top = windowBounds?.top?.toFloat() ?: 0f
        val width = windowBounds?.width()?.toFloat()
            ?: displayMetrics.widthPixels.toFloat()
        val height = windowBounds?.height()?.toFloat()
            ?: displayMetrics.heightPixels.toFloat()

        if (width <= 0f || height <= 0f) {
            return null
        }

        val safeLeft = left.coerceAtLeast(0f)
        val safeTop = top.coerceAtLeast(0f)
        val safeWidth = width.coerceAtMost(displayMetrics.widthPixels.toFloat())
        val safeHeight = height.coerceAtMost(displayMetrics.heightPixels.toFloat())

        val centerX = safeLeft + (safeWidth / 2f)
        val upperY = safeTop + (safeHeight * 0.25f)
        val lowerY = safeTop + (safeHeight * 0.75f)

        return GestureBounds(
            centerX = centerX,
            startY = lowerY,
            endY = upperY,
        )
    }

    private fun readActiveWindowBounds(): Rect? {
        val rootNode: AccessibilityNodeInfo = rootInActiveWindow ?: return null
        return try {
            val bounds = Rect()
            rootNode.getBoundsInScreen(bounds)
            if (bounds.width() <= 0 || bounds.height() <= 0) {
                null
            } else {
                bounds
            }
        } catch (error: Exception) {
            Log.w(TAG, "Failed to read active window bounds", error)
            null
        } finally {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                rootNode.recycle()
            } else {
                @Suppress("DEPRECATION")
                rootNode.recycle()
            }
        }
    }
}
