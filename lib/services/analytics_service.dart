import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'telemetry_transport.dart';

/// Deep telemetry tracker managing user presence heartbeats, watch durations,
/// 4s verified trending triggers, and screen/playback analytics behind
/// [TelemetryTransport] and [DeviceIdentityAdapter] seams.
class AnalyticsService with WidgetsBindingObserver {
  final TelemetryTransport _transport;
  final DeviceIdentityAdapter _deviceIdentity;
  final DateTime Function() _now;
  final Duration _presenceInterval;
  final Duration _watchHeartbeatInterval;
  final Duration _playbackVerificationDelay;

  String? _deviceId;
  String? _deviceName;
  String? _osVersion;
  String? _appVersion;
  bool _isTvDevice = false;

  String _status = 'online'; // 'online', 'watching', 'offline'
  String _currentPage = 'splash';
  String? _currentChannelId;
  String? _currentChannelName;
  String? _currentCategoryName;
  String? _currentEventId;
  String? _currentEventName;
  String? _currentEventSport;
  DateTime? _watchStartedAt;

  Timer? _heartbeatTimer;
  Timer? _watchHeartbeatTimer;
  Timer? _playbackVerificationTimer;
  bool _isInitialized = false;

  AnalyticsService({
    TelemetryTransport? transport,
    DeviceIdentityAdapter? deviceIdentity,
    DateTime Function()? now,
    Duration presenceInterval = const Duration(seconds: 120),
    Duration watchHeartbeatInterval = const Duration(seconds: 60),
    Duration playbackVerificationDelay = const Duration(seconds: 4),
  })  : _transport = transport ?? const FirebaseSupabaseTelemetryTransport(),
        _deviceIdentity = deviceIdentity ?? const PlatformDeviceIdentityAdapter(),
        _now = now ?? DateTime.now,
        _presenceInterval = presenceInterval,
        _watchHeartbeatInterval = watchHeartbeatInterval,
        _playbackVerificationDelay = playbackVerificationDelay;

  // Exposed for inspection & testing
  String get currentPage => _currentPage;
  String get status => _status;
  String? get currentChannelId => _currentChannelId;
  String? get currentChannelName => _currentChannelName;
  String? get currentEventId => _currentEventId;
  String? get currentEventName => _currentEventName;
  bool get isInitialized => _isInitialized;

  /// Resolve device identity, configure analytics user properties, and start heartbeats.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final identity = await _deviceIdentity.resolveIdentity();
      _deviceId = identity.deviceId;
      _deviceName = identity.deviceName;
      _osVersion = identity.osVersion;
      _appVersion = identity.appVersion;
      _isTvDevice = identity.isTvDevice;

      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;

      unawaited(_transport.setUserId(identity.deviceId));
      _syncUserProperties();

      _status = 'online';
      await _sendHeartbeat();
      _startHeartbeatTimer();

      debugPrint('AnalyticsService initialized successfully (Device ID: $_deviceId)');
    } catch (e) {
      debugPrint('Error initializing AnalyticsService: $e');
    }
  }

  /// Release lifecycle observers and active timers.
  void dispose() {
    if (_isInitialized) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _heartbeatTimer?.cancel();
    _watchHeartbeatTimer?.cancel();
    _playbackVerificationTimer?.cancel();
  }

  // ─── Playback Telemetry Hooks ───────────────────────────────

  /// Record start of TV/M3U channel or live sports event playback.
  void startWatching(
    String channelId,
    String channelName, {
    String? categoryName,
    String? eventId,
    String? eventName,
    String? sport,
  }) {
    final normalizedEventId =
        (eventId != null && eventId.trim().isNotEmpty) ? eventId.trim() : null;
    final normalizedEventName =
        (eventName != null && eventName.trim().isNotEmpty) ? eventName.trim() : null;
    final normalizedCategory =
        (categoryName != null && categoryName.trim().isNotEmpty) ? categoryName.trim() : null;
    final normalizedSport =
        (sport != null && sport.trim().isNotEmpty) ? sport.trim() : null;

    // Flush prior watch duration if switching directly without stopWatching
    if (_watchStartedAt != null && _currentChannelId != null) {
      if (_currentChannelId == channelId && _currentEventId == normalizedEventId) {
        return;
      }
      _flushWatchDuration();
    }

    _status = 'watching';
    final isEvent = normalizedEventId != null && normalizedEventName != null;

    _currentPage = isEvent ? 'Event: $normalizedEventName' : 'Channel: $channelName';
    _currentChannelId = channelId;
    _currentChannelName = channelName;
    _currentCategoryName = normalizedCategory;
    _currentEventId = normalizedEventId;
    _currentEventName = normalizedEventName;
    _currentEventSport = normalizedSport;
    _watchStartedAt = _now();

    _triggerImmediateHeartbeat();
    _syncUserProperties();

    unawaited(
      _transport.logScreenView(
        screenName: _trunc(_currentPage, 100),
        screenClass: isEvent ? 'SportEvent' : 'LiveChannel',
      ),
    );

    if (isEvent) {
      unawaited(_transport.logEvent('watch_event', {
        'event_id': _trunc(normalizedEventId, 100),
        'event_name': _trunc(normalizedEventName, 100),
        if (normalizedSport != null) 'sport': _trunc(normalizedSport, 100),
        'channel_id': _trunc(channelId, 100),
        'channel_name': _trunc(channelName, 100),
      }));
    } else {
      unawaited(_transport.logEvent('watch_channel', {
        'channel_id': _trunc(channelId, 100),
        'channel_name': _trunc(channelName, 100),
        if (normalizedCategory != null) 'category_name': _trunc(normalizedCategory, 100),
      }));
    }

    unawaited(
      _transport.logViewItem(
        itemId: _trunc(isEvent ? normalizedEventId : channelId, 100),
        itemName: _trunc(isEvent ? normalizedEventName : channelName, 100),
        itemCategory: _trunc(
          isEvent
              ? (normalizedSport ?? 'Live Sports')
              : (normalizedCategory ?? 'General'),
          100,
        ),
        itemBrand: isEvent ? 'live_event' : 'tv_channel',
      ),
    );

    _startWatchHeartbeatTimer();

    // Verified Playback Threshold: skip temporary live_* event streams
    _playbackVerificationTimer?.cancel();
    if (!isEvent && !channelId.startsWith('live_')) {
      _playbackVerificationTimer = Timer(_playbackVerificationDelay, () {
        _recordVerifiedPlayback(
          channelId,
          channelName: channelName,
          categoryId: normalizedCategory,
        );
      });
    }
  }

  /// Record playback termination and flush accumulated watch duration.
  void stopWatching() {
    _playbackVerificationTimer?.cancel();
    _playbackVerificationTimer = null;
    _watchHeartbeatTimer?.cancel();
    _watchHeartbeatTimer = null;

    _flushWatchDuration();

    _watchStartedAt = null;
    _status = 'online';
    _currentChannelId = null;
    _currentChannelName = null;
    _currentCategoryName = null;
    _currentEventId = null;
    _currentEventName = null;
    _currentEventSport = null;

    _syncUserProperties();
    _triggerImmediateHeartbeat();
  }

  void _flushWatchDuration() {
    if (_watchStartedAt == null || _currentChannelId == null) return;
    final durationSeconds = _now().difference(_watchStartedAt!).inSeconds;
    if (durationSeconds <= 0) return;

    final isEvent = _currentEventId != null && _currentEventName != null;
    unawaited(_transport.logEvent('watch_duration', {
      'content_type': isEvent ? 'event' : 'channel',
      'channel_id': _trunc(_currentChannelId!, 100),
      'channel_name': _trunc(_currentChannelName ?? '', 100),
      if (_currentCategoryName != null) 'category_name': _trunc(_currentCategoryName!, 100),
      if (_currentEventId != null) 'event_id': _trunc(_currentEventId!, 100),
      if (_currentEventName != null) 'event_name': _trunc(_currentEventName!, 100),
      if (_currentEventSport != null) 'sport': _trunc(_currentEventSport!, 100),
      'duration_seconds': durationSeconds,
    }));
  }

  void _startWatchHeartbeatTimer() {
    _watchHeartbeatTimer?.cancel();
    _watchHeartbeatTimer = Timer.periodic(_watchHeartbeatInterval, (_) {
      _emitWatchHeartbeat();
    });
  }

  void _emitWatchHeartbeat() {
    if (_status != 'watching' || _currentChannelId == null || _watchStartedAt == null) return;
    final isEvent = _currentEventId != null && _currentEventName != null;
    final elapsedSeconds = _now().difference(_watchStartedAt!).inSeconds;

    unawaited(_transport.logEvent('watch_heartbeat', {
      'content_type': isEvent ? 'event' : 'channel',
      'channel_id': _trunc(_currentChannelId!, 100),
      'channel_name': _trunc(_currentChannelName ?? '', 100),
      if (_currentCategoryName != null) 'category_name': _trunc(_currentCategoryName!, 100),
      if (_currentEventId != null) 'event_id': _trunc(_currentEventId!, 100),
      if (_currentEventName != null) 'event_name': _trunc(_currentEventName!, 100),
      if (_currentEventSport != null) 'sport': _trunc(_currentEventSport!, 100),
      'elapsed_seconds': elapsedSeconds,
    }));
  }

  // ─── Navigation & Interaction Telemetry ─────────────────────

  /// Log a normalized screen/tab view and update `current_page` user property.
  void trackScreenView(String screenName, {String? screenClass}) {
    final normalized = normalizeScreenName(screenName);
    if (normalized.isEmpty || _currentPage == normalized) return;
    _currentPage = normalized;

    unawaited(_transport.setUserProperty('current_page', _trunc(normalized, 36)));
    unawaited(
      _transport.logScreenView(
        screenName: _trunc(normalized, 100),
        screenClass: _trunc(screenClass ?? normalized, 100),
      ),
    );
  }

  /// Log category tap / filter selection.
  void trackCategorySelect(String categoryId, String categoryName) {
    if (categoryId.trim().isEmpty) return;
    unawaited(_transport.logEvent('select_category', {
      'category_id': _trunc(categoryId, 100),
      'category_name': _trunc(categoryName.isNotEmpty ? categoryName : categoryId, 100),
    }));
  }

  /// Log user search query and result count.
  void trackSearch(String query, int resultCount) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    unawaited(_transport.logSearch(searchTerm: _trunc(trimmed, 100), resultCount: resultCount));
  }

  /// Log favorite add/remove action.
  void trackFavoriteToggle({
    required String itemId,
    required String itemName,
    required bool isFavorite,
    String contentType = 'channel',
  }) {
    unawaited(_transport.logEvent('toggle_favorite', {
      'item_id': _trunc(itemId, 100),
      'item_name': _trunc(itemName, 100),
      'action': isFavorite ? 'add' : 'remove',
      'content_type': _trunc(contentType, 100),
    }));
  }

  /// Log hero banner selection.
  void trackBannerClick({
    required String bannerId,
    required String title,
    required String actionType,
    String? actionValue,
  }) {
    unawaited(_transport.logEvent('select_banner', {
      'banner_id': _trunc(bannerId, 100),
      'banner_title': _trunc(title, 100),
      'action_type': _trunc(actionType, 100),
      if (actionValue != null && actionValue.isNotEmpty)
        'action_value': _trunc(actionValue, 100),
    }));
  }

  /// Log stream server switch (manual or auto-failover).
  void trackServerSwitch({
    required String channelId,
    required String channelName,
    required int serverIndex,
    required String serverName,
    bool isAutoFailover = false,
  }) {
    unawaited(_transport.logEvent('switch_stream_server', {
      'channel_id': _trunc(channelId, 100),
      'channel_name': _trunc(channelName, 100),
      'server_index': serverIndex,
      'server_name': _trunc(serverName, 100),
      'auto_failover': isAutoFailover ? 'true' : 'false',
    }));
  }

  /// Log stream playback startup latency.
  void trackPlaybackStartup({
    required String channelId,
    required String channelName,
    required int startupTimeMs,
  }) {
    unawaited(_transport.logEvent('playback_startup', {
      'channel_id': _trunc(channelId, 100),
      'channel_name': _trunc(channelName, 100),
      'startup_ms': startupTimeMs,
    }));
  }

  /// Log stream playback failure / error.
  void trackPlaybackError({
    required String channelId,
    required String channelName,
    required String errorType,
    required String errorMessage,
  }) {
    unawaited(_transport.logEvent('playback_error', {
      'channel_id': _trunc(channelId, 100),
      'channel_name': _trunc(channelName, 100),
      'error_type': _trunc(errorType, 100),
      'error_message': _trunc(errorMessage, 100),
    }));
  }

  // ─── Helpers ────────────────────────────────────────────────

  void _syncUserProperties() {
    final activity = _status == 'watching'
        ? (_currentEventId != null ? 'watching_event' : 'watching_channel')
        : (_status == 'offline' ? 'offline' : 'browsing');

    unawaited(_transport.setUserProperty('current_activity', activity));
    unawaited(_transport.setUserProperty('current_page', _trunc(_currentPage, 36)));
    unawaited(_transport.setUserProperty('current_channel', _trunc(_currentChannelName ?? 'none', 36)));
    unawaited(_transport.setUserProperty('current_event', _trunc(_currentEventName ?? 'none', 36)));
    unawaited(_transport.setUserProperty(
      'device_type',
      _isTvDevice ? 'android_tv' : (kIsWeb ? 'web' : 'mobile'),
    ));
  }

  /// Normalize route names/paths into clean screen identifiers (e.g. '/home' -> 'home').
  static String normalizeScreenName(String raw) {
    var name = raw.trim();
    if (name.isEmpty) return '';
    if (name.startsWith('/')) name = name.substring(1);
    if (name.isEmpty) return 'splash';
    if (name.startsWith('player/')) return 'player';
    return name.replaceAll('/', '_').replaceAll('-', '_');
  }

  static String _trunc(String value, int maxLen) {
    final trimmed = value.trim();
    if (trimmed.length <= maxLen) return trimmed;
    return trimmed.substring(0, maxLen);
  }

  /// Build presence payload (also inspectable by tests).
  Map<String, dynamic> buildPresencePayload({DateTime? timestamp}) {
    return {
      'device_id': _deviceId,
      'device_name': _deviceName,
      'os_version': _osVersion,
      'app_version': _appVersion,
      'status': _status,
      'current_page': _currentPage,
      'current_channel_id': _currentChannelId,
      'current_channel_name': _currentChannelName,
      'current_event_id': _currentEventId,
      'current_event_name': _currentEventName,
      'last_active_at': (timestamp ?? _now()).toUtc().toIso8601String(),
    };
  }

  Future<void> _recordVerifiedPlayback(
    String channelId, {
    String? channelName,
    String? categoryId,
  }) async {
    if (_deviceId == null || channelId.isEmpty) return;
    await _transport.recordVerifiedPlayback(
      channelId: channelId,
      deviceId: _deviceId!,
      channelName: channelName,
      categoryId: categoryId,
    );
  }

  // ─── Lifecycle Observer ─────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;

    if (state == AppLifecycleState.resumed) {
      _status = _currentChannelId != null ? 'watching' : 'online';
      if (_status == 'watching') {
        _startWatchHeartbeatTimer();
      }
      _syncUserProperties();
      _triggerImmediateHeartbeat();
      _startHeartbeatTimer();
      debugPrint('App resumed: Started analytics heartbeats');
    } else if (state == AppLifecycleState.paused) {
      _flushWatchDuration();
      if (_watchStartedAt != null) {
        _watchStartedAt = _now();
      }
      _status = 'offline';
      _syncUserProperties();
      _sendHeartbeat(sync: true);
      _heartbeatTimer?.cancel();
      _watchHeartbeatTimer?.cancel();
      debugPrint('App paused: Stopped analytics heartbeats');
    }
  }

  // ─── Heartbeat Loops ────────────────────────────────────────

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_presenceInterval, (_) {
      _sendHeartbeat();
    });
  }

  void _triggerImmediateHeartbeat() {
    _sendHeartbeat();
    _startHeartbeatTimer();
  }

  Future<void> _sendHeartbeat({bool sync = false}) async {
    if (_deviceId == null) return;
    await _transport.upsertPresence(buildPresencePayload(), fireAndForget: sync);
  }
}
