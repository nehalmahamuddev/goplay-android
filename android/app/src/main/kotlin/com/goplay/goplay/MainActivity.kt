package com.goplay.goplay

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Rational
import android.view.KeyEvent
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@UnstableApi
class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_PICK_PLAYLIST = 4109
        private const val MAX_PLAYLIST_BYTES = 25L * 1024L * 1024L
    }

    private var pipChannel: MethodChannel? = null
    private var playerKeysChannel: MethodChannel? = null
    private var filePickerChannel: MethodChannel? = null
    private var pendingFileResult: MethodChannel.Result? = null
    private var isPlayerActive = false
    private var isPlayerFullscreen = false

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

        playerKeysChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.goplay/player_keys")
        playerKeysChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPlayerFullscreen" -> {
                    isPlayerFullscreen = call.arguments as? Boolean ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        filePickerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.goplay/file_picker")
        filePickerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPlaylistFile" -> {
                    if (pendingFileResult != null) {
                        result.error("ALREADY_ACTIVE", "File picker is already active", null)
                        return@setMethodCallHandler
                    }
                    pendingFileResult = result
                    try {
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, REQUEST_PICK_PLAYLIST)
                    } catch (e: Exception) {
                        pendingFileResult = null
                        result.error("PICKER_UNAVAILABLE", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Required for FlutterActivity SAF file result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_PLAYLIST) {
            val callback = pendingFileResult
            pendingFileResult = null
            if (callback == null) {
                @Suppress("DEPRECATION")
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            val uri = data.data!!
            try {
                var displayName: String? = null
                var fileSize: Long = -1L
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0) {
                            displayName = cursor.getString(nameIdx)
                        }
                        val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                            fileSize = cursor.getLong(sizeIdx)
                        }
                    }
                }
                if (fileSize > MAX_PLAYLIST_BYTES) {
                    callback.error("FILE_TOO_LARGE", "Selected file exceeds 25 MB limit", null)
                    return
                }
                val content = contentResolver.openInputStream(uri)?.use { stream ->
                    val out = java.io.ByteArrayOutputStream()
                    val buf = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val read = stream.read(buf)
                        if (read <= 0) break
                        total += read
                        if (total > MAX_PLAYLIST_BYTES) {
                            callback.error("FILE_TOO_LARGE", "Selected file exceeds 25 MB limit", null)
                            return
                        }
                        out.write(buf, 0, read)
                    }
                    String(out.toByteArray(), Charsets.UTF_8)
                } ?: ""
                callback.success(
                    mapOf(
                        "name" to (displayName ?: uri.lastPathSegment ?: "playlist.m3u"),
                        "content" to content,
                        "uri" to uri.toString()
                    )
                )
            } catch (e: Exception) {
                callback.error("READ_FAILED", e.message, null)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (isPlayerFullscreen && !isTvDevice()) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    playerKeysChannel?.invokeMethod("onVolumeKeyDelta", 0.05)
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    playerKeysChannel?.invokeMethod("onVolumeKeyDelta", -0.05)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
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
