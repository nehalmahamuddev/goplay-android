import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

/// Service to handle real-time user presence and Firebase Analytics telemetry.
class AnalyticsService with WidgetsBindingObserver {
  /// Global active instance for non-Widget observers (GoRouter, PlaybackTelemetry).
  static AnalyticsService? activeInstance;

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

  AnalyticsService() {
    activeInstance = this;
  }

  // Exposed for unit testing and inspection
  String get currentPage => _currentPage;
  String get status => _status;
  String? get currentChannelId => _currentChannelId;
  String? get currentChannelName => _currentChannelName;
  String? get currentEventId => _currentEventId;
  String? get currentEventName => _currentEventName;
  bool get isInitialized => _isInitialized;

  /// Initialize device info, generate unique ID if needed, and start heartbeats.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final box = Hive.box(AppConstants.settingsBox);

      // 1. Retrieve or generate unique device_id
      _deviceId = box.get('analytics_device_id') as String?;
      _deviceName = box.get('analytics_device_name') as String?;
      _osVersion = box.get('analytics_os_version') as String?;
      _isTvDevice = box.get('analytics_is_tv') as bool? ?? false;

      if (_deviceId == null || _deviceName == null || _osVersion == null) {
        final deviceInfo = DeviceInfoPlugin();

        if (kIsWeb) {
          _deviceId = _generateUuid();
          _deviceName = 'Web Browser';
          _osVersion = 'Web';
          _isTvDevice = false;
        } else {
          if (Platform.isAndroid) {
            try {
              final androidInfo = await deviceInfo.androidInfo;
              _deviceId = androidInfo.id.isNotEmpty ? androidInfo.id : _generateUuid();
              _deviceName = '${androidInfo.brand} ${androidInfo.model}';
              _osVersion = 'Android ${androidInfo.version.release}';
              _isTvDevice = androidInfo.systemFeatures.contains('android.software.leanback');
            } catch (e) {
              debugPrint('Failed to get Android device info: $e');
              _deviceId = _generateUuid();
              _deviceName = 'Android TV Device';
              _osVersion = 'Android TV';
              _isTvDevice = true;
            }
          } else if (Platform.isIOS) {
            final iosInfo = await deviceInfo.iosInfo;
            _deviceId = iosInfo.identifierForVendor ?? _generateUuid();
            _deviceName = iosInfo.name;
            _osVersion = 'iOS ${iosInfo.systemVersion}';
            _isTvDevice = false;
          } else {
            _deviceId = _generateUuid();
            _deviceName = Platform.operatingSystem;
            _osVersion = Platform.operatingSystemVersion;
            _isTvDevice = false;
          }
        }

        // Cache resolved info to prevent future async calls
        await box.put('analytics_device_id', _deviceId);
        await box.put('analytics_device_name', _deviceName);
        await box.put('analytics_os_version', _osVersion);
        await box.put('analytics_is_tv', _isTvDevice);
      }

      // 2. Fetch app version
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        _appVersion = packageInfo.version;
      } catch (_) {
        _appVersion = AppConstants.appVersion;
      }

      // 3. Register lifecycle observer
      WidgetsBinding.instance.addObserver(this);
      _isInitialized = true;

      // 4. Configure Firebase Analytics user ID, properties & send initial heartbeat
      if (Firebase.apps.isNotEmpty && _deviceId != null) {
        unawaited(FirebaseAnalytics.instance.setUserId(id: _deviceId).catchError((_) {}));
        _syncUserProperties();
      }
      _status = 'online';
      await _sendHeartbeat();
      _startHeartbeatTimer();

      debugPrint('AnalyticsService initialized successfully (Device ID: $_deviceId)');
    } catch (e) {
      debugPrint('Error initializing AnalyticsService: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _watchHeartbeatTimer?.cancel();
    _playbackVerificationTimer?.cancel();
  }

  // ─── Playback Telemetry Hooks ───────────────────────────────

  /// Call when user starts watching a channel or live sports event.
  void startWatching(
    String channelId,
    String channelName, {
    String? categoryName,
    String? eventId,
    String? eventName,
    String? sport,
  }) {
    final normalizedEventId = (eventId != null && eventId.trim().isNotEmpty) ? eventId.trim() : null;
    final normalizedEventName = (eventName != null && eventName.trim().isNotEmpty) ? eventName.trim() : null;
    final normalizedCategory = (categoryName != null && categoryName.trim().isNotEmpty) ? categoryName.trim() : null;
    final normalizedSport = (sport != null && sport.trim().isNotEmpty) ? sport.trim() : null;

    // Flush any prior watch duration if switching channels/events directly without stopWatching
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
    _watchStartedAt = DateTime.now();

    _triggerImmediateHeartbeat();
    _syncUserProperties();

    // Log the channel-specific screen view so it appears directly on the "PAGE TITLE AND SCREEN NAME" Realtime card
    if (Firebase.apps.isNotEmpty) {
      unawaited(
        FirebaseAnalytics.instance
            .logScreenView(
              screenName: _trunc(_currentPage, 100),
              screenClass: isEvent ? 'SportEvent' : 'LiveChannel',
            )
            .catchError((_) {}),
      );
    }

    if (isEvent) {
      _logFirebaseEvent('watch_event', {
        'event_id': _trunc(normalizedEventId, 100),
        'event_name': _trunc(normalizedEventName, 100),
        if (normalizedSport != null) 'sport': _trunc(normalizedSport, 100),
        'channel_id': _trunc(channelId, 100),
        'channel_name': _trunc(channelName, 100),
      });
    } else {
      _logFirebaseEvent('watch_channel', {
        'channel_id': _trunc(channelId, 100),
        'channel_name': _trunc(channelName, 100),
        if (normalizedCategory != null) 'category_name': _trunc(normalizedCategory, 100),
      });
    }

    // Standard GA4 view_item populates built-in Item Analytics reports automatically
    if (Firebase.apps.isNotEmpty) {
      unawaited(
        FirebaseAnalytics.instance
            .logViewItem(
              items: [
                AnalyticsEventItem(
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
              ],
            )
            .catchError((_) {}),
      );
    }

    // Start 60-second heartbeat so Firebase Realtime 5-min/30-min views always capture active viewers
    _startWatchHeartbeatTimer();

    // Verified Playback Threshold: count after 4 seconds of uninterrupted watching
    // Skip temporary live sports event streams (live_*) so they don't pollute TV channel trending.
    _playbackVerificationTimer?.cancel();
    if (!isEvent && !channelId.startsWith('live_')) {
      _playbackVerificationTimer = Timer(const Duration(seconds: 4), () {
        _recordVerifiedPlayback(
          channelId,
          channelName: channelName,
          categoryId: normalizedCategory,
        );
      });
    }
  }

  /// Call when user stops watching (closes player).
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
    final durationSeconds = DateTime.now().difference(_watchStartedAt!).inSeconds;
    if (durationSeconds <= 0) return;

    final isEvent = _currentEventId != null && _currentEventName != null;
    _logFirebaseEvent('watch_duration', {
      'content_type': isEvent ? 'event' : 'channel',
      'channel_id': _trunc(_currentChannelId!, 100),
      'channel_name': _trunc(_currentChannelName ?? '', 100),
      if (_currentCategoryName != null) 'category_name': _trunc(_currentCategoryName!, 100),
      if (_currentEventId != null) 'event_id': _trunc(_currentEventId!, 100),
      if (_currentEventName != null) 'event_name': _trunc(_currentEventName!, 100),
      if (_currentEventSport != null) 'sport': _trunc(_currentEventSport!, 100),
      'duration_seconds': durationSeconds,
    });
  }

  void _startWatchHeartbeatTimer() {
    _watchHeartbeatTimer?.cancel();
    _watchHeartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _emitWatchHeartbeat();
    });
  }

  void _emitWatchHeartbeat() {
    if (_status != 'watching' || _currentChannelId == null || _watchStartedAt == null) return;
    final isEvent = _currentEventId != null && _currentEventName != null;
    final elapsedSeconds = DateTime.now().difference(_watchStartedAt!).inSeconds;

    _logFirebaseEvent('watch_heartbeat', {
      'content_type': isEvent ? 'event' : 'channel',
      'channel_id': _trunc(_currentChannelId!, 100),
      'channel_name': _trunc(_currentChannelName ?? '', 100),
      if (_currentCategoryName != null) 'category_name': _trunc(_currentCategoryName!, 100),
      if (_currentEventId != null) 'event_id': _trunc(_currentEventId!, 100),
      if (_currentEventName != null) 'event_name': _trunc(_currentEventName!, 100),
      if (_currentEventSport != null) 'sport': _trunc(_currentEventSport!, 100),
      'elapsed_seconds': elapsedSeconds,
    });
  }

  // ─── Navigation & Interaction Telemetry ─────────────────────

  /// Log a clean screen/tab view to Firebase Analytics and keep currentPage synced.
  void trackScreenView(String screenName, {String? screenClass}) {
    final normalized = _normalizeScreenName(screenName);
    if (normalized.isEmpty) return;

    // Avoid duplicate consecutive screen views on same tab/route
    if (_currentPage == normalized) return;
    _currentPage = normalized;

    if (Firebase.apps.isNotEmpty) {
      unawaited(
        FirebaseAnalytics.instance
            .setUserProperty(name: 'current_page', value: _trunc(normalized, 36))
            .catchError((_) {}),
      );
      unawaited(
        FirebaseAnalytics.instance
            .logScreenView(
              screenName: _trunc(normalized, 100),
              screenClass: _trunc(screenClass ?? normalized, 100),
            )
            .catchError((_) {}),
      );
    }
  }

  /// Log category tap / filter selection.
  void trackCategorySelect(String categoryId, String categoryName) {
    if (categoryId.trim().isEmpty) return;
    _logFirebaseEvent('select_category', {
      'category_id': _trunc(categoryId, 100),
      'category_name': _trunc(categoryName.isNotEmpty ? categoryName : categoryId, 100),
    });
  }

  /// Log user search query + match count using standard GA4 search event.
  void trackSearch(String query, int resultCount) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    if (Firebase.apps.isNotEmpty) {
      unawaited(
        FirebaseAnalytics.instance
            .logSearch(
              searchTerm: _trunc(trimmed, 100),
              parameters: {'result_count': resultCount},
            )
            .catchError((_) {}),
      );
    }
  }

  /// Log favorite add/remove action.
  void trackFavoriteToggle({
    required String itemId,
    required String itemName,
    required bool isFavorite,
    String contentType = 'channel',
  }) {
    _logFirebaseEvent('toggle_favorite', {
      'item_id': _trunc(itemId, 100),
      'item_name': _trunc(itemName, 100),
      'action': isFavorite ? 'add' : 'remove',
      'content_type': _trunc(contentType, 100),
    });
  }

  /// Log hero banner selection.
  void trackBannerClick({
    required String bannerId,
    required String title,
    required String actionType,
    String? actionValue,
  }) {
    _logFirebaseEvent('select_banner', {
      'banner_id': _trunc(bannerId, 100),
      'banner_title': _trunc(title, 100),
      'action_type': _trunc(actionType, 100),
      if (actionValue != null && actionValue.isNotEmpty)
        'action_value': _trunc(actionValue, 100),
    });
  }

  /// Log stream server switch (manual or auto-failover).
  void trackServerSwitch({
    required String channelId,
    required String channelName,
    required int serverIndex,
    required String serverName,
    bool isAutoFailover = false,
  }) {
    _logFirebaseEvent('switch_stream_server', {
      'channel_id': _trunc(channelId, 100),
      'channel_name': _trunc(channelName, 100),
      'server_index': serverIndex,
      'server_name': _trunc(serverName, 100),
      'auto_failover': isAutoFailover ? 'true' : 'false',
    });
  }

  /// Log stream playback failure / error.
  void trackPlaybackError({
    required String channelId,
    required String channelName,
    required String errorType,
    required String errorMessage,
  }) {
    _logFirebaseEvent('playback_error', {
      'channel_id': _trunc(channelId, 100),
      'channel_name': _trunc(channelName, 100),
      'error_type': _trunc(errorType, 100),
      'error_message': _trunc(errorMessage, 100),
    });
  }

  // ─── Firebase Helpers ───────────────────────────────────────

  void _syncUserProperties() {
    if (Firebase.apps.isEmpty) return;
    final activity = _status == 'watching'
        ? (_currentEventId != null ? 'watching_event' : 'watching_channel')
        : (_status == 'offline' ? 'offline' : 'browsing');

    final analytics = FirebaseAnalytics.instance;
    unawaited(analytics.setUserProperty(name: 'current_activity', value: activity).catchError((_) {}));
    unawaited(analytics.setUserProperty(name: 'current_page', value: _trunc(_currentPage, 36)).catchError((_) {}));
    unawaited(analytics.setUserProperty(name: 'current_channel', value: _trunc(_currentChannelName ?? 'none', 36)).catchError((_) {}));
    unawaited(analytics.setUserProperty(name: 'current_event', value: _trunc(_currentEventName ?? 'none', 36)).catchError((_) {}));
    unawaited(analytics.setUserProperty(
      name: 'device_type',
      value: _isTvDevice ? 'android_tv' : (kIsWeb ? 'web' : 'mobile'),
    ).catchError((_) {}));
  }

  void _logFirebaseEvent(String name, Map<String, Object> parameters) {
    if (Firebase.apps.isEmpty) return;
    unawaited(
      FirebaseAnalytics.instance
          .logEvent(name: name, parameters: parameters)
          .catchError((_) {}),
    );
  }

  /// Normalize route names/paths into clean screen identifiers (e.g. '/home' -> 'home').
  static String _normalizeScreenName(String raw) {
    var name = raw.trim();
    if (name.isEmpty) return '';
    if (name.startsWith('/')) name = name.substring(1);
    if (name.isEmpty) return 'splash';
    // Strip path parameters like player/123 -> player
    final slashIndex = name.indexOf('/');
    if (slashIndex > 0 && name.startsWith('player/')) {
      return 'player';
    }
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
      'last_active_at': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  /// Record verified playback event to Supabase for dynamic trending
  Future<void> _recordVerifiedPlayback(
    String channelId, {
    String? channelName,
    String? categoryId,
  }) async {
    if (_deviceId == null || channelId.isEmpty) return;

    try {
      final client = Supabase.instance.client;
      await client.rpc('record_channel_playback', params: {
        'p_channel_id': channelId,
        'p_device_id': _deviceId,
        if (channelName != null && channelName.isNotEmpty) 'p_channel_name': channelName,
        if (categoryId != null && categoryId.isNotEmpty) 'p_category_id': categoryId,
      });
      debugPrint('Recorded verified playback for dynamic trending: $channelId');
    } catch (e) {
      debugPrint('Failed to record channel playback for trending: $e');
    }
  }

  // ─── Lifecycle Observer ─────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;

    if (state == AppLifecycleState.resumed) {
      // App brought to foreground - restore correct watching/online state
      _status = _currentChannelId != null ? 'watching' : 'online';
      if (_status == 'watching') {
        _startWatchHeartbeatTimer();
      }
      _syncUserProperties();
      _triggerImmediateHeartbeat();
      _startHeartbeatTimer();
      debugPrint('App resumed: Started analytics heartbeats');
    } else if (state == AppLifecycleState.paused) {
      // App sent to background - flush watch duration, mark offline, stop timers
      _flushWatchDuration();
      if (_watchStartedAt != null) {
        // Reset start timestamp in case app resumes seamlessly in same player session
        _watchStartedAt = DateTime.now();
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 120), (_) {
      _sendHeartbeat();
    });
  }

  void _triggerImmediateHeartbeat() {
    _sendHeartbeat();
    // Restart timer sequence to align with the latest state change
    _startHeartbeatTimer();
  }

  Future<void> _sendHeartbeat({bool sync = false}) async {
    if (_deviceId == null) return;

    final presenceData = buildPresencePayload();

    try {
      final client = Supabase.instance.client;
      if (sync) {
        // Run un-awaited to execute quickly during app exit/pause
        unawaited(client.from('user_presence').upsert(presenceData, onConflict: 'device_id').then((_) {}).catchError((_) {}));
      } else {
        await client.from('user_presence').upsert(presenceData, onConflict: 'device_id');
      }
    } catch (e) {
      debugPrint('Failed to send presence heartbeat: $e');
    }
  }

  // ─── Helper UUID generator ──────────────────────────────────

  /// Generates a RFC 4122 v4 compliant UUID in pure Dart (no dependencies).
  String _generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));

    // Set version to 4 (random)
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    values[8] = (values[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
      if (i == 3 || i == 5 || i == 7 || i == 9) {
        buffer.write('-');
      }
    }
    return buffer.toString();
  }
}
