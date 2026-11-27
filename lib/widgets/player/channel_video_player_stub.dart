import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../core/constants.dart';
import '../../core/typography.dart';
import '../../models/channel.dart';
import '../../providers/app_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/playback/playback_engine.dart';
import '../../services/playback/playback_state.dart';
import '../../services/playback/playback_state_machine.dart';
import '../../services/playback/playback_telemetry.dart';
import '../tv_focus_wrapper.dart';
import 'channel_video_player.dart';

Widget getChannelVideoPlayer({
  required Channel channel,
  VoidCallback? onFullscreenToggle,
  bool isFullscreen = false,
  bool showControls = true,
  VoidCallback? onTap,
  VoidCallback? onPreviousChannel,
  VoidCallback? onNextChannel,
  VoidCallback? onInteract,
  VoidCallback? onFocusChannelPanel,
  bool isTvDevice = false,
  FocusNode? playPauseFocusNode,
  List<Channel>? servers,
  int activeServerIndex = 0,
  ValueChanged<int>? onServerSelected,
  bool isLocked = false,
  ValueChanged<bool>? onLockChanged,
}) {
  return ChannelVideoPlayerNative(
    channel: channel,
    onFullscreenToggle: onFullscreenToggle,
    isFullscreen: isFullscreen,
    showControls: showControls,
    onTap: onTap,
    onPreviousChannel: onPreviousChannel,
    onNextChannel: onNextChannel,
    onInteract: onInteract,
    onFocusChannelPanel: onFocusChannelPanel,
    isTvDevice: isTvDevice,
    playPauseFocusNode: playPauseFocusNode,
    servers: servers,
    activeServerIndex: activeServerIndex,
    onServerSelected: onServerSelected,
    isLocked: isLocked,
    onLockChanged: onLockChanged,
  );
}

class ChannelVideoPlayerNative extends StatefulWidget implements ChannelVideoPlayer {
  @override
  final Channel channel;
  @override
  final VoidCallback? onFullscreenToggle;
  @override
  final bool isFullscreen;
  @override
  final bool showControls;
  @override
  final VoidCallback? onTap;
  @override
  final VoidCallback? onPreviousChannel;
  @override
  final VoidCallback? onNextChannel;
  @override
  final VoidCallback? onInteract;
  @override
  final VoidCallback? onFocusChannelPanel;
  @override
  final bool isTvDevice;
  @override
  final FocusNode? playPauseFocusNode;
  @override
  final List<Channel>? servers;
  @override
  final int activeServerIndex;
  @override
  final ValueChanged<int>? onServerSelected;
  @override
  final bool isLocked;
  @override
  final ValueChanged<bool>? onLockChanged;

  const ChannelVideoPlayerNative({
    super.key,
    required this.channel,
    this.onFullscreenToggle,
    this.isFullscreen = false,
    this.showControls = true,
    this.onTap,
    this.onPreviousChannel,
    this.onNextChannel,
    this.onInteract,
    this.onFocusChannelPanel,
    this.isTvDevice = false,
    this.playPauseFocusNode,
    this.servers,
    this.activeServerIndex = 0,
    this.onServerSelected,
    this.isLocked = false,
    this.onLockChanged,
  });

  @override
  State<ChannelVideoPlayerNative> createState() => _ChannelVideoPlayerNativeState();
}

String _formatDuration(Duration d) {
  final hrs = d.inHours;
  final mins = d.inMinutes.remainder(60);
  final secs = d.inSeconds.remainder(60);
  if (hrs > 0) {
    return '$hrs:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

enum _DragType { none, seek, brightness, volume }
enum _SettingsSubpage { main, quality, speed, aspectRatio, servers }

class _ChannelVideoPlayerNativeState extends State<ChannelVideoPlayerNative> {
  MethodChannel? _methodChannel;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _hasError = false;
  String? _errorMessage;

  // Cache creation params to avoid re-building on every frame
  Map<String, dynamic>? _cachedParams;
  String? _cachedChannelId;

  // Player state variables for controls
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  Timer? _progressTimer;

  double _volume = 1.0;
  double _prevVolume = 1.0;
  bool _isMuted = false;

  double _brightness = 0.5;
  Timer? _osdHideTimer;

  final ValueNotifier<double?> _brightnessOsdNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<double?> _volumeOsdNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<String?> _gestureToastNotifier = ValueNotifier<String?>(null);
  Timer? _gestureToastTimer;
  static const _keysChannel = MethodChannel('com.goplay/player_keys');

  bool _swipeGesturesEnabled = true;
  bool _extraBrightnessEnabled = false;
  bool _doubleTapSeekEnabled = false;
  bool _isVolumeLocked = false;
  bool _isBrightnessLocked = false;
  bool _hasShownThresholdToast = false;
  bool _hasShownVolumeBoostToast = false;

  // Unified Drag/Pan & Scrubbing state
  _DragType _dragType = _DragType.none;
  Offset _dragStartPosition = Offset.zero;
  Duration _dragStartSeekPosition = Duration.zero;

  bool _isScrubbing = false;
  final ValueNotifier<Duration?> _scrubPositionNotifier = ValueNotifier<Duration?>(null);
  final ValueNotifier<Duration?> _seekDeltaNotifier = ValueNotifier<Duration?>(null);

  // 3-Zone Double Tap state
  int _doubleTapSeekSeconds = 0;
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;
  Timer? _doubleTapResetTimer;

  bool _isLive = false;

  void _onDoubleTapSeek(int seconds) {
    if (_duration <= Duration.zero) return;
    _doubleTapResetTimer?.cancel();
    final isLeft = seconds < 0;
    final currentAccum = (isLeft ? _showDoubleTapLeft : _showDoubleTapRight) ? _doubleTapSeekSeconds : 0;
    final newSeconds = currentAccum + seconds;

    _seekRelative(seconds, wakeControls: false);

    setState(() {
      _showDoubleTapLeft = isLeft;
      _showDoubleTapRight = !isLeft;
      _doubleTapSeekSeconds = newSeconds;
    });

    _doubleTapResetTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) {
        setState(() {
          _showDoubleTapLeft = false;
          _showDoubleTapRight = false;
          _doubleTapSeekSeconds = 0;
        });
      }
    });
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_isLocked) return;
    _loadGestureSettings();
    final width = MediaQuery.of(context).size.width;
    final x = details.localPosition.dx;
    if (x < width * 0.35) {
      if (_doubleTapSeekEnabled) {
        _onDoubleTapSeek(-10);
      }
    } else if (x > width * 0.65) {
      if (_doubleTapSeekEnabled) {
        _onDoubleTapSeek(10);
      }
    } else {
      widget.onFullscreenToggle?.call();
    }
  }

  void _loadGestureSettings() {
    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        final box = Hive.box(AppConstants.settingsBox);
        _swipeGesturesEnabled = box.get(AppConstants.volumeBrightnessGesturesKey) as bool? ?? true;
        _extraBrightnessEnabled = box.get(AppConstants.extraBrightnessKey) as bool? ?? false;
        _doubleTapSeekEnabled = box.get(AppConstants.doubleTapSeekKey) as bool? ?? false;
      }
    } catch (_) {}
  }

  void _showGestureToast(String message) {
    _gestureToastTimer?.cancel();
    _gestureToastNotifier.value = message;
    _gestureToastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _gestureToastNotifier.value = null;
      }
    });
  }

  Future<void> _fetchInitialPlayerState() async {
    try {
      final state = await _methodChannel?.invokeMapMethod<String, dynamic>('getInitialState');
      if (state != null && mounted) {
        final vol = (state['volume'] as num?)?.toDouble();
        final bri = (state['brightness'] as num?)?.toDouble();
        if (vol != null) {
          _volume = vol.clamp(0.0, 1.0);
          _isMuted = _volume == 0;
        }
        if (bri != null) {
          _brightness = bri.clamp(0.004, 1.0);
        }
      }
    } catch (e) {
      debugPrint('Error fetching initial player state: $e');
    }
  }

  Future<dynamic> _handleKeyMethodCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'onVolumeKeyDelta':
        final delta = (call.arguments as num?)?.toDouble() ?? 0.0;
        _handleVolumeKeyDelta(delta);
        break;
    }
  }

  void _handleVolumeKeyDelta(double delta) {
    final prev = _volume;
    final next = (_volume + delta).clamp(0.0, 2.0);
    if (prev <= 1.0 && next > 1.0 && !_hasShownVolumeBoostToast) {
      _hasShownVolumeBoostToast = true;
      _showGestureToast('Volume exceeded 100% (Boost)');
    } else if (next <= 1.0) {
      _hasShownVolumeBoostToast = false;
    }
    _volume = next;
    _isMuted = _volume == 0;
    _methodChannel?.invokeMethod('setVolume', _volume);
    _volumeOsdNotifier.value = _volume;
    _startOsdHideTimer();
  }

  void _handlePanStart(DragStartDetails details) {
    if (_isLocked) return;
    _loadGestureSettings();
    _dragStartPosition = details.localPosition;
    _dragStartSeekPosition = _position;
    _dragType = _DragType.none;
    _osdHideTimer?.cancel();
    _isVolumeLocked = _volume < 1.0;
    _isBrightnessLocked = _brightness < 1.0;
    _hasShownThresholdToast = false;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_isLocked) return;
    final screen = MediaQuery.of(context).size;
    if (screen.width <= 0 || screen.height <= 0) return;

    final dx = details.localPosition.dx - _dragStartPosition.dx;
    final dy = details.localPosition.dy - _dragStartPosition.dy;

    // Disambiguate drag type if not decided yet
    if (_dragType == _DragType.none) {
      if (dx.abs() < 10 && dy.abs() < 10) return;

      if (dx.abs() > dy.abs() * 1.2 && _duration > Duration.zero) {
        // Horizontal swipe -> Seek scrub!
        _dragType = _DragType.seek;
        _isScrubbing = true;
        _scrubPositionNotifier.value = _position;
        _seekDeltaNotifier.value = Duration.zero;
      } else if (dy.abs() > dx.abs()) {
        // Vertical swipe -> Brightness (left half) or Volume (right half)
        // Respect settings toggle & fullscreen mode
        if (widget.isFullscreen && _swipeGesturesEnabled) {
          if (_dragStartPosition.dx < screen.width / 2) {
            _dragType = _DragType.brightness;
            _brightnessOsdNotifier.value = _brightness;
          } else {
            _dragType = _DragType.volume;
            _volumeOsdNotifier.value = _volume;
          }
        }
      }
    }

    // Process active drag
    if (_dragType == _DragType.seek && _duration > Duration.zero) {
      final scrubRangeMs = (_duration.inMilliseconds > 600000)
          ? (_duration.inMilliseconds * 0.25).clamp(90000.0, 600000.0)
          : (_duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 90000.0);
      final seekDeltaMs = ((dx / screen.width) * scrubRangeMs).round();
      final targetMs = (_dragStartSeekPosition.inMilliseconds + seekDeltaMs)
          .clamp(0, _duration.inMilliseconds);
      final targetPos = Duration(milliseconds: targetMs);
      _scrubPositionNotifier.value = targetPos;
      _seekDeltaNotifier.value = Duration(milliseconds: targetMs - _dragStartSeekPosition.inMilliseconds);
    } else if (_dragType == _DragType.brightness) {
      final delta = -details.delta.dy / (screen.height * 0.7);
      final raw = _brightness + delta;
      double next;
      final maxAllowed = _extraBrightnessEnabled ? 2.0 : 1.0;
      if (_isBrightnessLocked || !_extraBrightnessEnabled) {
        next = raw.clamp(0.004, 1.0);
        if (_extraBrightnessEnabled && raw > 1.0 && !_hasShownThresholdToast) {
          _hasShownThresholdToast = true;
          _showGestureToast('Slide up again to exceed 100%');
        }
      } else {
        next = raw.clamp(0.004, maxAllowed);
      }
      _brightness = next;
      _methodChannel?.invokeMethod('setBrightness', _brightness.clamp(0.004, 1.0));
      _brightnessOsdNotifier.value = _brightness;
    } else if (_dragType == _DragType.volume) {
      final delta = -details.delta.dy / (screen.height * 0.7);
      final raw = _volume + delta;
      double next;
      if (_isVolumeLocked) {
        next = raw.clamp(0.0, 1.0);
        if (raw > 1.0 && !_hasShownThresholdToast) {
          _hasShownThresholdToast = true;
          _showGestureToast('Slide up again to exceed 100%');
        }
      } else {
        next = raw.clamp(0.0, 2.0);
      }
      _volume = next;
      _isMuted = _volume == 0;
      _methodChannel?.invokeMethod('setVolume', _volume);
      _volumeOsdNotifier.value = _volume;
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_dragType == _DragType.seek) {
      final finalTarget = _scrubPositionNotifier.value;
      if (finalTarget != null) {
        _seekTo(finalTarget);
      }
      _scrubPositionNotifier.value = null;
      _seekDeltaNotifier.value = null;
      _isScrubbing = false;
    } else if (_dragType == _DragType.brightness || _dragType == _DragType.volume) {
      _startOsdHideTimer();
    }
    _dragType = _DragType.none;
  }

  void _handlePanCancel() {
    _handlePanEnd(DragEndDetails());
  }

  void _startOsdHideTimer() {
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _brightnessOsdNotifier.value = null;
        _volumeOsdNotifier.value = null;
      }
    });
  }


  String _currentQuality = 'Auto';
  List<int> _availableQualities = [];
  int _activeQualityHeight = -1;
  bool _isDetectingQualities = true;
  double _playbackSpeed = 1.0;
  final List<double> _speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
  StateSetter? _settingsModalSetState;

  int _aspectRatioIndex = 0;
  bool _isLocked = false;
  // ignore: unused_field
  bool _subtitlesEnabled = true;

  final List<int> _resizeModes = [0, 3, 4]; // RESIZE_MODE_FIT, RESIZE_MODE_FILL, RESIZE_MODE_ZOOM
  final List<String> _aspectLabels = ['FIT', 'STRETCH', 'ZOOM'];

  static const _pipChannel = MethodChannel('com.goplay/pip');

  // ─── Playback Engine ───────────────────────────────────────────

  late final PlaybackEngine _engine;

  // ─── Pre-cached gradient decorations — allocated once, not per build() ──

  static final _kGradientOverlayFS = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Colors.black.withAlpha(200),
        Colors.transparent,
        Colors.transparent,
      ],
    ),
  );
  static final _kGradientOverlayPortrait = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Colors.black.withAlpha(200),
        Colors.transparent,
        Colors.black.withAlpha(160),
      ],
    ),
  );

  String? _cachedStreamUrl;

  // ─── Creation params ─────────────────────────────────────────────

  Map<String, dynamic> _getCreationParams() {
    if (_cachedParams != null &&
        _cachedChannelId == widget.channel.id &&
        _cachedStreamUrl == widget.channel.streamUrl) {
      return _cachedParams!;
    }
    _cachedChannelId = widget.channel.id;
    _cachedStreamUrl = widget.channel.streamUrl;
    _cachedParams = _buildCreationParams();
    return _cachedParams!;
  }

  Map<String, dynamic> _buildCreationParams() {
    final headers = widget.channel.headers.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    String? subtitleUrl;
    String? headerManifestType;
    final removeKeys = <String>[];
    for (final entry in headers.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'x-subtitle-url') {
        subtitleUrl = entry.value.trim();
        removeKeys.add(entry.key);
      } else if (lower == 'x-manifest-type') {
        headerManifestType = entry.value.trim();
        removeKeys.add(entry.key);
      }
    }
    for (final k in removeKeys) {
      headers.remove(k);
    }

    // Bypass local proxy — ExoPlayer's DefaultHttpDataSource.Factory
    // already propagates custom headers to all sub-requests (manifests,
    // segments, keys) natively.  Routing segments through the Dart heap
    // caused severe GC stalls (CollectNewGeneration up to 9.5 s).
    final rawUrl = widget.channel.streamUrl.trim();
    final isPendingDynamic = rawUrl.isEmpty || rawUrl.startsWith('pro/') || rawUrl.contains('.txt');
    final playUrl = isPendingDynamic ? '' : rawUrl;

    int initialQuality = -1;
    if (_currentQuality != 'Auto') {
      initialQuality = int.tryParse(_currentQuality.replaceAll('p', '')) ?? -1;
    }

    final params = <String, dynamic>{
      'url': playUrl,
      'headers': headers,
      'initial_quality': initialQuality,
    };

    if (subtitleUrl != null && subtitleUrl.isNotEmpty) {
      params['subtitle_url'] = subtitleUrl;
    }
    if (headerManifestType != null && headerManifestType.isNotEmpty && headerManifestType != 'auto') {
      params['drm_manifest_type'] = headerManifestType;
    }

    if (widget.channel.hasDrm) {
      final drm = widget.channel.drm!;
      params['drm_type'] = drm.type.name;
      if (drm.manifestType != null && drm.manifestType!.isNotEmpty) {
        params['drm_manifest_type'] = drm.manifestType;
      }

      if (drm.isClearKey) {
        if (drm.kid != null) params['drm_kid'] = drm.kid;
        if (drm.key != null) params['drm_key'] = drm.key;
        if (drm.clearKeys != null) params['drm_clearkeys'] = drm.clearKeys;
      } else if (drm.isWidevine) {
        if (drm.licenseUrl != null) params['drm_license_url'] = drm.licenseUrl;
        if (drm.licenseHeaders != null) params['drm_license_headers'] = drm.licenseHeaders;
      }
    }

    return params;
  }

  // ─── Platform view lifecycle ─────────────────────────────────────

  void _onPlatformViewCreated(int id) {
    _methodChannel = MethodChannel('com.goplay/native_player_$id');
    _methodChannel!.setMethodCallHandler(_handleMethodCall);
    _engine.nativePort.setChannel(_methodChannel);
    _engine.keepAlive.syncForUrl(widget.channel.streamUrl);
    _fetchInitialPlayerState();
  }

  // ─── Method call handler ─────────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (!mounted) return;

    switch (call.method) {
      case 'onStateChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final state = args['state'] as String;
        final isPlaying = args['isPlaying'] as bool? ?? false;
        final nowBuffering = state == 'buffering';
        final isReady = state == 'ready' || state == 'playing';

        // Delegate recovery, buffering monitor, and stall-to-Auto downgrade to engine
        _engine.handleNativeStateEvent(args);

        // Update local UI state for controls rendering
        if (_isPlaying != isPlaying || _isBuffering != nowBuffering ||
            (isReady && (_hasError || _errorMessage != null))) {
          setState(() {
            _isPlaying = isPlaying;
            _isBuffering = nowBuffering;
            if (isReady) {
              _hasError = false;
              _errorMessage = null;
            }
          });
        }

        if (isPlaying) {
          _startProgressTimer();
        } else {
          _stopProgressTimer();
        }
        _updateProgress();
        break;

      case 'onTracksChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final rawQualities = (args['qualities'] as List?)?.cast<int>() ?? [];
        final activeHeight = (args['activeQuality'] as int?) ?? -1;
        if (mounted) {
          setState(() {
            _availableQualities = rawQualities;
            _isDetectingQualities = false;
            if (activeHeight > 0) {
              _activeQualityHeight = activeHeight;
            } else if (_availableQualities.isNotEmpty && _activeQualityHeight <= 0) {
              _activeQualityHeight = _availableQualities.first;
            }

            // If user has a non-Auto preferred quality, apply best-effort matching via native player
            if (_currentQuality != 'Auto') {
              final targetHeight = int.tryParse(_currentQuality.replaceAll('p', '')) ?? -1;
              if (targetHeight > 0) {
                _methodChannel?.invokeMethod('setQuality', targetHeight);
              }
            }
          });
          try {
            _settingsModalSetState?.call(() {});
          } catch (_) {}
        }
        break;

      case 'onVideoSizeChanged':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final height = (args['height'] as int?) ?? -1;
        if (mounted && height > 0) {
          setState(() {
            _activeQualityHeight = height;
          });
          try {
            _settingsModalSetState?.call(() {});
          } catch (_) {}
        }
        break;

      case 'onError':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final message = args['message'] as String? ?? 'Unknown playback error';
        debugPrint('NativePlayer error: $message');
        _stopProgressTimer();

        // Delegate to engine — handles classification, retry, failover, or skip
        _engine.handleNativeError(args);
        break;
    }
  }

  // ─── Playback Engine Listener ────────────────────────────────────

  void _onEngineChanged() {
    if (!mounted) return;
    final smState = _engine.state;

    // Sync error state from engine into widget state
    switch (smState.phase) {
      case PlaybackPhase.failed:
        setState(() {
          _hasError = true;
          _errorMessage = smState.error?.userMessage ?? 'Unable to play this stream';
          _isBuffering = false;
        });
        break;

      case PlaybackPhase.waitingForInternet:
        setState(() {
          _hasError = true;
          _errorMessage = smState.error?.userMessage ?? 'No internet connection';
          _isBuffering = false;
        });
        break;

      case PlaybackPhase.retrying:
        // Show retrying state — not a hard error
        setState(() {
          _hasError = false;
          _isBuffering = true;
        });
        break;

      case PlaybackPhase.skipping:
        // Show skipping countdown — not a hard error
        setState(() {
          _hasError = false;
          _isBuffering = false;
        });
        break;

      case PlaybackPhase.preparing:
        setState(() {
          _hasError = false;
          _errorMessage = null;
          _isBuffering = true;
        });
        break;

      case PlaybackPhase.playing:
        setState(() {
          _hasError = false;
          _errorMessage = null;
        });
        break;

      default:
        break;
    }
  }

  // ─── Progress timer ──────────────────────────────────────────────

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted && _isPlaying) {
        _updateProgress();
      }
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
  }

  Future<void> _updateProgress() async {
    if (_methodChannel == null || _isScrubbing) return;
    try {
      final state = await _methodChannel!.invokeMethod<Map>('getState');
      if (state != null && mounted) {
        if (_isScrubbing) return;
        final newPlaying = state['isPlaying'] as bool? ?? _isPlaying;
        final newPos = Duration(milliseconds: (state['position'] as int? ?? 0));
        final newDur = Duration(milliseconds: (state['duration'] as int? ?? 0));
        final newBuf = Duration(milliseconds: (state['bufferedPosition'] as int? ?? 0));
        final isLive = state['isLive'] as bool? ?? false;

        // Skip rebuild when controls are hidden AND position delta is <2s
        if (!widget.showControls &&
            newPlaying == _isPlaying &&
            (newPos - _position).abs() < const Duration(seconds: 2) &&
            newDur == _duration &&
            isLive == _isLive) {
          _isPlaying = newPlaying;
          _position = newPos;
          _duration = newDur;
          _bufferedPosition = newBuf;
          _isLive = isLive;
          return;
        }

        // Skip rebuild if nothing actually changed
        if (newPlaying == _isPlaying &&
            newPos == _position &&
            newDur == _duration &&
            newBuf == _bufferedPosition &&
            isLive == _isLive) {
          return;
        }

        setState(() {
          _isPlaying = newPlaying;
          _position = newPos;
          _duration = newDur;
          _bufferedPosition = newBuf;
          _isLive = isLive;
        });
      }
    } catch (e) {
      debugPrint('Error getting player state: $e');
    }
  }

  // ─── Playback controls ───────────────────────────────────────────

  void _retryPlaybackInternal() {
    _cachedParams = null;
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
      _position = Duration.zero;
      _duration = Duration.zero;
      _bufferedPosition = Duration.zero;
    });
    _engine.nativePort.play(_getCreationParams());
  }

  /// Manual retry.
  void _retryPlayback() {
    _engine.manualRetry();
  }

  void _seekTo(Duration position) {
    _engine.nativePort.seekTo(position.inMilliseconds);
    setState(() {
      _position = position;
    });
  }

  void _setVolume(double value) {
    setState(() {
      _volume = value;
      _isMuted = value == 0.0;
    });
    _engine.nativePort.setVolume(value);
  }

  void _toggleMute() {
    if (_isMuted) {
      _setVolume(_prevVolume > 0 ? _prevVolume : 1.0);
    } else {
      _prevVolume = _volume;
      _setVolume(0.0);
    }
  }

  void _setQuality(String label, int height) {
    setState(() {
      _currentQuality = label;
    });
    _engine.setQualityLabel(label);
    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        Hive.box(AppConstants.settingsBox).put('default_video_quality', label);
      }
    } catch (_) {}
    _engine.nativePort.setQuality(height);
  }

  void _toggleAspectRatio() {
    setState(() {
      _aspectRatioIndex = (_aspectRatioIndex + 1) % _resizeModes.length;
    });
    final mode = _resizeModes[_aspectRatioIndex];
    _engine.nativePort.setResizeMode(mode);
  }

  // ignore: unused_element
  void _enterPiP() async {
    try {
      await _pipChannel.invokeMethod('enterPiP');
    } catch (e) {
      debugPrint('Failed to enter PiP: $e');
    }
  }

  // ignore: unused_element
  void _toggleSubtitles() async {
    if (_methodChannel == null) return;
    try {
      final enabled = await _methodChannel!.invokeMethod<bool>('toggleSubtitles');
      if (enabled != null && mounted) {
        setState(() {
          _subtitlesEnabled = enabled;
        });
      }
    } catch (e) {
      debugPrint('Error toggling subtitles: $e');
    }
  }

  // ignore: unused_element
  void _cycleAudioTrack() async {
    if (_methodChannel == null) return;
    try {
      await _methodChannel!.invokeMethod<String>('cycleAudioTrack');
    } catch (e) {
      debugPrint('Error cycling audio track: $e');
    }
  }

  // ignore: unused_element
  void _cyclePlaybackSpeed() async {
    if (_methodChannel == null) return;
    final speeds = [1.0, 1.25, 1.5, 2.0, 0.5];
    final currentIdx = speeds.indexOf(_playbackSpeed);
    final nextSpeed = speeds[(currentIdx + 1) % speeds.length];
    try {
      final success = await _methodChannel!.invokeMethod<bool>('setPlaybackSpeed', nextSpeed);
      if (success == true && mounted) {
        setState(() {
          _playbackSpeed = nextSpeed;
        });
      }
    } catch (e) {
      debugPrint('Error setting playback speed: $e');
    }
  }

  Future<void> _setSpeed(double speed) async {
    widget.onInteract?.call();
    try {
      final success = await _methodChannel?.invokeMethod<bool>('setPlaybackSpeed', speed);
      if (success == true && mounted) {
        setState(() {
          _playbackSpeed = speed;
        });
      }
    } catch (e) {
      debugPrint('Error setting playback speed: $e');
    }
  }

  void _showPlayerSettingsModal() {
    widget.onInteract?.call();

    // Query active qualities directly in case not yet pushed
    if (_methodChannel != null && _availableQualities.isEmpty) {
      _methodChannel!.invokeListMethod<int>('getVideoQualities').then((result) {
        if (result != null && mounted) {
          setState(() {
            _availableQualities = result;
            _isDetectingQualities = false;
          });
          _settingsModalSetState?.call(() {});
        }
      }).catchError((_) {});
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final cs = Theme.of(dialogContext).colorScheme;
        final mq = MediaQuery.of(dialogContext);
        final bool isWide = mq.size.width >= 600;
        final double sheetWidth = isWide ? math.min(mq.size.width * 0.85, 420.0) : double.infinity;
        final double maxHeight = mq.size.height * 0.85;

        bool isDismissing = false;
        void dismiss() {
          if (!isDismissing && Navigator.of(dialogContext).canPop()) {
            isDismissing = true;
            _settingsModalSetState = null;
            Navigator.of(dialogContext).pop();
          }
        }

        _SettingsSubpage currentSubpage = _SettingsSubpage.main;

        return StatefulBuilder(
          builder: (context, setModalState) {
            _settingsModalSetState = setModalState;
            final isLiveNoDvr = _isLive && _duration == Duration.zero;

            // Compute current quality display label for the root menu tile
            final String qualityMenuLabel;
            if (_currentQuality == 'Auto') {
              if (_activeQualityHeight > 0) {
                qualityMenuLabel = 'Auto (${_activeQualityHeight}p)';
              } else if (_availableQualities.isNotEmpty) {
                qualityMenuLabel = 'Auto (${_availableQualities.first}p)';
              } else {
                qualityMenuLabel = 'Auto';
              }
            } else {
              qualityMenuLabel = _currentQuality;
            }

            final String speedMenuLabel = isLiveNoDvr
                ? 'Live'
                : (_playbackSpeed == 1.0 ? '1x' : '${_playbackSpeed}x');

            final String aspectMenuLabel = _aspectLabels[_aspectRatioIndex];

            // Build page content based on currentSubpage
            Widget pageContent;
            switch (currentSubpage) {
              case _SettingsSubpage.main:
                pageContent = Column(
                  key: const ValueKey('settings_main'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSettingsMenuItem(
                      icon: Icons.tune_rounded,
                      title: 'Quality',
                      trailingValue: qualityMenuLabel,
                      cs: cs,
                      autoFocus: true,
                      onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.quality),
                    ),
                    _buildSettingsMenuItem(
                      icon: Icons.slow_motion_video_rounded,
                      title: 'Playback speed',
                      trailingValue: speedMenuLabel,
                      cs: cs,
                      onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.speed),
                    ),
                    _buildSettingsMenuItem(
                      icon: Icons.aspect_ratio_rounded,
                      title: 'Aspect ratio',
                      trailingValue: aspectMenuLabel,
                      cs: cs,
                      onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.aspectRatio),
                    ),
                    if (widget.servers != null && widget.servers!.length > 1)
                      _buildSettingsMenuItem(
                        icon: Icons.dns_rounded,
                        title: 'Stream Source',
                        trailingValue: widget.servers![widget.activeServerIndex].name.isNotEmpty
                            ? widget.servers![widget.activeServerIndex].name
                            : 'Server ${widget.activeServerIndex + 1}',
                        cs: cs,
                        onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.servers),
                      ),
                    _buildSettingsMenuItem(
                      icon: Icons.lock_outline_rounded,
                      title: 'Lock screen',
                      showChevron: false,
                      cs: cs,
                      onTap: () {
                        dismiss();
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _isLocked = true;
                        });
                        widget.onLockChanged?.call(true);
                      },
                    ),
                  ],
                );
                break;

              case _SettingsSubpage.quality:
                // Quality Subpage (YouTube Screenshot 2 style)
                final List<String> qualityOptions = ['Auto'];
                if (_availableQualities.contains(2160)) qualityOptions.add('2160p');
                if (_availableQualities.contains(1440)) qualityOptions.add('1440p');
                qualityOptions.addAll(['1080p', '720p', '480p', '360p']);
                for (final q in _availableQualities) {
                  final label = '${q}p';
                  if (!qualityOptions.contains(label)) {
                    qualityOptions.add(label);
                  }
                }

                final currentActiveRes = _activeQualityHeight > 0
                    ? '${_activeQualityHeight}p'
                    : (_availableQualities.isNotEmpty
                        ? '${_availableQualities.first}p'
                        : (_isDetectingQualities ? 'Detecting...' : 'Auto'));

                pageContent = Column(
                  key: const ValueKey('settings_quality'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Subpage Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          TvFocusable(
                            isCircle: true,
                            focusColor: cs.primary,
                            onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.main),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Quality for current video  ·  $currentActiveRes',
                              style: const TextStyle(
                                fontFamily: GoPlayType.family,
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    const SizedBox(height: 6),
                    if (_availableQualities.length <= 1 && _availableQualities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.white60, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Broadcast is single-resolution (${_availableQualities.first}p). Your preference will apply to multi-bitrate streams.',
                                  style: const TextStyle(
                                    fontFamily: GoPlayType.family,
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ...qualityOptions.map((opt) {
                      final bool isSelected = _currentQuality == opt || (opt == 'Auto' && _currentQuality == 'Auto');
                      final bool isChannelFixed = _availableQualities.length <= 1 && _availableQualities.isNotEmpty;
                      final bool isNotNativeInFixed = isChannelFixed && opt != 'Auto' && opt != '${_availableQualities.first}p';

                      return _buildSubpageOption(
                        title: opt == 'Auto' ? 'Auto (recommended)' : opt,
                        subtitle: isNotNativeInFixed
                            ? 'Preferred · Playing at source (${_availableQualities.first}p)'
                            : null,
                        isSelected: isSelected,
                        cs: cs,
                        onTap: () {
                          final height = opt == 'Auto' ? -1 : (int.tryParse(opt.replaceAll('p', '')) ?? -1);
                          _setQuality(opt, height);
                          setModalState(() {});
                          Future.delayed(const Duration(milliseconds: 160), dismiss);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                );
                break;

              case _SettingsSubpage.speed:
                pageContent = Column(
                  key: const ValueKey('settings_speed'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          TvFocusable(
                            isCircle: true,
                            focusColor: cs.primary,
                            onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.main),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Playback speed',
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    const SizedBox(height: 6),
                    if (isLiveNoDvr)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.white38, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Speed adjustment is not available during live broadcasts.',
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._speeds.map((s) {
                        final isSelected = _playbackSpeed == s;
                        final label = s == 1.0 ? '1x (Normal)' : '${s}x';
                        return _buildSubpageOption(
                          title: label,
                          isSelected: isSelected,
                          cs: cs,
                          onTap: () {
                            _setSpeed(s);
                            setModalState(() {});
                            Future.delayed(const Duration(milliseconds: 160), dismiss);
                          },
                        );
                      }),
                    const SizedBox(height: 8),
                  ],
                );
                break;

              case _SettingsSubpage.aspectRatio:
                pageContent = Column(
                  key: const ValueKey('settings_aspect'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          TvFocusable(
                            isCircle: true,
                            focusColor: cs.primary,
                            onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.main),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Aspect ratio',
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    const SizedBox(height: 6),
                    ...List.generate(_resizeModes.length, (idx) {
                      final isSelected = _aspectRatioIndex == idx;
                      final label = _aspectLabels[idx];
                      return _buildSubpageOption(
                        title: label,
                        isSelected: isSelected,
                        cs: cs,
                        onTap: () {
                          setState(() {
                            _aspectRatioIndex = idx;
                          });
                          final mode = _resizeModes[idx];
                          _methodChannel?.invokeMethod('setResizeMode', mode);
                          setModalState(() {});
                          Future.delayed(const Duration(milliseconds: 160), dismiss);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                );
                break;

              case _SettingsSubpage.servers:
                final servers = widget.servers ?? [];
                pageContent = Column(
                  key: const ValueKey('settings_servers'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          TvFocusable(
                            isCircle: true,
                            focusColor: cs.primary,
                            onTap: () => setModalState(() => currentSubpage = _SettingsSubpage.main),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Stream Source',
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x1AFFFFFF), height: 1),
                    const SizedBox(height: 6),
                    ...List.generate(servers.length, (idx) {
                      final isSelected = widget.activeServerIndex == idx;
                      final server = servers[idx];
                      final label = server.name.isNotEmpty ? server.name : 'Server ${idx + 1}';
                      return _buildSubpageOption(
                        title: label,
                        isSelected: isSelected,
                        cs: cs,
                        onTap: () {
                          widget.onServerSelected?.call(idx);
                          setModalState(() {});
                          Future.delayed(const Duration(milliseconds: 160), dismiss);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                );
                break;
            }

            return PopScope(
              canPop: currentSubpage == _SettingsSubpage.main,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                setModalState(() {
                  currentSubpage = _SettingsSubpage.main;
                });
              },
              child: Align(
                alignment: isWide ? Alignment.center : Alignment.bottomCenter,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: sheetWidth,
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    decoration: BoxDecoration(
                      color: const Color(0xFF212121), // YouTube dark grey
                      borderRadius: isWide
                          ? BorderRadius.circular(20)
                          : const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 28,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      left: !isWide,
                      right: !isWide,
                      bottom: true,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Drag Handle (Screenshot 1 & 2)
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 6),
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),

                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: pageContent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _settingsModalSetState = null;
      if (!mounted || !widget.isFullscreen) return;
      if (widget.playPauseFocusNode != null) {
        widget.playPauseFocusNode!.requestFocus();
      } else {
        final ctx = _playPauseKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Focus.of(ctx).requestFocus();
        }
      }
    });
  }

  Widget _buildSettingsMenuItem({
    required IconData icon,
    required String title,
    String? trailingValue,
    bool showChevron = true,
    required ColorScheme cs,
    required VoidCallback onTap,
    bool autoFocus = false,
  }) {
    return TvFocusable(
      onTap: onTap,
      autoFocus: autoFocus,
      focusColor: cs.primary,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: GoPlayType.family,
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingValue != null && trailingValue.isNotEmpty) ...[
              Text(
                trailingValue,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.45),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubpageOption({
    required String title,
    String? subtitle,
    required bool isSelected,
    required ColorScheme cs,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      onTap: onTap,
      autoFocus: isSelected,
      focusColor: cs.primary,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ─── Widget lifecycle ────────────────────────────────────────────

  late final FocusNode _focusNode;
  // GlobalKey used to find the play/pause TvFocusable's FocusNode so we can
  // explicitly request focus when controls are shown via remote.
  final GlobalKey _playPauseKey = GlobalKey();

  // Explicit FocusNodes for Row 3a (Seek Bar) and Row 3b (Bottom Buttons)
  // to ensure 100% deterministic D-Pad Up/Down navigation between all 4 control rows.
  final FocusNode _seekBarFocusNode = FocusNode(debugLabel: 'SeekBarFocusNode');
  final FocusNode _bottomControlsFocusNode = FocusNode(debugLabel: 'BottomControlsFocusNode');

  @override
  void initState() {
    super.initState();
    _isLocked = widget.isLocked;
    _loadGestureSettings();
    _keysChannel.setMethodCallHandler(_handleKeyMethodCall);
    _keysChannel.invokeMethod('setPlayerFullscreen', widget.isFullscreen);

    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        final saved = Hive.box(AppConstants.settingsBox).get('default_video_quality') as String?;
        if (saved != null && saved.isNotEmpty) {
          _currentQuality = saved;
        }
      }
    } catch (_) {}

    _focusNode = FocusNode(debugLabel: 'PlayerFocusNode');
    // NOTE: The play/pause TvFocusable button has autoFocus:true so it
    // grabs focus first within the player scope. The outer _focusNode then
    // acts as a passive event-bubbling catcher for media keys.

    // Inject AnalyticsService from ProviderScope when mounted inside app shell
    AnalyticsService? analytics;
    try {
      analytics = ProviderScope.containerOf(context, listen: false)
          .read(analyticsServiceProvider);
    } catch (_) {}

    // Initialize the deep playback engine (connectivity, persistent circuit breaker, keep-alive)
    _engine = PlaybackEngine(
      telemetry: PlaybackTelemetry(analytics: analytics),
    );
    _engine.setQualityLabel(_currentQuality);
    _engine.initializeConnectivity();

    _engine.onRetryRequested = _retryPlaybackInternal;
    _engine.onServerFailover = (nextIdx) => widget.onServerSelected?.call(nextIdx);
    _engine.onNextChannelRequested = () => widget.onNextChannel?.call();
    _engine.onPreviousChannelRequested = () => widget.onPreviousChannel?.call();
    _engine.onDowngradedToAuto = () {
      if (mounted) {
        setState(() => _currentQuality = 'Auto');
      }
    };

    _engine.addListener(_onEngineChanged);

    // Tell the engine about the initial channel and server list
    _engine.loadChannel(
      widget.channel,
      servers: widget.servers,
      activeServerIndex: widget.activeServerIndex,
    );
  }

  @override
  void didUpdateWidget(ChannelVideoPlayerNative oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFullscreen != widget.isFullscreen) {
      _keysChannel.invokeMethod('setPlayerFullscreen', widget.isFullscreen);
    }
    if (oldWidget.isLocked != widget.isLocked) {
      _isLocked = widget.isLocked;
    }
    if (oldWidget.servers != widget.servers ||
        oldWidget.activeServerIndex != widget.activeServerIndex) {
      _engine.updateServerScope(widget.servers, widget.activeServerIndex);
    }
    if (oldWidget.channel.id != widget.channel.id ||
        oldWidget.channel.streamUrl != widget.channel.streamUrl) {
      _engine.loadChannel(
        widget.channel,
        servers: widget.servers,
        activeServerIndex: widget.activeServerIndex,
      );

      _cachedParams = null;

      setState(() {
        _hasError = false;
        _errorMessage = null;
        _isBuffering = true;
        _position = Duration.zero;
        _duration = Duration.zero;
        _bufferedPosition = Duration.zero;
        _isDetectingQualities = true;
        _availableQualities = [];
      });

      _engine.nativePort.play(_getCreationParams());

      // In fullscreen, after a channel switch (e.g. from chip selection in the
      // top bar), autoFocus does NOT re-fire (it only fires on first insert).
      // Explicitly move focus back to play/pause so the user is not stuck on
      // the top-bar chip and can reach all center/bottom controls via D-Pad.
      if (widget.isFullscreen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = _playPauseKey.currentContext;
          if (ctx != null) {
            Focus.of(ctx).requestFocus();
          }
        });
      }
    }
  }

  Timer? _osdTimer;
  String? _osdText;
  IconData? _osdIcon;

  void _showOsd(String text, IconData icon) {
    _osdTimer?.cancel();
    if (mounted) {
      setState(() {
        _osdText = text;
        _osdIcon = icon;
      });
    }
    _osdTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _osdText = null;
          _osdIcon = null;
        });
      }
    });
  }

  void _seekRelative(int seconds, {bool wakeControls = true}) {
    if (_duration <= Duration.zero) return;
    final newPos = _position + Duration(seconds: seconds);
    final target = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    _seekTo(target);
    if (wakeControls) {
      if (!widget.showControls) {
        widget.onTap?.call();
      }
      widget.onInteract?.call();
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _methodChannel?.invokeMethod('pause');
    } else {
      _methodChannel?.invokeMethod('resume');
    }
    if (!widget.showControls) {
      widget.onTap?.call();
    }
    widget.onInteract?.call();
  }

  /// D-Pad key mapping on TV remote:
  ///
  ///  OK / Select / Enter / Space → Show controls if hidden, then activate
  ///                                  focused button or toggle play/pause.
  ///  Up / Down (non-fullscreen)   → Previous / next channel.
  ///  Up / Down (fullscreen)       → Ignored — Flutter traversal moves focus
  ///                                  between rows (top bar → center → bottom).
  ///  Left / Right                 → Ignored — Flutter traversal moves focus
  ///                                  between buttons in the same row.
  ///  Media keys                   → Play, pause, rewind, fast-forward.
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Any key press → ensure controls are visible and timer is refreshed.
    // This is the TV "wake up controls" behaviour.
    if (!widget.showControls) {
      widget.onTap?.call(); // toggles controls visible in parent
      // After showing controls, move focus to play/pause so the user can
      // immediately navigate with D-Pad without an extra key press.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.playPauseFocusNode != null) {
          widget.playPauseFocusNode!.requestFocus();
        } else {
          final ctx = _playPauseKey.currentContext;
          if (ctx != null) {
            Focus.of(ctx).requestFocus();
          }
        }
      });
      return KeyEventResult.handled;
    } else {
      widget.onInteract?.call(); // just resets the hide timer
    }

    // ── Play / Pause (fallback when no child button is focused) ──
    // TvFocusable buttons handle OK themselves; this covers the case where
    // the outer node has focus (e.g. error state, buffering).
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.accept ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      // Only act if the outer node (not a TvFocusable child) has primary focus
      if (_focusNode.hasPrimaryFocus) {
        _togglePlayPause();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // let TvFocusable child handle it
    }

    // ── Media rewind/fast-forward keys (dedicated remote buttons) ──
    // These are DISTINCT from D-Pad Left/Right and should always seek.
    if (key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaStepBackward) {
      _seekRelative(-10);
      _showOsd('-10s', Icons.replay_10_rounded);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaStepForward) {
      _seekRelative(10);
      _showOsd('+10s', Icons.forward_10_rounded);
      return KeyEventResult.handled;
    }

    // ── D-Pad Left / Right ──
    // Return `ignored` — Flutter's directional traversal policy will move
    // focus to the prev/next TvFocusable button automatically.
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }

    // ── Up / Down ──
    // Return `ignored` so Flutter's directional traversal can move focus
    // smoothly between all control buttons (Play/Pause, Fullscreen Toggle, etc.).
    // Dedicated physical channel +/- buttons on TV remotes handle channel switching.
    if (key == LogicalKeyboardKey.channelUp) {
      if (widget.onPreviousChannel != null) {
        widget.onPreviousChannel!();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.channelDown) {
      if (widget.onNextChannel != null) {
        widget.onNextChannel!();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _osdTimer?.cancel();
    _osdHideTimer?.cancel();
    _doubleTapResetTimer?.cancel();
    _brightnessOsdNotifier.dispose();
    _volumeOsdNotifier.dispose();
    _scrubPositionNotifier.dispose();
    _seekDeltaNotifier.dispose();
    _stopProgressTimer();
    _settingsModalSetState = null;
    _focusNode.dispose();
    _seekBarFocusNode.dispose();
    _bottomControlsFocusNode.dispose();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _gestureToastTimer?.cancel();
    _gestureToastNotifier.dispose();
    _keysChannel.invokeMethod('setPlayerFullscreen', false);
    _keysChannel.setMethodCallHandler(null);
    _methodChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorWidget();

    return Focus(
      focusNode: _focusNode,
      // autofocus: false — the play/pause TvFocusable inside has autoFocus:true.
      // This outer Focus only serves as an event-bubbling catcher for Up/Down
      // channel switching. It must NOT steal focus from the child buttons.
      autofocus: false,
      onKeyEvent: _handlePlayerKeyEvent,
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: Stack(
            children: [
              // Native ExoPlayer view — disabled from taking D-Pad focus
              Focus(
                canRequestFocus: false,
                child: AndroidView(
                  viewType: 'com.goplay/native_player',
                  creationParams: _getCreationParams(),
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onPlatformViewCreated,
                ),
              ),

              // ── Extra Brightness Filter Overlay (Fullscreen) ──
              if (widget.isFullscreen)
                ValueListenableBuilder<double?>(
                  valueListenable: _brightnessOsdNotifier,
                  builder: (context, value, child) {
                    if (!_extraBrightnessEnabled || _brightness <= 1.0) {
                      return const SizedBox.shrink();
                    }
                    final extraAlpha = ((_brightness - 1.0).clamp(0.0, 1.0) * 0.40);
                    return Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: extraAlpha),
                        ),
                      ),
                    );
                  },
                ),

              // Buffering indicator (isolated — when controls are hidden)
              if (_isBuffering && !widget.showControls)
                const Center(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),

              // Tap & gesture overlay to show/hide controls or double-tap / pan scrub when controls are hidden
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onDoubleTapDown: _handleDoubleTapDown,
                  onDoubleTap: () {},
                  onPanStart: _handlePanStart,
                  onPanUpdate: _handlePanUpdate,
                  onPanEnd: _handlePanEnd,
                  onPanCancel: _handlePanCancel,
                  child: const SizedBox.shrink(),
                ),
              ),

              // Controls UI layer
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !widget.showControls,
                  child: Listener(
                    onPointerDown: (_) {
                      widget.onInteract?.call();
                    },
                    child: AnimatedOpacity(
                      opacity: widget.showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _isLocked
                          ? _buildLockedControls()
                          : _buildUnlockedControls(),
                    ),
                  ),
                ),
              ),

              // ── 3-Zone Double Tap Seek Ripple Overlay (Left & Right) ──
              Positioned.fill(
                child: IgnorePointer(
                  child: _DoubleTapSeekOverlay(
                    showLeft: _showDoubleTapLeft,
                    showRight: _showDoubleTapRight,
                    seconds: _doubleTapSeekSeconds,
                  ),
                ),
              ),

              // ── Swipe Scrub HUD Overlay (Centered) ──
              Positioned.fill(
                child: IgnorePointer(
                  child: _SwipeScrubOsd(
                    scrubPositionNotifier: _scrubPositionNotifier,
                    seekDeltaNotifier: _seekDeltaNotifier,
                    duration: _duration,
                  ),
                ),
              ),

              // ── Brightness & Volume OSD (Fullscreen) ──
              if (widget.isFullscreen) ...[
                Positioned(
                  left: 36,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: _BrightnessOsd(notifier: _brightnessOsdNotifier),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 36,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: RepaintBoundary(
                      child: IgnorePointer(
                        child: _VolumeOsd(notifier: _volumeOsdNotifier),
                      ),
                    ),
                  ),
                ),
              ],

              // ── Gesture Hint Toast Pill ──
              ValueListenableBuilder<String?>(
                valueListenable: _gestureToastNotifier,
                builder: (context, msg, _) {
                  if (msg == null) return const SizedBox.shrink();
                  return Positioned(
                    bottom: widget.isFullscreen ? 80 : 36,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: RepaintBoundary(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                          child: Text(
                            msg,
                            style: const TextStyle(
                              fontFamily: GoPlayType.family,
                              color: Colors.white,
                              fontSize: GoPlayType.sm,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ── State machine status overlay ──
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.isFullscreen ? 80 : 56,
                child: Center(
                  child: _StateMachineOverlay(stateMachine: _engine.stateMachine),
                ),
              ),

              // ── Android TV Remote OSD Feedback ──
              Positioned.fill(
                child: IgnorePointer(
                  child: _TvPlayerOsd(
                    message: _osdText,
                    icon: _osdIcon,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Locked controls ─────────────────────────────────────────────

  Widget _buildLockedControls() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _isLocked = false;
            });
            widget.onLockChanged?.call(false);
            widget.onInteract?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xEE141418),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_open_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Tap to unlock',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Unlocked controls ───────────────────────────────────────────

  Widget _buildUnlockedControls() {
    return Stack(
      children: [
        // Dark gradient overlay — pre-cached decorations
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: () {},
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            onPanCancel: _handlePanCancel,
            child: DecoratedBox(
              decoration: widget.isFullscreen
                  ? _kGradientOverlayFS
                  : _kGradientOverlayPortrait,
            ),
          ),
        ),

        // Central Playback Controls — isolated from seek-bar repaints
        Center(
          child: RepaintBoundary(
            child: _CentralControls(
              isPlaying: _isPlaying,
              isBuffering: _isBuffering,
              playPauseKey: _playPauseKey,
              playPauseFocusNode: widget.playPauseFocusNode,
              onPlayPause: () {
                if (_isPlaying) {
                  _methodChannel?.invokeMethod('pause');
                } else {
                  _methodChannel?.invokeMethod('resume');
                }
              },
              onPrev: widget.onPreviousChannel,
              onNext: widget.onNextChannel,
              onRewind: () {
                final newPos = _position - const Duration(seconds: 10);
                _seekTo(newPos < Duration.zero ? Duration.zero : newPos);
              },
              onForward: () {
                final newPos = _position + const Duration(seconds: 10);
                _seekTo(newPos > _duration ? _duration : newPos);
              },
              isFullscreen: widget.isFullscreen,
              autoFocus: widget.isFullscreen,
              onFocusDown: () => _seekBarFocusNode.requestFocus(),
              onInteract: widget.onInteract,
            ),
          ),
        ),

        // Bottom Controls Bar — isolated from central controls repaints
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 0.80, 1.0],
                ),
              ),
              padding: EdgeInsets.only(
                top: widget.isFullscreen ? 22.0 : 8.0,
                bottom: widget.isFullscreen ? 10.0 : 8.0,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mq = MediaQuery.of(context);
                  final availableWidth = constraints.maxWidth;
                  final isCompact = availableWidth < 580;
                  final hPadding = isCompact ? 14.0 : 24.0;
                  final leftPadding = widget.isFullscreen ? math.max(hPadding, mq.padding.left) : hPadding;
                  final rightPadding = widget.isFullscreen ? math.max(hPadding, mq.padding.right) : hPadding;
                  final cs = Theme.of(context).colorScheme;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Seek Bar / Timeline — inset horizontally to align with bottom buttons & time row
                      Padding(
                        padding: EdgeInsets.only(left: leftPadding, right: rightPadding),
                        child: RepaintBoundary(
                          child: _FocusableSeekBar(
                            position: _position,
                            duration: _duration,
                            bufferedPosition: _bufferedPosition,
                            onSeek: _seekTo,
                            onScrubbingChanged: (scrubbing) {
                              setState(() {
                                _isScrubbing = scrubbing;
                              });
                            },
                            isFullscreen: widget.isFullscreen,
                            onSeekRelative: _seekRelative,
                            onInteract: widget.onInteract,
                            focusNode: _seekBarFocusNode,
                            onFocusDown: () => _bottomControlsFocusNode.requestFocus(),
                            onFocusUp: () {
                              if (widget.playPauseFocusNode != null) {
                                widget.playPauseFocusNode!.requestFocus();
                              } else {
                                final ctx = _playPauseKey.currentContext;
                                if (ctx != null) Focus.of(ctx).requestFocus();
                              }
                            },
                          ),
                        ),
                      ),

                      // Bottom Buttons row — tightened immediately under seek bar
                      Padding(
                        padding: EdgeInsets.only(
                          left: leftPadding,
                          right: rightPadding,
                          bottom: widget.isFullscreen ? 4.0 : 0.0,
                          top: 0.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Time text / Adaptive Live badge with Tabular Figures
                            if (_isLive && _duration == Duration.zero)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: cs.primary.withValues(alpha: 0.8),
                                          blurRadius: 8,
                                          spreadRadius: 1.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      fontFamily: GoPlayType.family,
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Flexible(
                                fit: FlexFit.loose,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        _formatDuration(_position),
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: Colors.white,
                                          fontSize: isCompact ? 12.5 : 14,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      Text(
                                        ' / ',
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: Colors.white.withValues(alpha: 0.45),
                                          fontSize: isCompact ? 11.5 : 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(_duration),
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: Colors.white.withValues(alpha: 0.70),
                                          fontSize: isCompact ? 12.5 : 14,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            if (widget.isFullscreen)
                              _buildFullscreenRightControls(availableWidth: availableWidth)
                            else
                              _buildPortraitRightControls(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenRightControls({required double availableWidth}) {
    final cs = Theme.of(context).colorScheme;
    final bool isCompact = availableWidth < 580;
    final double iconSize = isCompact ? 22.0 : 28.0;
    final double btnPadding = isCompact ? 5.0 : 7.0;
    final double btnSpacing = isCompact ? 4.0 : 6.0;
    // On narrow screens (< 360px), hide PiP to guarantee zero overflow
    final bool showPip = !isCompact || availableWidth >= 360;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            widget.isFullscreen) {
          widget.onInteract?.call();
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp) {
            _seekBarFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            // Prevent focus loss when pressing Down on the bottom-most row!
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Picture-in-Picture Button
          if (showPip) ...[
            TvFocusable(
              focusNode: _bottomControlsFocusNode,
              isCircle: true,
              focusColor: cs.primary,
              onTap: _enterPiP,
              child: Padding(
                padding: EdgeInsets.all(btnPadding),
                child: Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: iconSize),
              ),
            ),
            SizedBox(width: btnSpacing),
          ],

          // 2. Aspect Ratio Button
          TvFocusable(
            focusNode: showPip ? null : _bottomControlsFocusNode,
            isCircle: true,
            focusColor: cs.primary,
            onTap: _toggleAspectRatio,
            child: Padding(
              padding: EdgeInsets.all(btnPadding),
              child: Icon(Icons.fit_screen_rounded, color: Colors.white, size: iconSize),
            ),
          ),
          SizedBox(width: btnSpacing),

          // 2.5 Playback Settings Button (Quality, Speed)
          TvFocusable(
            isCircle: true,
            focusColor: cs.primary,
            onTap: _showPlayerSettingsModal,
            child: Padding(
              padding: EdgeInsets.all(btnPadding),
              child: Icon(Icons.settings_rounded, color: Colors.white, size: iconSize),
            ),
          ),
          SizedBox(width: btnSpacing),

          // 3. Volume Button
          TvFocusable(
            isCircle: true,
            focusColor: cs.primary,
            onTap: _toggleMute,
            child: Padding(
              padding: EdgeInsets.all(btnPadding),
              child: Icon(
                _isMuted || _volume == 0
                    ? Icons.volume_off_rounded
                    : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                color: Colors.white,
                size: iconSize,
              ),
            ),
          ),
          SizedBox(width: btnSpacing),

          // 4. Lock Button
          TvFocusable(
            isCircle: true,
            focusColor: cs.primary,
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() {
                _isLocked = true;
              });
              widget.onLockChanged?.call(true);
            },
            child: Padding(
              padding: EdgeInsets.all(btnPadding),
              child: Icon(Icons.lock_open_rounded, color: Colors.white, size: iconSize),
            ),
          ),
          SizedBox(width: btnSpacing),

          // 5. Settings / Server Selection Button (when channel has multiple servers)
          if (widget.servers != null && widget.servers!.length > 1) ...[
            TvFocusable(
              isCircle: true,
              focusColor: cs.primary,
              onTap: _showServerSelectionModal,
              child: Padding(
                padding: EdgeInsets.all(btnPadding),
                child: Icon(Icons.dns_rounded, color: Colors.white, size: iconSize),
              ),
            ),
            SizedBox(width: btnSpacing),
          ],

          // 6. Fullscreen Toggle Button
          if (widget.onFullscreenToggle != null)
            TvFocusable(
              isCircle: true,
              focusColor: cs.primary,
              onTap: widget.onFullscreenToggle,
              child: Padding(
                padding: EdgeInsets.all(btnPadding),
                child: Icon(
                  widget.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPortraitRightControls() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Picture-in-Picture Button
        TvFocusable(
          isCircle: true,
          focusColor: cs.primary,
          onTap: _enterPiP,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.picture_in_picture_alt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 6),

        // 2. Volume Button
        TvFocusable(
          isCircle: true,
          focusColor: cs.primary,
          onTap: _toggleMute,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              _isMuted || _volume == 0
                  ? Icons.volume_off_rounded
                  : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 6),

        // 2.5 Playback Settings Button (Quality, Speed)
        TvFocusable(
          isCircle: true,
          focusColor: cs.primary,
          onTap: _showPlayerSettingsModal,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.settings_rounded, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 6),

        // 3. Fullscreen Toggle Button
        if (widget.onFullscreenToggle != null)
          TvFocusable(
            isCircle: true,
            focusColor: cs.primary,
            onTap: widget.onFullscreenToggle,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                widget.isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
      ],
    );
  }

  void _showServerSelectionModal() {
    final servers = widget.servers;
    if (servers == null || servers.isEmpty) return;
    widget.onInteract?.call();

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final cs = Theme.of(dialogContext).colorScheme;
        final mq = MediaQuery.of(dialogContext);
        final bool isWide = mq.size.width >= 600;
        final double sheetWidth = isWide ? math.min(mq.size.width * 0.85, 480.0) : double.infinity;
        final double maxHeight = mq.size.height * 0.75;

        bool isDismissing = false;
        void dismiss() {
          if (!isDismissing && Navigator.of(dialogContext).canPop()) {
            isDismissing = true;
            _settingsModalSetState = null;
            Navigator.of(dialogContext).pop();
          }
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: sheetWidth,
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E22), // YouTube dark charcoal
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 28,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                left: !isWide,
                right: !isWide,
                bottom: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Drag Handle + Header gesture detector for swipe down
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        if ((details.primaryDelta ?? 0) > 6) {
                          dismiss();
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Drag Handle
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 12),
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),

                          // Minimal YouTube Title Header (no subtitle, no divider, no close button)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                            child: Text(
                              'Servers',
                              style: const TextStyle(
                                fontFamily: GoPlayType.family,
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Server list
                    Flexible(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is OverscrollNotification &&
                              notification.overscroll < -8) {
                            dismiss();
                            return true;
                          } else if (notification is ScrollUpdateNotification &&
                              notification.metrics.pixels <= 0 &&
                              (notification.scrollDelta ?? 0) < -8) {
                            dismiss();
                            return true;
                          }
                          return false;
                        },
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          itemCount: servers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 2),
                          itemBuilder: (context, index) {
                            final s = servers[index];
                            final isSelected = index == widget.activeServerIndex;
                            final displayName =
                                s.name.isNotEmpty ? s.name : 'Server ${index + 1}';

                            return TvFocusable(
                              borderRadius: BorderRadius.circular(12),
                              focusColor: cs.primary.withValues(alpha: 0.2),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                dismiss();
                                if (index != widget.activeServerIndex) {
                                  widget.onServerSelected?.call(index);
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 13,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.dns_rounded,
                                      color: isSelected ? cs.primary : Colors.white70,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: isSelected ? cs.primary : Colors.white,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_rounded,
                                        color: cs.primary,
                                        size: 22,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
      },
    );
  }

  // ─── Error widget (state-machine aware) ───────────────────────────

  Widget _buildErrorWidget() {
    final smState = _engine.state;
    final errorType = smState.error?.type;
    final isDrm = errorType == ErrorType.drmFailure || widget.channel.hasDrm;
    final isNoInternet = errorType == ErrorType.noInternet ||
        smState.phase == PlaybackPhase.waitingForInternet;
    final isGeoBlock = errorType == ErrorType.geoBlock;
    final hasNext = widget.onNextChannel != null;
    final hasPrev = widget.onPreviousChannel != null;

    // Choose icon based on error type
    IconData errorIcon;
    Color iconColor;
    String errorTitle;

    if (isNoInternet) {
      errorIcon = Icons.wifi_off_rounded;
      iconColor = Colors.orange;
      errorTitle = 'No Internet Connection';
    } else if (isDrm) {
      errorIcon = Icons.lock_outline;
      iconColor = Colors.orange;
      errorTitle = 'DRM Protected Content';
    } else if (isGeoBlock) {
      errorIcon = Icons.shield_outlined;
      iconColor = Colors.redAccent;
      errorTitle = 'Content Not Available';
    } else {
      errorIcon = Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
      iconColor = Colors.redAccent;
      errorTitle = 'Stream Unavailable';
    }

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(errorIcon, color: iconColor, size: 48),
              const SizedBox(height: 14),
              Text(
                errorTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: GoPlayType.family,
                  color: Colors.white,
                  fontSize: GoPlayType.md,
                  fontWeight: FontWeight.w700,
                  height: GoPlayType.leadingSnug,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.channel.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: GoPlayType.family,
                    color: Colors.white70,
                    fontSize: GoPlayType.sm,
                    fontWeight: FontWeight.w400,
                    height: GoPlayType.leadingSnug,
                  ),
                  // Channel names come from the remote catalogue.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage ?? 'Unable to play this stream',
                  style: const TextStyle(
                    fontFamily: GoPlayType.family,
                    color: Colors.white70,
                    fontSize: GoPlayType.sm,
                    height: GoPlayType.leadingBody,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20),
              // Action buttons row
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  // Retry button
                  _ErrorActionButton(
                    icon: Icons.refresh_rounded,
                    label: isNoInternet ? 'Check Connection' : 'Retry',
                    onTap: _retryPlayback,
                    isPrimary: true,
                  ),
                  // Next Channel button
                  if (hasNext)
                    _ErrorActionButton(
                      icon: Icons.skip_next_rounded,
                      label: 'Next Channel',
                      onTap: () {
                        widget.onNextChannel!();
                      },
                      isPrimary: false,
                    ),
                  // Previous Channel button (fallback if no next)
                  if (!hasNext && hasPrev)
                    _ErrorActionButton(
                      icon: Icons.skip_previous_rounded,
                      label: 'Prev Channel',
                      onTap: () {
                        widget.onPreviousChannel!();
                      },
                      isPrimary: false,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Error Action Button ─────────────────────────────────────────

class _ErrorActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ErrorActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: isPrimary ? Colors.white : Colors.white70,
        backgroundColor: isPrimary
            ? Colors.orange.shade800
            : Colors.white.withAlpha(25),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isPrimary
              ? BorderSide.none
              : const BorderSide(color: Colors.white24, width: 0.8),
        ),
      ),
    );
  }
}

// ─── State Machine Status Overlay ─────────────────────────────────

/// Shows contextual overlays based on the [PlaybackStateMachine] state:
/// - Retrying: "Retrying (2/3)..."
/// - Skipping: "Skipping in 5s... [Cancel] [Skip Now]"
/// - Waiting for Internet: "Waiting for internet..."
class _StateMachineOverlay extends StatelessWidget {
  final PlaybackStateMachine stateMachine;

  const _StateMachineOverlay({required this.stateMachine});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stateMachine,
      builder: (context, _) {
        final state = stateMachine.state;

        switch (state.phase) {
          case PlaybackPhase.retrying:
            return _StatusPill(
              icon: Icons.refresh_rounded,
              iconColor: Colors.orangeAccent,
              message: 'Retrying (${state.retryAttempt}/${state.maxRetries})…',
              showSpinner: true,
            );

          case PlaybackPhase.skipping:
            return _SkipCountdownPill(
              secondsRemaining: state.skipCountdown ?? 0,
              onCancel: () => stateMachine.cancelSkip(),
              onSkipNow: () => stateMachine.skipNow(),
            );

          case PlaybackPhase.waitingForInternet:
            return const _StatusPill(
              icon: Icons.wifi_off_rounded,
              iconColor: Colors.orange,
              message: 'Waiting for internet…',
              showSpinner: true,
            );

          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// Simple status pill with icon/spinner + message.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String message;
  final bool showSpinner;

  const _StatusPill({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                color: Colors.orangeAccent,
                strokeWidth: 1.5,
              ),
            )
          else
            Icon(icon, color: iconColor, size: 14),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: GoPlayType.sm,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Skip countdown pill with [Cancel] and [Skip Now] buttons.
class _SkipCountdownPill extends StatelessWidget {
  final int secondsRemaining;
  final VoidCallback onCancel;
  final VoidCallback onSkipNow;

  const _SkipCountdownPill({
    required this.secondsRemaining,
    required this.onCancel,
    required this.onSkipNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(210),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withAlpha(100), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              color: Colors.orangeAccent,
              strokeWidth: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Skipping in ${secondsRemaining}s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: GoPlayType.sm,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white38, width: 0.8),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: GoPlayType.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSkipNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade800,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Skip Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: GoPlayType.xs,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ─── Central Playback Controls ────────────────────────────────────

/// Extracted central playback controls (prev, rewind, play/pause, forward, next)
class _CentralControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final bool isFullscreen;
  /// When true, the play/pause button requests autofocus so it's the first
  /// button reachable by D-Pad when the player opens.
  final bool autoFocus;
  /// Key placed on the play/pause TvFocusable so its FocusNode can be looked
  /// up from the parent state to auto-focus when controls appear.
  final GlobalKey? playPauseKey;
  final FocusNode? playPauseFocusNode;
  final VoidCallback? onFocusDown;
  final VoidCallback? onInteract;

  const _CentralControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onRewind,
    required this.onForward,
    required this.isFullscreen,
    this.autoFocus = false,
    this.playPauseKey,
    this.playPauseFocusNode,
    this.onFocusDown,
    this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final double iconSize = isFullscreen ? 34 : 24;
    final double playSize = isFullscreen ? 60 : 44;
    final double buttonSize = isFullscreen ? 48 : 36;
    final double spacing = isFullscreen ? 20 : 12;

    final hasPrev = onPrev != null;
    final hasNext = onNext != null;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. Previous Channel Button
        TvFocusable(
          isCircle: true,
          onTap: onPrev,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              Icons.skip_previous_rounded,
              color: hasPrev ? Colors.white : Colors.white38,
              size: iconSize,
            ),
          ),
        ),
        SizedBox(width: spacing),

        // 2. Rewind 10s Button
        TvFocusable(
          isCircle: true,
          onTap: onRewind,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              Icons.replay_10_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
        SizedBox(width: spacing),

        // 3. Play / Pause Button — autofocus so D-Pad starts here
        TvFocusable(
          key: playPauseKey,
          focusNode: playPauseFocusNode,
          isCircle: true,
          autoFocus: autoFocus,
          onTap: onPlayPause,
          child: Container(
            width: playSize,
            height: playSize,
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isBuffering
                  ? SizedBox(
                      width: playSize * 0.5,
                      height: playSize * 0.5,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: isFullscreen ? 2.5 : 2.0,
                      ),
                    )
                  : Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: playSize * 0.75,
                    ),
            ),
          ),
        ),
        SizedBox(width: spacing),

        // 4. Forward 10s Button
        TvFocusable(
          isCircle: true,
          onTap: onForward,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              Icons.forward_10_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
        SizedBox(width: spacing),

        // 5. Next Channel Button
        TvFocusable(
          isCircle: true,
          onTap: onNext,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(
              Icons.skip_next_rounded,
              color: hasNext ? Colors.white : Colors.white38,
              size: iconSize,
            ),
          ),
        ),
      ],
    );

    if (onFocusDown == null) return row;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          onInteract?.call();
          if (event.logicalKey == LogicalKeyboardKey.arrowDown && isFullscreen) {
            onFocusDown?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
  }
}

// ─── Focusable Seek Bar ──────────────────────────────────────────

/// TV-focusable wrapper around [PlayerProgressBar].
/// When focused, D-Pad Left seeks -10s and D-Pad Right seeks +10s.
class _FocusableSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrubbingChanged;
  final bool isFullscreen;
  final void Function(int seconds) onSeekRelative;
  final VoidCallback? onInteract;
  final FocusNode? focusNode;
  final VoidCallback? onFocusDown;
  final VoidCallback? onFocusUp;

  const _FocusableSeekBar({
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.onSeek,
    this.onScrubbingChanged,
    required this.isFullscreen,
    required this.onSeekRelative,
    this.onInteract,
    this.focusNode,
    this.onFocusDown,
    this.onFocusUp,
  });

  @override
  State<_FocusableSeekBar> createState() => _FocusableSeekBarState();
}

class _FocusableSeekBarState extends State<_FocusableSeekBar> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Focused label
        if (_isFocused && widget.isFullscreen)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.keyboard_arrow_left, color: Colors.white54, size: 14),
                SizedBox(width: 2),
                Text(
                  '← Seek →',
                  style: TextStyle(color: Colors.white70, fontSize: GoPlayType.xs, letterSpacing: GoPlayType.trackingMeta),
                ),
                SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_right, color: Colors.white54, size: 14),
              ],
            ),
          ),
        TvFocusable(
          focusNode: widget.focusNode,
          borderRadius: BorderRadius.circular(4),
          onFocusChange: (focused) {
            setState(() {
              _isFocused = focused;
            });
          },
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowLeft) {
              widget.onSeekRelative(-10);
              widget.onInteract?.call();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight) {
              widget.onSeekRelative(10);
              widget.onInteract?.call();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown && widget.isFullscreen) {
              widget.onFocusDown?.call();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowUp && widget.isFullscreen) {
              widget.onFocusUp?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          onTap: () {},
          child: PlayerProgressBar(
            position: widget.position,
            duration: widget.duration,
            bufferedPosition: widget.bufferedPosition,
            onSeek: widget.onSeek,
            onScrubbingChanged: widget.onScrubbingChanged,
            isFullscreen: widget.isFullscreen,
          ),
        ),
      ],
    );
  }
}

// ─── Progress Bar ─────────────────────────────────────────────────

/// Custom Seek Bar ProgressBar with Buffer Indicator, 44px Touch Target & Floating Time Pill
class PlayerProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrubbingChanged;
  final bool isFullscreen;

  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.onSeek,
    this.onScrubbingChanged,
    required this.isFullscreen,
  });

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  double get _currentProgress {
    if (_isDragging) return _dragProgress;
    if (widget.duration <= Duration.zero) return 0.0;
    return (widget.position.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get _currentScrubDuration {
    if (widget.duration <= Duration.zero) return Duration.zero;
    final ms = (widget.duration.inMilliseconds * _currentProgress).round();
    return Duration(milliseconds: ms);
  }

  void _onDragStart(BuildContext context, double localX) {
    if (widget.duration <= Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;

    final pct = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _isDragging = true;
      _dragProgress = pct;
    });
    widget.onScrubbingChanged?.call(true);
  }

  void _onDragUpdate(BuildContext context, double localX) {
    if (!_isDragging || widget.duration <= Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;

    final pct = (localX / width).clamp(0.0, 1.0);
    setState(() {
      _dragProgress = pct;
    });
  }

  void _onDragEnd() {
    if (!_isDragging) return;
    final target = _currentScrubDuration;
    setState(() {
      _isDragging = false;
    });
    widget.onSeek(target);
    widget.onScrubbingChanged?.call(false);
  }

  void _onDragCancel() {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
    });
    widget.onScrubbingChanged?.call(false);
  }

  void _onTapDown(BuildContext context, double localX) {
    if (widget.duration <= Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;

    final pct = (localX / width).clamp(0.0, 1.0);
    final targetMs = (widget.duration.inMilliseconds * pct).round();
    widget.onSeek(Duration(milliseconds: targetMs));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration <= Duration.zero) {
      return const SizedBox(height: 12);
    }

    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final thumbX = totalWidth * _currentProgress;
        final pillLeft = (thumbX - 35).clamp(0.0, totalWidth > 70 ? totalWidth - 70 : 0.0);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 44px comfortable touch target
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) => _onDragStart(context, details.localPosition.dx),
              onHorizontalDragUpdate: (details) => _onDragUpdate(context, details.localPosition.dx),
              onHorizontalDragEnd: (_) => _onDragEnd(),
              onHorizontalDragCancel: () => _onDragCancel(),
              onTapDown: (details) => _onTapDown(context, details.localPosition.dx),
              child: SizedBox(
                height: widget.isFullscreen ? 28.0 : 20.0,
                width: double.infinity,
                child: Center(
                  child: CustomPaint(
                    size: Size(totalWidth, _isDragging ? 5.0 : 3.0),
                    painter: _ProgressBarPainter(
                      progress: _currentProgress,
                      bufferedProgress: widget.duration.inMilliseconds > 0
                          ? (widget.bufferedPosition.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0,
                      isDragging: _isDragging,
                      activeColor: cs.primary,
                    ),
                  ),
                ),
              ),
            ),

            // Floating Time Pill hovering above finger when dragging
            if (_isDragging)
              Positioned(
                left: pillLeft,
                top: -24,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xE6141418),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.6),
                        width: 1.0,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Text(
                      _formatDuration(_currentScrubDuration),
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        color: cs.primary,
                        fontSize: GoPlayType.xs,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final double bufferedProgress;
  final bool isDragging;
  final Color activeColor;

  final Paint _paintBg;
  final Paint _paintBuf;
  final Paint _paintAct;
  final Paint _paintThumb;
  final Paint _paintThumbGlow;

  _ProgressBarPainter({
    required this.progress,
    required this.bufferedProgress,
    required this.isDragging,
    required this.activeColor,
  })  : _paintBg = Paint()..color = Colors.white.withValues(alpha: 0.18),
        _paintBuf = Paint()..color = Colors.white.withValues(alpha: 0.38),
        _paintAct = Paint()..color = activeColor,
        _paintThumb = Paint()..color = activeColor,
        _paintThumbGlow = Paint()
          ..color = activeColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final h = size.height;
    final r = Radius.circular(h / 2);

    // Background track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, y - h / 2, size.width, h), r),
      _paintBg,
    );

    // Buffered track
    if (bufferedProgress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - h / 2, size.width * bufferedProgress, h),
          r,
        ),
        _paintBuf,
      );
    }

    // Active track
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - h / 2, size.width * progress, h),
          r,
        ),
        _paintAct,
      );
    }

    // Thumb handle
    final thumbX = size.width * progress;
    if (isDragging) {
      // Glow ring
      canvas.drawCircle(Offset(thumbX, y), 12.0, _paintThumbGlow);
      // Main Thumb
      canvas.drawCircle(Offset(thumbX, y), 7.5, _paintThumb);
      // Inner dot
      canvas.drawCircle(Offset(thumbX, y), 2.5, Paint()..color = Colors.black);
    } else {
      canvas.drawCircle(Offset(thumbX, y), 5.0, _paintThumb);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter old) {
    return old.progress != progress ||
        old.bufferedProgress != bufferedProgress ||
        old.isDragging != isDragging;
  }
}

class _TvPlayerOsd extends StatelessWidget {
  final String? message;
  final IconData? icon;

  const _TvPlayerOsd({this.message, this.icon});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.primary.withValues(alpha: 0.6), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.3),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, color: cs.primary, size: 24),
            if (icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(
                message!,
                style: const TextStyle(
                  fontFamily: GoPlayType.family,
                  color: Colors.white,
                  fontSize: GoPlayType.md,
                  fontWeight: FontWeight.w700,
                  height: GoPlayType.leadingSnug,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoubleTapSeekOverlay extends StatelessWidget {
  final bool showLeft;
  final bool showRight;
  final int seconds;

  const _DoubleTapSeekOverlay({
    required this.showLeft,
    required this.showRight,
    required this.seconds,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLeft && !showRight) return const SizedBox.shrink();

    final isLeft = showLeft;
    final width = MediaQuery.of(context).size.width;
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: width * 0.35,
        height: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.horizontal(
            right: isLeft ? const Radius.elliptical(80, 220) : Radius.zero,
            left: !isLeft ? const Radius.elliptical(80, 220) : Radius.zero,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLeft ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
                color: cs.primary,
                size: 38,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 8,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${seconds.abs()}s',
                style: const TextStyle(
                  fontFamily: GoPlayType.family,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: GoPlayType.base,
                  shadows: [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeScrubOsd extends StatelessWidget {
  final ValueNotifier<Duration?> scrubPositionNotifier;
  final ValueNotifier<Duration?> seekDeltaNotifier;
  final Duration duration;

  const _SwipeScrubOsd({
    required this.scrubPositionNotifier,
    required this.seekDeltaNotifier,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Duration?>(
      valueListenable: scrubPositionNotifier,
      builder: (context, scrubPos, _) {
        if (scrubPos == null) return const SizedBox.shrink();

        return ValueListenableBuilder<Duration?>(
          valueListenable: seekDeltaNotifier,
          builder: (context, delta, _) {
            final deltaDuration = delta ?? Duration.zero;
            final isNeg = deltaDuration.isNegative;
            final progress = duration.inMilliseconds > 0
                ? (scrubPos.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xE6141418),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNeg ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
                          color: cs.primary,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${isNeg ? '-' : '+'}${_formatDuration(deltaDuration.abs())}',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            color: cs.primary,
                            fontSize: GoPlayType.lg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatDuration(scrubPos)} / ${_formatDuration(duration)}',
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        color: Colors.white,
                        fontSize: GoPlayType.sm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 160,
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(
                          children: [
                            Container(color: Colors.white24),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(color: cs.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _BrightnessOsd extends StatelessWidget {
  final ValueNotifier<double?> notifier;

  const _BrightnessOsd({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: notifier,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        final isBoosted = value > 1.0;
        const boostColor = Color(0xFFFFA726);

        IconData sunIcon;
        if (value < 0.3) {
          sunIcon = Icons.brightness_3_rounded;
        } else if (value < 0.6) {
          sunIcon = Icons.wb_sunny_outlined;
        } else {
          sunIcon = Icons.wb_sunny_rounded;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sunIcon,
              color: isBoosted ? boostColor : Colors.white,
              size: 26,
              shadows: [
                Shadow(
                  color: isBoosted ? const Color(0xAAFFA726) : Colors.black87,
                  blurRadius: isBoosted ? 10 : 6,
                ),
                const Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 5,
              height: 120,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 3),
                      ],
                    ),
                  ),
                  FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                  if (isBoosted)
                    FractionallySizedBox(
                      heightFactor: (value - 1.0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: boostColor,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: const [
                            BoxShadow(color: Color(0xAAFFA726), blurRadius: 8, spreadRadius: 1),
                            BoxShadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeOsd extends StatelessWidget {
  final ValueNotifier<double?> notifier;

  const _VolumeOsd({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: notifier,
      builder: (context, value, _) {
        if (value == null) return const SizedBox.shrink();
        final isBoosted = value > 1.0;
        const boostColor = Color(0xFFFFA726);

        IconData volIcon;
        if (value <= 0.001) {
          volIcon = Icons.volume_off_rounded;
        } else if (value < 0.5) {
          volIcon = Icons.volume_down_rounded;
        } else {
          volIcon = Icons.volume_up_rounded;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              volIcon,
              color: isBoosted ? boostColor : Colors.white,
              size: 26,
              shadows: [
                Shadow(
                  color: isBoosted ? const Color(0xAAFFA726) : Colors.black87,
                  blurRadius: isBoosted ? 10 : 6,
                ),
                const Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 5,
              height: 120,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 3),
                      ],
                    ),
                  ),
                  FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                  if (isBoosted)
                    FractionallySizedBox(
                      heightFactor: (value - 1.0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: boostColor,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: const [
                            BoxShadow(color: Color(0xAAFFA726), blurRadius: 8, spreadRadius: 1),
                            BoxShadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
