package com.goplay.goplay

import android.content.pm.PackageManager
import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity : FlutterActivity() {
    private var pipChannel: MethodChannel? = null
    private var isPlayerActive = false

    private fun isTvDevice(): Boolean {
        val uiModeManager = getSystemService(UI_MODE_SERVICE) as? android.app.UiModeManager
        return uiModeManager?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
                packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable edge-to-edge around camera cutouts/notches on Android P (API 28+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        if (isTvDevice()) {
            // TV devices: retain fullscreen to avoid black overscan borders
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.let { controller ->
                    controller.hide(
                        android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars()
                    )
                    controller.systemBarsBehavior =
                        android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                )
            }
        } else {
            // Mobile devices: keep status bar visible with transparent edge-to-edge rendering
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.setDecorFitsSystemWindows(false)
                window.insetsController?.show(android.view.WindowInsets.Type.statusBars())
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                )
            }
        }
    }

    private fun supportsPiP(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the native ExoPlayer PlatformView
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.goplay/native_player",
                NativePlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.goplay/pip")
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    if (supportsPiP()) {
                        try {
                            val builder = PictureInPictureParams.Builder()
                            builder.setAspectRatio(Rational(16, 9))
                            val entered = enterPictureInPictureMode(builder.build())
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_FAILED", e.message, null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "PiP not supported on this device", null)
                    }
                }
                "setPlayerActive" -> {
                    isPlayerActive = call.arguments as? Boolean ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isPlayerActive && supportsPiP()) {
            try {
                val builder = PictureInPictureParams.Builder()
                builder.setAspectRatio(Rational(16, 9))
                enterPictureInPictureMode(builder.build())
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPiPModeChanged", isInPictureInPictureMode)
    }
}
