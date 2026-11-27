import 'package:flutter/foundation.dart';
import '../analytics_service.dart';
import 'playback_state.dart';

/// Forwards structured playback telemetry (startup latency, errors, retries,
/// auto-failover, skips) directly into an injected [AnalyticsService].
class PlaybackTelemetry {
  final AnalyticsService? _analytics;

  PlaybackTelemetry({AnalyticsService? analytics}) : _analytics = analytics;

  /// Record a successful stream startup.
  void recordStartup({
    required String channelId,
    required String channelName,
    required int startupTimeMs,
  }) {
    debugPrint('Telemetry: STARTUP channel=$channelName time=${startupTimeMs}ms');
    _analytics?.trackPlaybackStartup(
      channelId: channelId,
      channelName: channelName,
      startupTimeMs: startupTimeMs,
    );
  }

  /// Record a playback error and forward to analytics.
  void recordError({
    required String channelId,
    required String channelName,
    required ErrorType errorType,
    required String rawMessage,
  }) {
    debugPrint('Telemetry: ERROR channel=$channelName type=$errorType msg=$rawMessage');
    _analytics?.trackPlaybackError(
      channelId: channelId,
      channelName: channelName,
      errorType: errorType.name,
      errorMessage: rawMessage,
    );
  }

  /// Record an automatic multi-server failover initiated by [PlaybackEngine].
  void recordAutoFailover({
    required String channelId,
    required String channelName,
    required int serverIndex,
    required String serverName,
  }) {
    debugPrint('Telemetry: AUTO_FAILOVER channel=$channelName -> server=$serverName ($serverIndex)');
    _analytics?.trackServerSwitch(
      channelId: channelId,
      channelName: channelName,
      serverIndex: serverIndex,
      serverName: serverName,
      isAutoFailover: true,
    );
  }

  /// Record a retry attempt.
  void recordRetry({
    required String channelId,
    required String channelName,
    required int attempt,
    required int maxAttempts,
  }) {
    debugPrint('Telemetry: RETRY channel=$channelName attempt=$attempt/$maxAttempts');
  }

  /// Record a channel skip.
  void recordSkip({
    required String channelId,
    required String channelName,
    required String skipToChannelId,
  }) {
    debugPrint('Telemetry: SKIP from=$channelName to=$skipToChannelId');
  }

  /// Record a buffer event (rebuffering during playback).
  void recordBufferEvent({
    required String channelId,
    required String channelName,
  }) {
    debugPrint('Telemetry: BUFFER channel=$channelName');
  }

  void dispose() {}
}
