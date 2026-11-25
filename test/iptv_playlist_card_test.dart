import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/iptv_playlist.dart';
import 'package:goplay/screens/iptv/widgets/iptv_playlist_card.dart';

void main() {
  group('IptvPlaylistCard Widget Tests', () {
    final samplePlaylist = IptvPlaylist(
      id: 'test_p1',
      name: 'Toffee BD Sports',
      sourceType: IptvSourceType.m3uUrl,
      url: 'https://live.toffeebd.com/playlist.m3u8',
      epgUrl: 'https://xmltv.ch/epg.xml',
      addedAt: DateTime(2026, 11, 24, 10, 30),
      lastSync: DateTime(2026, 11, 25, 14, 0),
      channelCount: 76,
      channels: const [],
    );

    testWidgets('renders playlist title, channel count, and EPG tag', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: IptvPlaylistCard(
                playlist: samplePlaylist,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Toffee BD Sports'), findsOneWidget);
      expect(find.textContaining('76'), findsAtLeastNWidgets(1));
      expect(find.text('EPG'), findsOneWidget);
    });

    testWidgets('renders selection mode checkbox when selectionMode is true', (tester) async {
      bool toggleCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: IptvPlaylistCard(
                playlist: samplePlaylist,
                selectionMode: true,
                isSelected: true,
                onToggleSelect: () => toggleCalled = true,
              ),
            ),
          ),
        ),
      );

      // Verify selected state can be tapped to toggle
      await tester.tap(find.byType(IptvPlaylistCard));
      await tester.pumpAndSettle();

      expect(toggleCalled, isTrue);
    });
  });
}
