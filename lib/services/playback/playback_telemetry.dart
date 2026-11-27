import 'package:flutter/foundation.dart';
import '../analytics_service.dart';
import 'playback_state.dart';

/// Records structured playback events for analytics.
class PlaybackTelemetry {
  PlaybackTelemetry();

  /// Record a successful startup.
  void recordStartup({
    required String channelId,
    required String channelName,
    required int startupTimeMs,
  }) {
    debugPrint('Telemetry: STARTUP channel=$channelName '
        'time=${startupTimeMs}ms');
  }

  /// Record a playback error and forward to Firebase Analytics.
  void recordError({
    required String channelId,
    required String channelName,
    required ErrorType errorType,
    required String rawMessage,
  }) {
    debugPrint('Telemetry: ERROR channel=$channelName '
        'type=$errorType msg=$rawMessage');
    AnalyticsService.activeInstance?.trackPlaybackError(
      channelId: channelId,
      channelName: channelName,
      errorType: errorType.name,
      errorMessage: rawMessage,
    );
  }

  /// Record a retry attempt.
  void recordRetry({
    required String channelId,
    required String channelName,
    required int attempt,
    required int maxAttempts,
  }) {
    debugPrint('Telemetry: RETRY channel=$channelName '
        'attempt=$attempt/$maxAttempts');
  }

  /// Record a channel skip.
  void recordSkip({
    required String channelId,
    required String channelName,
    required String skipToChannelId,
  }) {
    debugPrint('Telemetry: SKIP from=$channelName '
        'to=$skipToChannelId');
  }

  /// Record a buffer event (rebuffering during playback).
  void recordBufferEvent({
    required String channelId,
    required String channelName,
  }) {
    debugPrint('Telemetry: BUFFER channel=$channelName');
  }

  void dispose() {
    // Future: flush any pending events
  }
}
