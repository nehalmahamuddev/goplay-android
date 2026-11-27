import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/channel.dart';
import '../local_proxy.dart';
import 'circuit_breaker.dart';
import 'connectivity_service.dart';
import 'playback_state.dart';
import 'playback_state_machine.dart';
import 'playback_telemetry.dart';

/// Shared process-wide circuit breaker so channel outage memory persists
/// across individual player sessions.
final CircuitBreaker sharedPlaybackCircuitBreaker = CircuitBreaker();

/// Seam abstracting native video player commands (`MethodChannel` in production,
/// fake in tests).
abstract class NativePlayerPort {
  Future<void> play(Map<String, dynamic> params);
  Future<void> setQuality(int height);
  Future<void> seekTo(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> setResizeMode(int mode);
  Future<Map<dynamic, dynamic>?> getState();
  Future<bool?> toggleSubtitles();
  void setSpeed(double speed);
  void pause();
  void resume();
  void setChannel(MethodChannel? channel);
}

/// Production adapter wrapping ExoPlayer's `MethodChannel`.
class MethodChannelNativePlayerPort implements NativePlayerPort {
  MethodChannel? _channel;

  MethodChannelNativePlayerPort([this._channel]);

  @override
  void setChannel(MethodChannel? channel) {
    _channel = channel;
  }

  @override
  Future<void> play(Map<String, dynamic> params) async {
    await _channel?.invokeMethod('play', params);
  }

  @override
  Future<void> setQuality(int height) async {
    await _channel?.invokeMethod('setQuality', height);
  }

  @override
  Future<void> seekTo(int positionMs) async {
    await _channel?.invokeMethod('seekTo', positionMs);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _channel?.invokeMethod('setVolume', volume);
  }

  @override
  Future<void> setResizeMode(int mode) async {
    await _channel?.invokeMethod('setResizeMode', mode);
  }

  @override
  Future<Map<dynamic, dynamic>?> getState() async {
    return _channel?.invokeMethod<Map>('getState');
  }

  @override
  Future<bool?> toggleSubtitles() async {
    return _channel?.invokeMethod<bool>('toggleSubtitles');
  }

  @override
  void setSpeed(double speed) {
    _channel?.invokeMethod('setSpeed', speed);
  }

  @override
  void pause() {
    _channel?.invokeMethod('pause');
  }

  @override
  void resume() {
    _channel?.invokeMethod('resume');
  }
}

/// Seam isolating CDN auth keep-alive side effects (`otte.cache.aiv-cdn.net`).
abstract class StreamKeepAlive {
  void syncForUrl(String streamUrl);
  void stop();
}

/// Production keep-alive adapter delegating to [LocalProxy].
class LocalProxyKeepAlive implements StreamKeepAlive {
  bool _active = false;

  @override
  void syncForUrl(String streamUrl) {
    final needsKeepAlive = streamUrl.contains('otte.cache.aiv-cdn.net');
    if (needsKeepAlive && !_active) {
      _active = true;
      LocalProxy.startKkx4Auth();
    } else if (!needsKeepAlive && _active) {
      stop();
    }
  }

  @override
  void stop() {
    if (!_active) return;
    _active = false;
    LocalProxy.stopKkx4Auth();
  }
}

/// Deep playback orchestrator owning recovery, single non-wrapping server failover,
/// stall-to-Auto downgrade, and CDN auth keep-alive behind narrow seams.
class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({
    ConnectivityService? connectivityService,
    CircuitBreaker? circuitBreaker,
    PlaybackTelemetry? telemetry,
    NativePlayerPort? nativePort,
    StreamKeepAlive? keepAlive,
    DateTime Function()? now,
  })  : _connectivityService = connectivityService ?? ConnectivityService(),
        _circuitBreaker = circuitBreaker ?? sharedPlaybackCircuitBreaker,
        _telemetry = telemetry ?? PlaybackTelemetry(),
        _nativePort = nativePort ?? MethodChannelNativePlayerPort(),
        _keepAlive = keepAlive ?? LocalProxyKeepAlive(),
        _now = now ?? DateTime.now {
    _stateMachine = PlaybackStateMachine(
      connectivityService: _connectivityService,
      circuitBreaker: _circuitBreaker,
      telemetry: _telemetry,
    );

    _stateMachine.onRetryPlayback = () => onRetryRequested?.call();
    _stateMachine.onSwitchChannel = (_) => _skipToAdjacentChannel();
    _stateMachine.onSkipRequest = _handleFailoverOrSkip;
    _stateMachine.addListener(notifyListeners);
  }

  final ConnectivityService _connectivityService;
  final CircuitBreaker _circuitBreaker;
  final PlaybackTelemetry _telemetry;
  final NativePlayerPort _nativePort;
  final StreamKeepAlive _keepAlive;
  final DateTime Function() _now;
  late final PlaybackStateMachine _stateMachine;

  List<Channel> _servers = const <Channel>[];
  int _activeServerIndex = 0;
  String _currentQuality = 'Auto';

  // Unified stall-downgrade tracking (absorbed out of widget state)
  bool _hasPlayedInitially = false;
  bool _isBuffering = false;
  int _consecutiveStalls = 0;
  DateTime? _lastStallTime;
  Timer? _stallTimer;

  // Engine -> Host callbacks
  VoidCallback? onRetryRequested;
  ValueChanged<int>? onServerFailover;
  VoidCallback? onNextChannelRequested;
  VoidCallback? onPreviousChannelRequested;
  VoidCallback? onDowngradedToAuto;

  PlaybackStateMachine get stateMachine => _stateMachine;
  PlaybackState get state => _stateMachine.state;
  NativePlayerPort get nativePort => _nativePort;
  StreamKeepAlive get keepAlive => _keepAlive;
  String get currentQuality => _currentQuality;
  int get consecutiveStalls => _consecutiveStalls;

  Future<void> initializeConnectivity() => _connectivityService.initialize();

  void updateServerScope(List<Channel>? servers, int activeServerIndex) {
    _servers = servers ?? const <Channel>[];
    _activeServerIndex = activeServerIndex;
  }

  void setQualityLabel(String label) {
    _currentQuality = label;
    _consecutiveStalls = 0;
    if (label == 'Auto') {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
  }

  void loadChannel(
    Channel channel, {
    List<Channel>? servers,
    int activeServerIndex = 0,
  }) {
    if (servers != null) {
      _servers = servers;
    }
    _activeServerIndex = activeServerIndex;
    _hasPlayedInitially = false;
    _isBuffering = true;
    _consecutiveStalls = 0;
    _lastStallTime = null;
    _stallTimer?.cancel();
    _stallTimer = null;

    _keepAlive.syncForUrl(channel.streamUrl);
    _stateMachine.playChannel(channel);
  }

  void handleNativeStateEvent(Map<String, dynamic> args) {
    final stateStr = args['state'] as String? ?? '';
    final nowBuffering = stateStr == 'buffering';
    final isReady = stateStr == 'ready' || stateStr == 'playing';

    _stateMachine.handleNativeStateEvent(args);

    final wasBuffering = _isBuffering;
    _isBuffering = nowBuffering;
    if (isReady) {
      _hasPlayedInitially = true;
    }

    // Quality stall detection (when locked to manual quality, downgrade to Auto on stalls)
    if (!wasBuffering &&
        nowBuffering &&
        _hasPlayedInitially &&
        _currentQuality != 'Auto') {
      final currentNow = _now();
      if (_lastStallTime != null &&
          currentNow.difference(_lastStallTime!).inSeconds <= 30) {
        _consecutiveStalls++;
      } else {
        _consecutiveStalls = 1;
      }
      _lastStallTime = currentNow;

      _stallTimer?.cancel();
      _stallTimer = Timer(const Duration(seconds: 10), () {
        if (_isBuffering && _hasPlayedInitially && _currentQuality != 'Auto') {
          _triggerStallDowngrade();
        }
      });

      if (_consecutiveStalls >= 3) {
        _triggerStallDowngrade();
      }
    } else if (!nowBuffering) {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
  }

  void handleNativeError(Map<String, dynamic> args) {
    _stateMachine.handleError(args);
  }

  void manualRetry() => _stateMachine.manualRetry();
  void cancelSkip() => _stateMachine.cancelSkip();
  void skipNow() => _stateMachine.skipNow();

  void _triggerStallDowngrade() {
    if (_currentQuality == 'Auto') return;
    _consecutiveStalls = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    _currentQuality = 'Auto';
    _nativePort.setQuality(-1);
    onDowngradedToAuto?.call();
  }

  /// Single deterministic failover: tries remaining servers once without wrapping back to 0,
  /// then advances to next/previous channel or forces terminal failure.
  void _handleFailoverOrSkip() {
    if (_servers.length > 1 && _activeServerIndex < _servers.length - 1) {
      final nextIdx = _activeServerIndex + 1;
      final nextName = _servers[nextIdx].name.isNotEmpty
          ? _servers[nextIdx].name
          : 'Server ${nextIdx + 1}';
      debugPrint(
          'PlaybackEngine: error on server $_activeServerIndex, failing over to $nextIdx ($nextName)');
      _activeServerIndex = nextIdx;
      _telemetry.recordAutoFailover(
        channelId: _stateMachine.currentChannel?.id ?? '',
        channelName: _stateMachine.currentChannel?.name ?? '',
        serverIndex: nextIdx,
        serverName: nextName,
      );
      onServerFailover?.call(nextIdx);
      return;
    }

    _skipToAdjacentChannel();
  }

  void _skipToAdjacentChannel() {
    if (onNextChannelRequested != null) {
      debugPrint('PlaybackEngine: skipping to next channel');
      onNextChannelRequested!();
    } else if (onPreviousChannelRequested != null) {
      debugPrint('PlaybackEngine: skipping to previous channel');
      onPreviousChannelRequested!();
    } else {
      debugPrint('PlaybackEngine: all servers exhausted and no adjacent channels — failing');
      _stateMachine.forceFail(const ClassifiedError(
        type: ErrorType.unknown,
        strategy: RecoveryStrategy.showError,
        rawMessage: 'Stream failed across all available servers.',
        isRecoverable: false,
      ));
    }
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _keepAlive.stop();
    _stateMachine.removeListener(notifyListeners);
    _stateMachine.dispose();
    _connectivityService.dispose();
    super.dispose();
  }
}
