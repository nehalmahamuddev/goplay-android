package com.goplay.goplay

import android.content.Context
import android.content.ContextWrapper
import android.app.Activity
import android.app.Application
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.util.Base64
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecInfo
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import android.view.LayoutInflater
import android.media.AudioManager
import android.media.audiofx.LoudnessEnhancer
import android.provider.Settings
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native ExoPlayer/Media3 PlatformView for Flutter.
 *
 * Provides:
 * - Direct HLS/DASH playback with custom HTTP headers (Referer, User-Agent, etc.)
 * - ClearKey DRM (local license from kid/key hex pairs)
 * - Widevine DRM (remote license server with optional headers)
 * - Native hardware decoding via MediaCodec
 * - Automatic header propagation to all segment/key requests
 */
@UnstableApi
class NativePlayerView(
    private val context: Context,
    private val viewId: Int,
    private val messenger: BinaryMessenger,
    creationParams: Map<String, Any?>?
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "NativePlayerView"
        private const val CHANNEL_PREFIX = "com.goplay/native_player_"
    }

    private val container: FrameLayout = FrameLayout(context)
    private val useSurfaceView: Boolean = (creationParams?.get("use_surface_view") as? Boolean) == true
    private val playerView: PlayerView = LayoutInflater.from(context).inflate(
        if (useSurfaceView) R.layout.player_view_surface_layout else R.layout.player_view_layout,
        container,
        false
    ) as PlayerView
    private var player: ExoPlayer? = null
    private val methodChannel: MethodChannel
    private var fallbackStage = 0
    private var lifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null
    private var preferredQualityHeight: Int = -1
    private var hwAccelerationEnabled: Boolean = true
    private var backgroundAudioEnabled: Boolean = false
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private val audioManager: AudioManager? by lazy {
        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    @Suppress("DEPRECATION")
    private fun isTvDevice(): Boolean {
        val pm = context.packageManager
        val uiMode = context.getSystemService(Context.UI_MODE_SERVICE) as? android.app.UiModeManager
        return uiMode?.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
            pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(android.content.pm.PackageManager.FEATURE_TELEVISION)
    }

    init {
        // Setup PlayerView
        playerView.keepScreenOn = true // Keep screen awake while video is playing
        container.addView(playerView)

        // Setup MethodChannel for this view instance
        methodChannel = MethodChannel(messenger, "$CHANNEL_PREFIX$viewId")
        methodChannel.setMethodCallHandler(this)

        // Setup Activity Lifecycle monitoring to handle PiP dismissals / app background pause
        val activity = getActivity(context)
        if (activity != null) {
            val app = activity.application
            val callbacks = object : Application.ActivityLifecycleCallbacks {
                override fun onActivityPaused(act: Activity) {
                    if (act === activity) {
                        if (backgroundAudioEnabled) return
                        // Pause player if app goes to background/paused AND is not in PiP mode
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            if (!act.isInPictureInPictureMode) {
                                player?.pause()
                            }
                        } else {
                            player?.pause()
                        }
                    }
                }

                override fun onActivityStopped(act: Activity) {
                    if (act === activity) {
                        if (backgroundAudioEnabled) return
                        // Pause player immediately on activity stop (which includes PiP close/dismissal)
                        player?.pause()
                    }
                }

                override fun onActivityDestroyed(act: Activity) {
                    if (act === activity) {
                        player?.release()
                        player = null
                    }
                }

                override fun onActivityCreated(act: Activity, savedInstanceState: Bundle?) {}
                override fun onActivityStarted(act: Activity) {}
                override fun onActivityResumed(act: Activity) {}
                override fun onActivitySaveInstanceState(act: Activity, outState: Bundle) {}
            }
            lifecycleCallbacks = callbacks
            app.registerActivityLifecycleCallbacks(callbacks)
        }

        // If creation params were provided, initialize immediately
        if (creationParams != null) {
            val url = creationParams["url"] as? String
            if (!url.isNullOrBlank()) {
                initializePlayer(creationParams)
            }
        }
    }

    private fun getActivity(context: Context): Activity? {
        var ctx = context
        while (ctx is ContextWrapper) {
            if (ctx is Activity) {
                return ctx
            }
            ctx = ctx.baseContext
        }
        return null
    }

    override fun getView(): View = container

    override fun dispose() {
        Log.d(TAG, "Disposing NativePlayerView $viewId")
        lifecycleCallbacks?.let {
            getActivity(context)?.application?.unregisterActivityLifecycleCallbacks(it)
        }
        methodChannel.setMethodCallHandler(null)
        try {
            loudnessEnhancer?.release()
        } catch (_: Exception) {}
        loudnessEnhancer = null
        player?.release()
        player = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialState" -> {
                val am = audioManager
                val curVolume = if (am != null) {
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                    if (max > 0) cur.toFloat() / max.toFloat() else 0.5f
                } else {
                    1.0f
                }
                val activity = getActivity(context)
                val curBrightness = if (activity != null) {
                    val winBrightness = activity.window.attributes.screenBrightness
                    if (winBrightness >= 0f) {
                        winBrightness
                    } else {
                        try {
                            Settings.System.getInt(
                                activity.contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS
                            ) / 255f
                        } catch (_: Exception) {
                            0.5f
                        }
                    }
                } else {
                    0.5f
                }
                result.success(mapOf(
                    "volume" to curVolume.toDouble(),
                    "brightness" to curBrightness.coerceIn(0.004f, 1.0f).toDouble()
                ))
            }
            "play" -> {
                val args = call.arguments as? Map<*, *>
                if (args != null) {
                    @Suppress("UNCHECKED_CAST")
                    initializePlayer(args as Map<String, Any?>)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            }
            "pause" -> {
                player?.pause()
                result.success(true)
            }
            "resume" -> {
                player?.play()
                result.success(true)
            }
            "stop" -> {
                player?.stop()
                result.success(true)
            }
            "seekTo" -> {
                val positionMs = (call.arguments as? Number)?.toLong() ?: 0L
                player?.seekTo(positionMs)
                result.success(true)
            }
            "setVolume" -> {
                val volume = (call.arguments as? Double)?.toFloat() ?: 1.0f
                val am = audioManager
                if (am != null) {
                    val maxStep = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val curStep = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                    val targetStep = (volume.coerceIn(0.0f, 1.0f) * maxStep).roundToInt().coerceIn(0, maxStep)
                    if (targetStep != curStep) {
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, targetStep, 0)
                    }
                }
                player?.volume = 1.0f

                // Handle LoudnessEnhancer for volume boost above 100% (1.0 to 2.0)
                if (volume > 1.0f) {
                    val boost = ((volume - 1.0f) * 1000).toInt()
                    val existing = loudnessEnhancer
                    if (existing != null) {
                        try {
                            existing.setTargetGain(boost)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error updating LoudnessEnhancer gain", e)
                        }
                    } else {
                        val sessionId = player?.audioSessionId
                        if (sessionId != null && sessionId != AudioManager.ERROR) {
                            try {
                                loudnessEnhancer = LoudnessEnhancer(sessionId).apply {
                                    setTargetGain(boost)
                                    enabled = true
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error creating LoudnessEnhancer", e)
                            }
                        }
                    }
                } else {
                    try {
                        loudnessEnhancer?.release()
                    } catch (_: Exception) {}
                    loudnessEnhancer = null
                }
                result.success(true)
            }
            "setBrightness" -> {
                if (isTvDevice()) {
                    result.success(false)
                    return
                }
                val brightness = (call.arguments as? Double)?.toFloat() ?: -1.0f
                val activity = getActivity(context)
                if (activity != null) {
                    activity.runOnUiThread {
                        val lp = activity.window.attributes
                        lp.screenBrightness = if (brightness < 0) -1.0f else brightness.coerceIn(0.004f, 1.0f)
                        activity.window.attributes = lp
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "setQuality" -> {
                val height = (call.arguments as? Number)?.toInt() ?: -1
                preferredQualityHeight = height
                val exoPlayer = player
                if (exoPlayer != null) {
                    applyQuality(exoPlayer, height, flushBuffer = true)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "getVideoQualities" -> {
                val exoPlayer = player
                if (exoPlayer != null) {
                    val sortedHeights = extractVideoHeights(exoPlayer.currentTracks)
                    result.success(sortedHeights)
                } else {
                    result.success(emptyList<Int>())
                }
            }
            "setResizeMode" -> {
                val mode = call.arguments as? Int ?: 0
                playerView.resizeMode = mode
                result.success(true)
            }
            "toggleSubtitles" -> {
                val exoPlayer = player
                if (exoPlayer != null) {
                    val currentParams = exoPlayer.trackSelectionParameters
                    val isTextDisabled = currentParams.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
                    val builder = currentParams.buildUpon()
                    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !isTextDisabled)
                    exoPlayer.trackSelectionParameters = builder.build()
                    result.success(isTextDisabled) // returns the new enabled state (true if it was disabled)
                } else {
                    result.success(false)
                }
            }
            "cycleAudioTrack" -> {
                val exoPlayer = player
                if (exoPlayer != null) {
                    val currentParams = exoPlayer.trackSelectionParameters
                    val builder = currentParams.buildUpon()
                    val currentTracks = exoPlayer.currentTracks
                    val audioGroups = currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
                    
                    if (audioGroups.isNotEmpty()) {
                        val languages = audioGroups.flatMap { group ->
                            (0 until group.length).mapNotNull { trackIdx ->
                                group.getTrackFormat(trackIdx).language
                            }
                        }.distinct()
                        
                        if (languages.size > 1) {
                            val currentLang = currentParams.preferredAudioLanguages.firstOrNull()
                            val nextIdx = if (currentLang != null) {
                                (languages.indexOf(currentLang) + 1) % languages.size
                            } else {
                                1
                            }
                            val nextLang = languages[nextIdx]
                            builder.setPreferredAudioLanguage(nextLang)
                            exoPlayer.trackSelectionParameters = builder.build()
                            result.success(nextLang)
                        } else {
                            result.success("Default")
                        }
                    } else {
                        result.success("None")
                    }
                } else {
                    result.success(null)
                }
            }
            "setPlaybackSpeed" -> {
                val speed = (call.arguments as? Double)?.toFloat() ?: 1.0f
                player?.setPlaybackSpeed(speed)
                result.success(true)
            }
            "getState" -> {
                val exoPlayer = player
                val duration = exoPlayer?.duration ?: 0L
                val position = exoPlayer?.currentPosition ?: 0L
                val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
                val isLive = exoPlayer?.isCurrentMediaItemLive == true
                result.success(mapOf(
                    "isPlaying" to (exoPlayer?.playWhenReady == true),
                    "playbackState" to (exoPlayer?.playbackState ?: Player.STATE_IDLE),
                    "duration" to if (duration == C.TIME_UNSET) 0L else duration,
                    "position" to position,
                    "bufferedPosition" to bufferedPosition,
                    "isLive" to isLive
                ))
            }
            "dispose" -> {
                player?.release()
                player = null
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Initialize ExoPlayer with the given stream configuration.
     *
     * @param config Map containing:
     *   - "url": Stream URL (HLS .m3u8 or DASH .mpd)
     *   - "headers": Map<String, String> of HTTP headers
     *   - "drm_type": "clearkey" | "widevine" | null
     *   - "drm_kid": ClearKey KID hex string
     *   - "drm_key": ClearKey Key hex string
     *   - "drm_license_url": Widevine license server URL
     *   - "drm_license_headers": Map<String, String> for license requests
     */
    private fun initializePlayer(config: Map<String, Any?>) {
        val url = config["url"] as? String ?: return
        Log.d(TAG, "Initializing player with config: $config")

        // Apply initial quality, decoder, audio & aspect ratio preferences from settings
        val initialQuality = (config["initial_quality"] as? Number)?.toInt() ?: -1
        preferredQualityHeight = if (initialQuality > 0) initialQuality else -1
        val initialResizeMode = (config["initial_resize_mode"] as? Number)?.toInt() ?: 0
        playerView.resizeMode = initialResizeMode
        val bufferMode = config["buffer_mode"] as? String ?: "Balanced"
        hwAccelerationEnabled = (config["hw_acceleration"] as? Boolean) ?: true
        backgroundAudioEnabled = (config["background_audio"] as? Boolean) ?: false

        // --- Build HTTP DataSource Factory with custom headers ---
        val httpFactory = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)
            .setAllowCrossProtocolRedirects(true)

        @Suppress("UNCHECKED_CAST")
        val headers = config["headers"] as? Map<String, String>
        if (!headers.isNullOrEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
            Log.d(TAG, "Custom headers set: ${headers.keys}")
        }

        // Set a default User-Agent if not already specified
        val ua = headers?.entries?.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }?.value
        if (ua != null) {
            httpFactory.setUserAgent(ua)
        } else {
            httpFactory.setUserAgent("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36")
        }

        // --- Build DRM Session Manager if needed ---
        val drmType = config["drm_type"] as? String
        val drmSessionManager = when (drmType) {
            "clearkey" -> buildClearKeyDrm(config)
            "widevine" -> buildWidevineDrm(config, httpFactory)
            else -> null
        }

        // Reset DRM fallback state for this playback session
        fallbackStage = 0

        // --- Build MediaItem ---
        val uri = Uri.parse(url)
        val mediaItemBuilder = MediaItem.Builder().setUri(uri)

        // Auto-detect MIME type from URL or explicit manifest hint
        val urlLower = url.lowercase()
        val manifestHint = (config["drm_manifest_type"] as? String)?.lowercase()
        when {
            urlLower.contains(".mpd") || manifestHint == "mpd" || manifestHint == "dash" ->
                mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
            urlLower.contains(".m3u8") || manifestHint == "hls" || manifestHint == "m3u8" ->
                mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            manifestHint == "ss" || manifestHint == "smoothstreaming" ->
                mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_SS)
        }

        // Attach external subtitle track if provided
        val subtitleUrl = (config["subtitle_url"] as? String)?.trim()
        if (!subtitleUrl.isNullOrEmpty()) {
            val subLower = subtitleUrl.lowercase()
            val subMime = when {
                subLower.contains(".vtt") -> MimeTypes.TEXT_VTT
                subLower.contains(".ttml") || subLower.contains(".dfxp") -> MimeTypes.APPLICATION_TTML
                else -> MimeTypes.APPLICATION_SUBRIP
            }
            val subConfig = MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUrl))
                .setMimeType(subMime)
                .setLanguage("en")
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()
            mediaItemBuilder.setSubtitleConfigurations(listOf(subConfig))
        }

        // Configure DRM on the MediaItem if needed
        if (drmType == "clearkey" || drmType == "widevine") {
            val drmUuid = when (drmType) {
                "clearkey" -> C.CLEARKEY_UUID
                "widevine" -> C.WIDEVINE_UUID
                else -> null
            }
            if (drmUuid != null) {
                val drmConfig = MediaItem.DrmConfiguration.Builder(drmUuid)
                if (drmType == "widevine") {
                    val licenseUrl = config["drm_license_url"] as? String
                    if (licenseUrl != null) {
                        drmConfig.setLicenseUri(licenseUrl)
                    }
                    @Suppress("UNCHECKED_CAST")
                    val licenseHeaders = config["drm_license_headers"] as? Map<String, String>
                    if (!licenseHeaders.isNullOrEmpty()) {
                        drmConfig.setLicenseRequestHeaders(licenseHeaders)
                    }
                }
                mediaItemBuilder.setDrmConfiguration(drmConfig.build())
            }
        }

        val mediaItem = mediaItemBuilder.build()

        // --- Create MediaSource from factory ---
        val mediaSourceFactory = if (drmSessionManager != null) {
            DefaultMediaSourceFactory(httpFactory).setDrmSessionManagerProvider { drmSessionManager }
        } else {
            DefaultMediaSourceFactory(httpFactory)
        }
        val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)

        // --- Setup / Reuse ExoPlayer ---
        var exoPlayer = player
        if (exoPlayer == null) {
            val (minBufMs, maxBufMs, playBufMs, rebufMs) = when (bufferMode) {
                "Fast Load" -> listOf(5_000, 20_000, 500, 1_000)
                "High Stability" -> listOf(30_000, 90_000, 3_000, 5_000)
                else -> listOf(15_000, 50_000, 1_500, 2_000) // Balanced
            }
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(minBufMs, maxBufMs, playBufMs, rebufMs)
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()

            val renderersFactory = DefaultRenderersFactory(context)
                .setEnableDecoderFallback(true)
                .apply {
                    if (!hwAccelerationEnabled) {
                        setMediaCodecSelector(object : MediaCodecSelector {
                            override fun getDecoderInfos(
                                mimeType: String,
                                requiresSecureDecoder: Boolean,
                                requiresTunnelingDecoder: Boolean
                            ): MutableList<MediaCodecInfo> {
                                val all = MediaCodecUtil.getDecoderInfos(
                                    mimeType,
                                    requiresSecureDecoder,
                                    requiresTunnelingDecoder
                                )
                                return all.sortedBy { info ->
                                    val name = info.name.lowercase()
                                    val isSoftware = info.softwareOnly ||
                                        name.startsWith("c2.android.") ||
                                        name.startsWith("omx.google.") ||
                                        name.contains(".sw.")
                                    if (isSoftware) 0 else 1
                                }.toMutableList()
                            }
                        })
                    }
                }

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build()

            exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setLoadControl(loadControl)
                .setAudioAttributes(audioAttributes, true)
                .build()
            player = exoPlayer
            playerView.player = exoPlayer

            // Add player listeners
            exoPlayer.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    Log.e(TAG, "Playback error: ${error.errorCodeName} - ${error.message}", error)
                    
                    val errorMsg = error.message ?: ""
                    val causeMsg = error.cause?.message ?: ""
                    val isDrmError = (error.errorCode in 6000..6999) ||
                                     error.errorCodeName.startsWith("ERROR_CODE_DRM") ||
                                     errorMsg.contains("DRM", ignoreCase = true) ||
                                     errorMsg.contains("decrypt", ignoreCase = true) ||
                                     causeMsg.contains("decryption", ignoreCase = true) ||
                                     causeMsg.contains("crypto", ignoreCase = true)
                    
                    if (isDrmError && fallbackStage < 3) {
                        val isAudioFailing = errorMsg.contains("audio", ignoreCase = true) || 
                                             error.errorCodeName.contains("AUDIO")
                        val isVideoFailing = errorMsg.contains("video", ignoreCase = true) || 
                                             error.errorCodeName.contains("VIDEO")

                        try {
                            val currentParameters = exoPlayer.trackSelectionParameters
                            val builder = currentParameters.buildUpon()

                            if (fallbackStage == 0) {
                                if (isAudioFailing) {
                                    Log.w(TAG, "DRM audio error. Stage 1 fallback: Disabling audio track.")
                                    builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                                    fallbackStage = 1
                                } else if (isVideoFailing) {
                                    Log.w(TAG, "DRM video error. Stage 2 fallback: Restricting video to SD.")
                                    builder.setMaxVideoSizeSd()
                                    fallbackStage = 2
                                } else {
                                    Log.w(TAG, "General DRM error. Stage 2 fallback: Restricting video to SD first.")
                                    builder.setMaxVideoSizeSd()
                                    fallbackStage = 2
                                }
                            } else if (fallbackStage == 1) {
                                Log.w(TAG, "DRM error persists. Stage 3 fallback: Disabling audio and restricting video to SD.")
                                builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                                builder.setMaxVideoSizeSd()
                                fallbackStage = 3
                            } else if (fallbackStage == 2) {
                                Log.w(TAG, "DRM error persists. Stage 3 fallback: Disabling audio and restricting video to SD.")
                                builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                                builder.setMaxVideoSizeSd()
                                fallbackStage = 3
                            }

                            exoPlayer.trackSelectionParameters = builder.build()
                            exoPlayer.prepare()
                            exoPlayer.play()
                            return
                        } catch (fallbackEx: Exception) {
                            Log.e(TAG, "Failed to apply DRM fallback stage $fallbackStage", fallbackEx)
                        }
                    }

                    methodChannel.invokeMethod("onError", mapOf(
                        "code" to error.errorCode,
                        "message" to (error.message ?: "Unknown playback error"),
                        "errorCodeName" to error.errorCodeName,
                        "httpStatus" to extractHttpStatus(error),
                        "isDrmError" to isDrmError,
                        "causeName" to (error.cause?.javaClass?.simpleName ?: ""),
                        "causeMessage" to (error.cause?.message ?: "")
                    ))
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    val stateName = when (playbackState) {
                        Player.STATE_IDLE -> "idle"
                        Player.STATE_BUFFERING -> "buffering"
                        Player.STATE_READY -> if (exoPlayer.playWhenReady) "ready" else "paused"
                        Player.STATE_ENDED -> "ended"
                        else -> "unknown"
                    }
                    Log.d(TAG, "Playback state changed: $stateName")
                    sendPlayerState()
                }

                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                    Log.d(TAG, "playWhenReady changed: $playWhenReady, reason: $reason")
                    sendPlayerState()
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    Log.d(TAG, "isPlaying changed: $isPlaying")
                    sendPlayerState()
                }

                override fun onTracksChanged(tracks: Tracks) {
                    val sortedHeights = extractVideoHeights(tracks)
                    val activeHeight = extractSelectedVideoHeight(tracks)
                    Log.d(TAG, "onTracksChanged: detected video qualities: $sortedHeights, activeHeight: $activeHeight")
                    methodChannel.invokeMethod("onTracksChanged", mapOf(
                        "qualities" to sortedHeights,
                        "activeQuality" to activeHeight
                    ))

                    if (preferredQualityHeight > 0 && sortedHeights.isNotEmpty()) {
                        player?.let { p ->
                            applyQuality(p, preferredQualityHeight, flushBuffer = false)
                        }
                    }
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.height > 0) {
                        methodChannel.invokeMethod("onVideoSizeChanged", mapOf(
                            "width" to videoSize.width,
                            "height" to videoSize.height
                        ))
                    }
                }
            })
        } else {
            // Stop and reset for new media source
            exoPlayer.stop()
            exoPlayer.clearMediaItems()
            // Reset track selection parameters to default so new stream loads cleanly without stale bounds
            exoPlayer.trackSelectionParameters = TrackSelectionParameters.Builder().build()
        }

        // --- Start playback ---
        val autoPlay = (config["auto_play"] as? Boolean) ?: true
        try {
            exoPlayer.setMediaSource(mediaSource)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = autoPlay
            Log.d(TAG, "Player prepared and starting playback (autoPlay=$autoPlay)")
        } catch (e: Throwable) {
            Log.e(TAG, "Native player initialization error: ${e.message}", e)
            methodChannel.invokeMethod("onError", mapOf(
                "code" to -1,
                "message" to (e.message ?: "Failed to initialize video decoder"),
                "errorCodeName" to "NATIVE_INIT_ERROR",
                "isDrmError" to false,
                "causeName" to (e.javaClass.simpleName),
                "causeMessage" to (e.message ?: "")
            ))
        }
    }

    private fun extractVideoHeights(tracks: Tracks): List<Int> {
        val heights = mutableListOf<Int>()
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_VIDEO) {
                for (i in 0 until group.length) {
                    if (group.isTrackSupported(i)) {
                        val format = group.getTrackFormat(i)
                        if (format.height > 0) {
                            heights.add(format.height)
                        }
                    }
                }
            }
        }
        return heights.distinct().sortedDescending()
    }

    private fun findBestMatchingHeight(availableHeights: List<Int>, targetHeight: Int): Int {
        if (availableHeights.contains(targetHeight)) return targetHeight
        val lower = availableHeights.filter { it <= targetHeight }.maxOrNull()
        if (lower != null) return lower
        return availableHeights.minOrNull() ?: targetHeight
    }

    private fun applyQuality(exoPlayer: ExoPlayer, height: Int, flushBuffer: Boolean = true) {
        val currentParams = exoPlayer.trackSelectionParameters
        val builder = currentParams.buildUpon()
        builder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)

        if (height > 0) {
            val heights = extractVideoHeights(exoPlayer.currentTracks)
            val targetHeight = if (heights.isNotEmpty()) {
                findBestMatchingHeight(heights, height)
            } else {
                height
            }
            builder.setMaxVideoSize(Int.MAX_VALUE, targetHeight)
            builder.setMinVideoSize(1, targetHeight)

            for (group in exoPlayer.currentTracks.groups) {
                if (group.type == C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until group.length) {
                        if (group.getTrackFormat(i).height == targetHeight) {
                            builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
                            break
                        }
                    }
                }
            }
        } else {
            builder.setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
            builder.setMinVideoSize(0, 0)
        }

        exoPlayer.trackSelectionParameters = builder.build()

        if (flushBuffer && exoPlayer.playbackState == Player.STATE_READY) {
            val currentPos = exoPlayer.currentPosition
            exoPlayer.seekTo(currentPos)
        }
    }

    private fun extractSelectedVideoHeight(tracks: Tracks): Int {
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_VIDEO) {
                for (i in 0 until group.length) {
                    if (group.isTrackSelected(i)) {
                        val format = group.getTrackFormat(i)
                        if (format.height > 0) {
                            return format.height
                        }
                    }
                }
            }
        }
        return -1
    }

    private fun sendPlayerState() {
        val exoPlayer = player ?: return
        val playbackState = exoPlayer.playbackState
        val playWhenReady = exoPlayer.playWhenReady

        val stateName = when (playbackState) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> if (playWhenReady) "ready" else "paused"
            Player.STATE_ENDED -> "ended"
            else -> "unknown"
        }

        methodChannel.invokeMethod("onStateChanged", mapOf(
            "state" to stateName,
            "isPlaying" to playWhenReady,
            "bufferedPosition" to (exoPlayer.bufferedPosition),
            "position" to (exoPlayer.currentPosition),
            "duration" to (if (exoPlayer.duration == C.TIME_UNSET) 0L else exoPlayer.duration)
        ))
    }

    /**
     * Build ClearKey DRM session manager from hex kid/key.
     */
    private fun buildClearKeyDrm(config: Map<String, Any?>): DefaultDrmSessionManager? {
        val keysArray = JSONArray()

        val clearKeys = config["drm_clearkeys"] as? Map<*, *>
        if (!clearKeys.isNullOrEmpty()) {
            for ((kidRaw, keyRaw) in clearKeys) {
                val kidHex = kidRaw as? String
                val keyHex = keyRaw as? String
                if (kidHex != null && keyHex != null) {
                    try {
                        val kidBytes = hexToBytes(kidHex)
                        val keyBytes = hexToBytes(keyHex)
                        val kidB64 = Base64.encodeToString(kidBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
                        val keyB64 = Base64.encodeToString(keyBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

                        val keyObj = JSONObject().apply {
                            put("kty", "oct")
                            put("k", keyB64)
                            put("kid", kidB64)
                        }
                        keysArray.put(keyObj)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to parse kid/key pair: kid=$kidHex", e)
                    }
                }
            }
        } else {
            val kidHex = config["drm_kid"] as? String
            val keyHex = config["drm_key"] as? String
            if (kidHex != null && keyHex != null) {
                try {
                    val kidBytes = hexToBytes(kidHex)
                    val keyBytes = hexToBytes(keyHex)
                    val kidB64 = Base64.encodeToString(kidBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
                    val keyB64 = Base64.encodeToString(keyBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

                    val keyObj = JSONObject().apply {
                        put("kty", "oct")
                        put("k", keyB64)
                        put("kid", kidB64)
                    }
                    keysArray.put(keyObj)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse single kid/key: kid=$kidHex", e)
                }
            }
        }

        if (keysArray.length() == 0) {
            Log.w(TAG, "No ClearKey keys found in config")
            return null
        }

        return try {
            val licenseJson = JSONObject().apply {
                put("keys", keysArray)
                put("type", "temporary")
            }

            val licenseBytes = licenseJson.toString().toByteArray(Charsets.UTF_8)
            val callback = LocalMediaDrmCallback(licenseBytes)

            DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .setMultiSession(true)
                .build(callback)
                .also {
                    Log.d(TAG, "ClearKey DRM configured with ${keysArray.length()} keys. Enabled multi-session.")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build ClearKey DRM", e)
            null
        }
    }

    /**
     * Build Widevine DRM session manager with a remote license server.
     */
    private fun buildWidevineDrm(
        config: Map<String, Any?>,
        httpFactory: DefaultHttpDataSource.Factory
    ): DefaultDrmSessionManager? {
        val licenseUrl = config["drm_license_url"] as? String ?: return null

        return try {
            val callback = HttpMediaDrmCallback(licenseUrl, httpFactory)

            @Suppress("UNCHECKED_CAST")
            val licenseHeaders = config["drm_license_headers"] as? Map<String, String>
            licenseHeaders?.forEach { (key, value) ->
                callback.setKeyRequestProperty(key, value)
            }

            DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .build(callback)
                .also {
                    Log.d(TAG, "Widevine DRM configured: licenseUrl=$licenseUrl")
                }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build Widevine DRM", e)
            null
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val cleanHex = hex.replace(" ", "").lowercase()
        return ByteArray(cleanHex.length / 2) { i ->
            cleanHex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }

    /**
     * Walk the cause chain to extract an HTTP response code if present.
     */
    private fun extractHttpStatus(error: PlaybackException): Int? {
        var cause: Throwable? = error.cause
        while (cause != null) {
            if (cause is androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException) {
                return cause.responseCode
            }
            cause = cause.cause
        }
        return null
    }
}

/**
 * Factory for creating NativePlayerView instances from Flutter.
 */
@UnstableApi
class NativePlayerViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String, Any?>
        return NativePlayerView(context, viewId, messenger, creationParams)
    }
}
