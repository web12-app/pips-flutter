package com.crossberry.pips

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter activity with the Pips PiP bridge.
 *
 * While a video is playing, going to the background calls "enter" and Android
 * shrinks the activity into a floating Picture-in-Picture window, so the video
 * keeps playing over any other app. "exit" brings the activity back full
 * sized (used when the user opens the app again from PiP).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "pips/pip"
    private var inPip = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> {
                    result.success(startPip())
                }
                "exit" -> {
                    stopPip()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        // YouTube cookie bridge: reads the shared webview cookie jar so the app
        // can collect a Netscape cookies.txt (for server-side YouTube imports).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pips/youtube").setMethodCallHandler { call, result ->
            when (call.method) {
                "cookieHeader" -> {
                    val url = call.argument<String>("url") ?: "https://www.youtube.com"
                    try {
                        result.success(android.webkit.CookieManager.getInstance().getCookie(url) ?: "")
                    } catch (e: Exception) {
                        result.success("")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Enter PiP mode. Returns false when the device can't (API < 26). */
    private fun startPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isInPictureInPictureMode) return true
        return try {
            // Keep screen on + visible even when the device is locked.
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            val params = PictureInPictureParams.Builder().build()
            enterPictureInPictureMode(params)
            inPip = true
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Leave PiP mode (reopen the app full sized). */
    private fun stopPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!isInPictureInPictureMode) return
        // Re-launching the singleTop activity with CLEAR_TOP pulls it out of
        // the PiP window and back to the foreground.
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Some skins refuse; the user can still tap the PiP window.
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPip = isInPictureInPictureMode
        if (!isInPictureInPictureMode) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }
}
