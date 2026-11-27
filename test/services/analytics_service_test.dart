import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/services/analytics_service.dart';
import 'package:goplay/services/playback/playback_state.dart';
import 'package:goplay/services/playback/playback_telemetry.dart';
import 'package:goplay/services/telemetry_transport.dart';

class _FakeDeviceIdentityAdapter implements DeviceIdentityAdapter {
  DeviceIdentityInfo info = const DeviceIdentityInfo(
    deviceId: 'dev-123',
    deviceName: 'Pixel TV',
    osVersion: 'Android 14',
    appVersion: '2.5.0',
    isTvDevice: true,
  );

  @override
  Future<DeviceIdentityInfo> resolveIdentity() async => info;
}

class _FakeTelemetryTransport implements TelemetryTransport {
  String? userId;
  final Map<String, String> userProperties = {};
  final List<(String screenName, String screenClass)> screenViews = [];
  final List<(String name, Map<String, Object> params)> events = [];
  final List<String> viewItems = [];
  final List<(String term, int count)> searches = [];
  final List<(Map<String, dynamic> payload, bool fireAndForget)> presenceUpserts = [];
  final List<({String channelId, String deviceId, String? channelName, String? categoryId})>
      verifiedPlaybacks = [];

  @override
  Future<void> setUserId(String userId) async {
    this.userId = userId;
  }

  @override
  Future<void> setUserProperty(String name, String value) async {
    userProperties[name] = value;
  }

  @override
  Future<void> logScreenView({
    required String screenName,
    required String screenClass,
  }) async {
    screenViews.add((screenName, screenClass));
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add((name, parameters));
  }

  @override
  Future<void> logViewItem({
    required String itemId,
    required String itemName,
    required String itemCategory,
    required String itemBrand,
  }) async {
    viewItems.add('$itemId:$itemName:$itemCategory:$itemBrand');
  }

  @override
  Future<void> logSearch({
    required String searchTerm,
    required int resultCount,
  }) async {
    searches.add((searchTerm, resultCount));
  }

  @override
  Future<void> upsertPresence(
    Map<String, dynamic> payload, {
    bool fireAndForget = false,
  }) async {
    presenceUpserts.add((payload, fireAndForget));
  }

  @override
  Future<void> recordVerifiedPlayback({
    required String channelId,
    required String deviceId,
    String? channelName,
    String? categoryId,
  }) async {
    verifiedPlaybacks.add((
      channelId: channelId,
      deviceId: deviceId,
      channelName: channelName,
      categoryId: categoryId,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyticsService & TelemetryTransport seam', () {
    test('initialize resolves identity, sets user properties, and emits initial presence', () async {
      final transport = _FakeTelemetryTransport();
      final service = AnalyticsService(
        transport: transport,
        deviceIdentity: _FakeDeviceIdentityAdapter(),
      );

      await service.initialize();
      addTearDown(service.dispose);

      expect(service.isInitialized, isTrue);
      expect(transport.userId, 'dev-123');
      expect(transport.userProperties['device_type'], 'android_tv');
      expect(transport.userProperties['current_activity'], 'browsing');
      expect(transport.presenceUpserts, hasLength(1));
      expect(transport.presenceUpserts.single.$1['device_id'], 'dev-123');
      expect(transport.presenceUpserts.single.$1['status'], 'online');
    });

    test('tracks channel watch, duration, heartbeats, and skips verified trending for live_* events', () async {
      var now = DateTime.utc(2026, 11, 27, 10, 0, 0);
      final transport = _FakeTelemetryTransport();
      final service = AnalyticsService(
        transport: transport,
        deviceIdentity: _FakeDeviceIdentityAdapter(),
        now: () => now,
        playbackVerificationDelay: const Duration(milliseconds: 20),
        watchHeartbeatInterval: const Duration(milliseconds: 25),
      );

      await service.initialize();
      addTearDown(service.dispose);

      service.startWatching('ch-1', 'Star Sports 1', categoryName: 'Sports');
      expect(service.status, 'watching');
      expect(service.currentPage, 'Channel: Star Sports 1');
      expect(transport.screenViews.last, ('Channel: Star Sports 1', 'LiveChannel'));
      expect(transport.events.any((e) => e.$1 == 'watch_channel'), isTrue);
      expect(transport.viewItems.last, 'ch-1:Star Sports 1:Sports:tv_channel');

      await Future.delayed(const Duration(milliseconds: 60));
      expect(transport.verifiedPlaybacks, hasLength(1));
      expect(transport.verifiedPlaybacks.single.channelName, 'Star Sports 1');
      expect(transport.verifiedPlaybacks.single.categoryId, 'Sports');
      expect(transport.events.any((e) => e.$1 == 'watch_heartbeat'), isTrue);

      now = now.add(const Duration(seconds: 45));
      service.stopWatching();
      expect(service.status, 'online');
      final durEvent = transport.events.lastWhere((e) => e.$1 == 'watch_duration');
      expect(durEvent.$2['duration_seconds'], 45);
      expect(durEvent.$2['content_type'], 'channel');

      // Live event stream skips verified channel trending RPC
      service.startWatching(
        'live_ev1_0',
        'Server 1',
        eventId: 'ev1',
        eventName: 'India vs Australia',
        sport: 'Cricket',
      );
      await Future.delayed(const Duration(milliseconds: 40));
      expect(transport.verifiedPlaybacks, hasLength(1));
      expect(transport.userProperties['current_activity'], 'watching_event');
    });

    test('PlaybackTelemetry forwards startup, error, and auto-failover to injected AnalyticsService', () {
      final transport = _FakeTelemetryTransport();
      final service = AnalyticsService(
        transport: transport,
        deviceIdentity: _FakeDeviceIdentityAdapter(),
      );
      final telemetry = PlaybackTelemetry(analytics: service);

      telemetry.recordStartup(
        channelId: 'ch-1',
        channelName: 'Somoy TV',
        startupTimeMs: 420,
      );
      telemetry.recordError(
        channelId: 'ch-1',
        channelName: 'Somoy TV',
        errorType: ErrorType.serverError,
        rawMessage: 'HTTP 502',
      );
      telemetry.recordAutoFailover(
        channelId: 'ch-1',
        channelName: 'Somoy TV',
        serverIndex: 1,
        serverName: 'Server 2',
      );

      expect(
        transport.events.map((e) => e.$1),
        ['playback_startup', 'playback_error', 'switch_stream_server'],
      );
      expect(transport.events.last.$2['auto_failover'], 'true');
    });

    test('normalizes screen names and handles lifecycle pause/resume state', () async {
      final transport = _FakeTelemetryTransport();
      final service = AnalyticsService(
        transport: transport,
        deviceIdentity: _FakeDeviceIdentityAdapter(),
      );
      await service.initialize();
      addTearDown(service.dispose);

      service.trackScreenView('/home');
      service.trackScreenView('/settings/player');
      service.trackScreenView('/player/ch-99');
      expect(service.currentPage, 'player');
      expect(transport.screenViews.map((s) => s.$1), ['home', 'settings_player', 'player']);

      service.startWatching('ch-9', 'BTV');
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(service.status, 'offline');
      expect(transport.presenceUpserts.last.$2, isTrue); // fireAndForget=true on pause

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(service.status, 'watching');
    });
  });
}
