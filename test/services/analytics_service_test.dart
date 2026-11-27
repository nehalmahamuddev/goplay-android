import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/services/analytics_service.dart';

void main() {
  group('AnalyticsService', () {
    test('tracks live channel watching and resets on stopWatching', () {
      final service = AnalyticsService();
      expect(service.currentPage, 'splash');
      expect(service.status, 'online');

      service.startWatching(
        'ch-1',
        'Star Sports 1',
        categoryName: 'Sports',
      );

      expect(service.status, 'watching');
      expect(service.currentPage, 'Channel: Star Sports 1');
      expect(service.currentChannelId, 'ch-1');
      expect(service.currentChannelName, 'Star Sports 1');
      expect(service.currentEventId, isNull);
      expect(service.currentEventName, isNull);

      final payload = service.buildPresencePayload(
        timestamp: DateTime.utc(2026, 11, 27, 10, 0),
      );
      expect(payload['status'], 'watching');
      expect(payload['current_page'], 'Channel: Star Sports 1');
      expect(payload['current_channel_id'], 'ch-1');
      expect(payload['current_channel_name'], 'Star Sports 1');
      expect(payload['current_event_id'], isNull);
      expect(payload['current_event_name'], isNull);

      service.stopWatching();
      expect(service.status, 'online');
      expect(service.currentChannelId, isNull);
      expect(service.currentChannelName, isNull);
    });

    test('tracks live sports event watching alongside channel metadata', () {
      final service = AnalyticsService();

      service.startWatching(
        'live_ev1_0',
        'Server 1',
        categoryName: 'Cricket',
        eventId: 'ev1',
        eventName: 'India vs Australia',
        sport: 'Cricket',
      );

      expect(service.status, 'watching');
      expect(service.currentEventId, 'ev1');
      expect(service.currentEventName, 'India vs Australia');
      expect(service.currentChannelId, 'live_ev1_0');

      final payload = service.buildPresencePayload();
      expect(payload['current_event_id'], 'ev1');
      expect(payload['current_event_name'], 'India vs Australia');
      expect(payload['current_page'], 'Event: India vs Australia');

      // Switching from event to regular TV channel clears stale event metadata
      service.startWatching('ch-2', 'BBC World', categoryName: 'News');
      expect(service.currentEventId, isNull);
      expect(service.currentEventName, isNull);
      expect(service.currentChannelId, 'ch-2');
      expect(service.currentChannelName, 'BBC World');
    });

    test('normalizes screen names across routes and tabs', () {
      final service = AnalyticsService();

      service.trackScreenView('/home');
      expect(service.currentPage, 'home');

      service.trackScreenView('/settings/player');
      expect(service.currentPage, 'settings_player');

      service.trackScreenView('/player/ch-99');
      expect(service.currentPage, 'player');

      service.trackScreenView('favorites');
      expect(service.currentPage, 'favorites');
    });
  });
}
