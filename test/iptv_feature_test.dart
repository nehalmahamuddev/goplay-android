import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:goplay/core/constants.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/models/drm_config.dart';
import 'package:goplay/models/iptv_playlist.dart';
import 'package:goplay/providers/iptv_providers.dart';
import 'package:goplay/screens/iptv/iptv_screen.dart';
import 'package:goplay/screens/iptv/widgets/iptv_add_helpers.dart';
import 'package:goplay/screens/iptv/widgets/iptv_add_menu_sheet.dart';
import 'package:goplay/screens/iptv/widgets/iptv_add_source_dialog.dart';
import 'package:goplay/screens/iptv/widgets/iptv_channel_browser_sheet.dart';
import 'package:goplay/screens/iptv/widgets/iptv_home_dialogs.dart';
import 'package:goplay/screens/iptv/widgets/iptv_svg_icon.dart';
import 'package:goplay/screens/iptv/widgets/iptv_view_settings_sheet.dart';
import 'package:goplay/services/iptv_service.dart';

/// Lightweight in-memory [IptvService] for `testWidgets` so real Riverpod
/// notifiers (`IptvBookmarksNotifier`, `IptvViewConfigsNotifier`,
/// `IptvSettingsNotifier`, `IptvPlaylistsNotifier`) run end-to-end without
/// opening VM `RandomAccessFile` locks inside Flutter's `FakeAsync` zone.
class _MemoryIptvService extends IptvService {
  IptvGlobalSettings _settings = const IptvGlobalSettings();
  Map<String, IptvViewConfig> _viewConfigs = {};
  Map<String, IptvBookmarkItem> _bookmarks = {};
  List<IptvEpgSource> _epgSources = [];
  List<IptvPlaylist> _playlists;

  _MemoryIptvService([List<IptvPlaylist>? initialPlaylists])
      : _playlists = List<IptvPlaylist>.from(initialPlaylists ?? const []);

  @override
  Future<List<IptvPlaylist>> getSavedPlaylists() async => _playlists;

  @override
  Future<void> savePlaylist(IptvPlaylist playlist) async {
    _playlists = [playlist, ..._playlists.where((p) => p.id != playlist.id)];
  }

  @override
  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists) async {
    _playlists = List<IptvPlaylist>.from(playlists);
  }

  @override
  Future<void> deletePlaylist(String id) async {
    _playlists = _playlists.where((p) => p.id != id).toList();
  }

  @override
  IptvGlobalSettings loadGlobalSettings() => _settings;

  @override
  Future<void> saveGlobalSettings(IptvGlobalSettings settings) async {
    _settings = settings;
  }

  @override
  Map<String, IptvViewConfig> loadViewConfigs() => _viewConfigs;

  @override
  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs) async {
    _viewConfigs = Map<String, IptvViewConfig>.from(configs);
  }

  @override
  Map<String, IptvBookmarkItem> loadBookmarks() => _bookmarks;

  @override
  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks) async {
    _bookmarks = Map<String, IptvBookmarkItem>.from(bookmarks);
  }

  @override
  List<IptvEpgSource> loadSavedEpgSources() => _epgSources;

  @override
  Future<void> saveEpgSources(List<IptvEpgSource> sources) async {
    _epgSources = List<IptvEpgSource>.from(sources);
  }

  @override
  Future<Map<String, List<IptvEpgProgramme>>> fetchAndParseEpg(
    String epgUrl, {
    Map<String, String>? headers,
  }) async {
    final now = DateTime.now();
    return {
      'toffeetv': [
        IptvEpgProgramme(
          channelKey: 'toffeetv',
          title: 'Sample Guide Show',
          startTime: now.subtract(const Duration(minutes: 10)),
          stopTime: now.add(const Duration(minutes: 50)),
        ),
      ],
    };
  }

  @override
  Future<String?> probeUrlMimeType(
    String url, {
    Map<String, String>? headers,
  }) async {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  @override
  Future<StalkerTestResult> testStalkerConnection({
    required String portalUrl,
    required String macAddress,
  }) async {
    return StalkerTestResult(
      token: 'STALKER_TOK_99',
      expiry: '2027-12-31',
      mac: macAddress.trim().replaceAll('-', ':').toUpperCase(),
    );
  }

  @override
  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist) async {
    return playlist.copyWith(
      lastSync: DateTime.now(),
      channelCount: 1,
      channels: [
        Channel(
          id: '${playlist.id}_ch1',
          name: playlist.name,
          streamUrl: playlist.url,
          category: 'General',
          isLive: true,
          quality: 'HD',
          drm: playlist.drm,
          headers: {
            ...playlist.headers,
            if (playlist.authorization != null) 'Authorization': playlist.authorization!,
            if (playlist.subtitleUrl != null) 'X-Subtitle-Url': playlist.subtitleUrl!,
          },
        ),
      ],
    );
  }
}

void main() {
  group('ClearKey & M3U / JSON Parser Tests', () {
    test('DrmConfig.parseClearKeys parses JWK JSON, flat JSON, comma pairs & single hex', () {
      final jwkRaw = jsonEncode({
        'keys': [
          {
            'kty': 'oct',
            'kid': 'ABEiM0RVZneImaq7zN3u_w',
            'k': 'ZmVkY2JhOTg3NjU0MzIxMA',
          }
        ],
        'type': 'temporary',
      });
      final jwkParsed = DrmConfig.parseClearKeys(jwkRaw);
      expect(jwkParsed['00112233445566778899aabbccddeeff'], isNotEmpty);

      const flatRaw = '{"DeAdBeEfDeAdBeEfDeAdBeEfDeAdBeEf":"CaFeBaBeCaFeBaBeCaFeBaBeCaFeBaBe"}';
      final flatParsed = DrmConfig.parseClearKeys(flatRaw);
      expect(
        flatParsed['deadbeefdeadbeefdeadbeefdeadbeef'],
        'cafebabecafebabecafebabecafebabe',
      );

      const multiPairs =
          'aaaa1111aaaa1111aaaa1111aaaa1111:bbbb2222bbbb2222bbbb2222bbbb2222,cccc3333cccc3333cccc3333cccc3333:dddd4444dddd4444dddd4444dddd4444';
      final multiParsed = DrmConfig.parseClearKeys(multiPairs);
      expect(multiParsed.length, 2);
      expect(
        multiParsed['cccc3333cccc3333cccc3333cccc3333'],
        'dddd4444dddd4444dddd4444dddd4444',
      );
    });

    test('parseM3uOrJsonContent extracts EPG URL, JWK ClearKey JSON, EXTVLCOPT, EXTHTTP & pipe params', () {
      const m3u = '''
#EXTM3U url-tvg="https://epg.example.com/guide.xml.gz"
#EXTINF:-1 tvg-id="sony.max" group-title="Movies",Sony MAX HD
#KODIPROP:inputstream.adaptive.license_type=org.w3.clearkey
#KODIPROP:inputstream.adaptive.license_key={"deadbeefdeadbeefdeadbeefdeadbeef":"cafebabecafebabecafebabecafebabe"}
#EXTVLCOPT:http-user-agent=CustomPlayer/1.0
#EXTVLCOPT:http-referrer=https://ref.example.com/
#EXTHTTP:{"cookie":"sid=abc123","origin":"https://origin.example.com"}
https://cdn.example.com/sony/index.mpd

#EXTINF:-1 group-title="Sports",Cricket One
#https://cdn.example.com/cricket.m3u8|User-Agent=PipeUA&Cookie=tok=99&Referer=https://pipe.ref/&Origin=https://pipe.orig
''';

      final result = parseM3uOrJsonContent(m3u, 'pl_test');
      expect(result.detectedEpgUrl, 'https://epg.example.com/guide.xml.gz');
      expect(result.channels.length, 2);

      final sony = result.channels[0];
      expect(sony.name, 'Sony MAX HD');
      expect(sony.category, 'Movies');
      expect(sony.tvgId, 'sony.max');
      expect(sony.hasDrm, isTrue);
      expect(sony.drm?.type, DrmType.clearkey);
      expect(
        sony.drm?.clearKeys?['deadbeefdeadbeefdeadbeefdeadbeef'],
        'cafebabecafebabecafebabecafebabe',
      );
      expect(sony.headers['User-Agent'], 'CustomPlayer/1.0');
      expect(sony.headers['Referer'], 'https://ref.example.com/');
      expect(sony.headers['Cookie'] ?? sony.headers['cookie'], 'sid=abc123');

      final cricket = result.channels[1];
      expect(cricket.name, 'Cricket One');
      expect(cricket.streamUrl, 'https://cdn.example.com/cricket.m3u8');
      expect(cricket.headers['User-Agent'], 'PipeUA');
      expect(cricket.headers['Cookie'], 'tok=99');
      expect(cricket.headers['Referer'], 'https://pipe.ref/');
      expect(cricket.headers['Origin'], 'https://pipe.orig');
    });

    test('parseM3uOrJsonContent parses JSON playlist array format', () {
      const jsonContent = '''
[
  {
    "EXTINF": {
      "title": "Toffee TV",
      "groupTitle": "Family",
      "tvgId": "toffee.tv"
    },
    "KODIPROP": {
      "licenseType": "clearkey",
      "licenseKey": "11111111111111111111111111111111:22222222222222222222222222222222"
    },
    "EXTVLCOPT": {
      "httpUserAgent": "JsonUA",
      "cookie": "c=1"
    },
    "url": "https://cdn.example.com/toffee/index.mpd"
  }
]
''';
      final result = parseM3uOrJsonContent(jsonContent, 'pl_json');
      expect(result.channels.length, 1);
      final ch = result.channels.first;
      expect(ch.name, 'Toffee TV');
      expect(ch.category, 'Family');
      expect(ch.tvgId, 'toffee.tv');
      expect(ch.drm?.type, DrmType.clearkey);
      expect(
        ch.drm?.clearKeys?['11111111111111111111111111111111'],
        '22222222222222222222222222222222',
      );
      expect(ch.headers['User-Agent'], 'JsonUA');
      expect(ch.headers['Cookie'], 'c=1');
    });
  });

  group('XMLTV EPG & Category Grouping Tests', () {
    test('parseXmltvEpg & lookupEpgProgrammesForChannel match tvgId and kEpgQualityRegex fallback', () {
      const xml = '''
<tv>
  <channel id="cnn.us">
    <display-name>CNN</display-name>
  </channel>
  <programme start="20261125120000 +0000" stop="20261125130000 +0000" channel="cnn.us">
    <title>World News Now</title>
    <desc>Hourly global headlines</desc>
  </programme>
</tv>
''';
      final epgMap = parseXmltvEpg(xml);
      expect(epgMap['cnn.us'], isNotEmpty);
      expect(epgMap['cnn'], isNotEmpty);

      final chNoTvgId = Channel(
        id: 'c_1',
        name: 'CNN HD',
        streamUrl: 'https://example.com/cnn.m3u8',
      );
      final matched = lookupEpgProgrammesForChannel(chNoTvgId, epgMap);
      expect(matched.length, 1);
      expect(matched.first.title, 'World News Now');
    });

    test('buildGroupedCategories keeps "All" at index 0 after sorting, and respects hideAllCategory', () {
      final channels = [
        Channel(id: '1', name: 'F1', streamUrl: 'https://a/1.m3u8', category: 'Family'),
        Channel(id: '2', name: 'M1', streamUrl: 'https://a/2.m3u8', category: 'Movies'),
        Channel(id: '3', name: 'M2', streamUrl: 'https://a/3.m3u8', category: 'Movies'),
        Channel(id: '4', name: 'M3', streamUrl: 'https://a/4.m3u8', category: 'Movies'),
        Channel(id: '5', name: 'S1', streamUrl: 'https://a/5.m3u8', category: 'Sports'),
        Channel(id: '6', name: 'S2', streamUrl: 'https://a/6.m3u8', category: 'Sports'),
      ];

      final sorted = buildGroupedCategories(channels, sortByCountDesc: true);
      expect(sorted.map((g) => g.title).toList(), ['All', 'Movies', 'Sports', 'Family']);
      expect(sorted.first.tabLabel, 'All (6)');

      final hiddenAll = buildGroupedCategories(
        channels,
        sortByCountDesc: true,
        hideAllCategory: true,
      );
      expect(hiddenAll.map((g) => g.title).toList(), ['Movies', 'Sports', 'Family']);
    });

    test('filterIptvCategoryChannels filters strictly by title', () {
      final channels = [
        Channel(id: '1', name: 'Toffee Movies', streamUrl: 'https://a/1', category: 'Movies'),
        Channel(id: '2', name: 'Sony MAX HD', streamUrl: 'https://a/movies', category: 'Movies'),
      ];
      final res = filterIptvCategoryChannels(channels, 'movies');
      expect(res.length, 1);
      expect(res.first.name, 'Toffee Movies');
    });
  });

  group('IPTV Hive Persistence & Riverpod Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_iptv_unit_');
      Hive.init(tempDir.path);
      await Hive.openBox(AppConstants.settingsBox);
      await Hive.openBox(AppConstants.favoritesBox);
      await Hive.openBox('iptv_playlists');
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('IptvService & Notifiers persist global settings, view configs & bookmarks to Hive', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(iptvSettingsProvider.notifier).toggleSortCategoriesByCount(true);
      await container.read(iptvSettingsProvider.notifier).setBackgroundMode(
            IptvBackgroundMode.animated,
          );
      await container.read(iptvViewConfigsProvider.notifier).setConfig(
            'pl_1',
            const IptvViewConfig(mode: IptvDisplayMode.poster, spanCount: 3, posterRatioIndex: 7),
          );
      await container.read(iptvBookmarksProvider.notifier).saveBookmark(
            channel: Channel(id: 'bm_1', name: 'HBO HD', streamUrl: 'https://ex/hbo.m3u8'),
            playlistId: 'pl_1',
            playlistName: 'Movies Pack',
            categories: ['Movies'],
          );

      final freshService = IptvService();
      expect(freshService.loadGlobalSettings().sortCategoriesByCount, isTrue);
      expect(freshService.loadGlobalSettings().backgroundMode, IptvBackgroundMode.animated);
      expect(freshService.loadViewConfigs()['pl_1']?.mode, IptvDisplayMode.poster);
      expect(freshService.loadViewConfigs()['pl_1']?.posterRatioIndex, 7);
      expect(freshService.loadBookmarks()['bm_1']?.channel.name, 'HBO HD');
      expect(freshService.loadBookmarks()['bm_1']?.categories, containsAll(['Movies', 'All']));
    });
  });

  group('IPTV UI Widget Tests', () {
    testWidgets('IptvScreen omits duplicate Bookmark/Home/Local bottom navigation bar & sorts playlists', (tester) async {
      final samplePlaylists = [
        IptvPlaylist(
          id: 'pl_z',
          name: 'Zulu',
          sourceType: IptvSourceType.m3uUrl,
          url: 'https://example.com/z.m3u',
          addedAt: DateTime.now(),
          lastSync: DateTime.now(),
          channelCount: 5,
        ),
        IptvPlaylist(
          id: 'pl_a',
          name: 'Alpha',
          sourceType: IptvSourceType.m3uUrl,
          url: 'https://example.com/a.m3u',
          addedAt: DateTime.now(),
          lastSync: DateTime.now(),
          channelCount: 25,
        ),
      ];
      final memService = _MemoryIptvService(samplePlaylists);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iptvServiceProvider.overrideWithValue(memService),
          ],
          child: const MaterialApp(
            home: IptvScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('IPTV.'), findsOneWidget);
      expect(find.text('Zulu'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.textContaining('•  25 ch'), findsOneWidget);
      expect(find.textContaining('•  5 ch'), findsOneWidget);
      // Verify the rejected 2nd bottom navigation bar ("Bookmark" / "Local") is absent
      expect(find.text('Bookmark'), findsNothing);
      expect(find.text('Local'), findsNothing);

      // Verify Sort & Bookmarks modal works
      await tester.tap(find.byTooltip('Sort & Filter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Sort by Name (A-Z)'), findsOneWidget);
      expect(find.text('Sort by Channel Count (High-Low)'), findsOneWidget);
      expect(find.text('Saved Channel Bookmarks (0)'), findsOneWidget);
    });

    testWidgets('IptvChannelBrowserSheet displays tabs, verbatim HD titles, search, view modes & bookmarks', (tester) async {
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final memService = _MemoryIptvService();
      final playlist = IptvPlaylist(
        id: 'toffee_pl',
        name: 'toffee',
        sourceType: IptvSourceType.m3uUrl,
        url: 'https://example.com/toffee.m3u',
        addedAt: DateTime.now(),
        lastSync: DateTime.now(),
        channelCount: 4,
        channels: [
          Channel(id: 'ch_1', name: 'Toffee TV', streamUrl: 'https://ex/1.m3u8', category: 'Family'),
          Channel(id: 'ch_2', name: 'Sony MAX HD', streamUrl: 'https://ex/2.m3u8', category: 'Movies'),
          Channel(id: 'ch_3', name: 'Zee Cinema', streamUrl: 'https://ex/3.m3u8', category: 'Movies'),
          Channel(id: 'ch_4', name: 'Cricket Sports', streamUrl: 'https://ex/4.m3u8', category: 'Sports'),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            iptvServiceProvider.overrideWithValue(memService),
          ],
          child: MaterialApp(
            home: IptvChannelBrowserSheet(playlist: playlist),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('toffee'), findsOneWidget);
      expect(find.text('All (4)'), findsOneWidget);
      expect(find.text('Family (1)'), findsOneWidget);
      expect(find.text('Movies (2)'), findsOneWidget);
      expect(find.text('Sports (1)'), findsOneWidget);

      // Channel title preserves "HD" verbatim and shows clean APK "No TV guide available | Group"
      expect(find.text('Sony MAX HD'), findsOneWidget);
      expect(find.text('No TV guide available | Movies'), findsWidgets);

      // Test 300ms debounced title search
      await tester.tap(find.byTooltip('Search channels'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Sony');
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Sony MAX HD'), findsOneWidget);
      expect(find.text('Toffee TV'), findsNothing);

      // Clear search
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Toffee TV'), findsOneWidget);

      // Open TabJump sheet
      await tester.tap(find.byTooltip('Category tabs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Categories'), findsOneWidget);
      await tester.tap(find.text('Sports').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Open View Settings sheet & switch to List mode -> reveals info icon
      await tester.tap(find.byTooltip('View settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(IptvViewSettingsSheet), findsOneWidget);
      await tester.tap(find.text('List'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Close bottom sheet
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byTooltip('Channel info'), findsWidgets);

      // Long press channel opens EPG/Channel Details bottom sheet
      await tester.longPress(find.text('Cricket Sports'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('COPY URL'), findsOneWidget);
      expect(find.text('PLAY NOW'), findsOneWidget);

      // Close EPG sheet and test heart bookmark -> CategorySelectorDialog persistence
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byWidgetPredicate((w) => w is IptvSvgIcon && (w.icon == IptvSvgIcons.heart || w.icon == IptvSvgIcons.heartFilled)).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remember my choice next time'), findsOneWidget);
      expect(find.text('CONFIRM'), findsOneWidget);
      await tester.tap(find.text('CONFIRM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(memService.loadBookmarks().containsKey('ch_4'), isTrue);
      expect(find.textContaining('Saved "Cricket Sports"'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
      'IptvScreen renders empty state on narrow 320px/360px widths with zero overflow',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        for (final width in [360.0, 320.0]) {
          tester.view.physicalSize = Size(width, 720);
          final memService = _MemoryIptvService();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                iptvServiceProvider.overrideWithValue(memService),
              ],
              child: const MaterialApp(home: IptvScreen()),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('IPTV.'), findsOneWidget);
          expect(find.text('LOAD SAMPLE PLAYLIST'), findsOneWidget);
          expect(find.text('ADD NEW CONTENT'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'IptvScreen supports Guide sheet, Manage TV Guide (EPG), Multi-Select batch delete, Sort menu & cross-playlist search',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(412, 860);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final p1 = IptvPlaylist(
          id: 'pl_1',
          name: 'Toffee Live',
          sourceType: IptvSourceType.m3uUrl,
          url: 'https://example.com/toffee.m3u',
          addedAt: DateTime(2026, 11, 24),
          channelCount: 2,
          channels: [
            Channel(
              id: 'ch_a',
              name: 'Toffee TV',
              streamUrl: 'https://ex/a.m3u8',
              category: 'Family',
            ),
            Channel(
              id: 'ch_b',
              name: 'Sony MAX HD',
              streamUrl: 'https://ex/b.m3u8',
              category: 'Movies',
            ),
          ],
        );
        final p2 = IptvPlaylist(
          id: 'pl_2',
          name: 'Sports Hub',
          sourceType: IptvSourceType.m3uUrl,
          url: 'https://example.com/sports.m3u',
          addedAt: DateTime(2026, 11, 25),
          channelCount: 1,
          channels: [
            Channel(
              id: 'ch_c',
              name: 'T Sports HD',
              streamUrl: 'https://ex/c.m3u8',
              category: 'Sports',
            ),
          ],
        );

        final memService = _MemoryIptvService([p1, p2]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iptvServiceProvider.overrideWithValue(memService),
            ],
            child: const MaterialApp(home: IptvScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Guide sheet (?)
        await tester.tap(find.byTooltip('IPTV Guide'));
        await tester.pumpAndSettle();
        expect(find.byType(IptvGuideSheet), findsOneWidget);
        expect(find.text('How to Add a Playlist to Your IPTV App'), findsOneWidget);
        await tester.tap(find.text('Network & DRM'));
        await tester.pumpAndSettle();
        expect(find.text('How to Add a Video to Your Network Stream'), findsOneWidget);
        await tester.tap(find.text('GOT IT'));
        await tester.pumpAndSettle();

        // 2. Manage TV Guide (EPG) sheet + Add EPG Link dialog
        await tester.tap(find.byTooltip('Manage TV Guide'));
        await tester.pumpAndSettle();
        expect(find.byType(IptvManageEpgSheet), findsOneWidget);
        await tester.tap(find.text('ADD EPG LINK'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Any name (e.g. Global TV Guide)'),
          'My Guide',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Enter EPG URL (.xml / .xml.gz)'),
          'https://example.com/epg.xml',
        );
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();
        expect(memService.loadSavedEpgSources().length, 1);
        expect(find.text('My Guide'), findsOneWidget);
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        // 3. (+) Add menu shows 6 APK options including Add Teleguide EPG
        await tester.tap(find.byWidgetPredicate((w) => w is IptvSvgIcon && w.icon == IptvSvgIcons.plus));
        await tester.pumpAndSettle();
        expect(find.byType(IptvAddMenuSheet), findsOneWidget);
        expect(find.text('Add Teleguide EPG (XML)'), findsOneWidget);
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        // 4. Sort & Filter dialog shows APK tip & Newest first option
        await tester.tap(find.byTooltip('Sort & Filter'));
        await tester.pumpAndSettle();
        expect(
          find.text('Tips: Long press and drag the dots icon to reorder items.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Sort by Date (Newest first)'));
        await tester.pumpAndSettle();

        // 5. Cross-playlist channel search
        await tester.tap(find.byTooltip('Search playlists & channels'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Sony');
        await tester.pumpAndSettle();
        expect(find.text('Matching Channels (1)'), findsOneWidget);
        expect(find.text('Sony MAX HD'), findsOneWidget);
        await tester.tap(find.byTooltip('Close search'));
        await tester.pumpAndSettle();

        // 6. Multi-Select mode + batch delete
        await tester.tap(find.byTooltip('Select playlists'));
        await tester.pumpAndSettle();
        expect(find.text('0 Selected'), findsOneWidget);
        await tester.tap(find.text('Sports Hub'));
        await tester.pumpAndSettle();
        expect(find.text('1 Selected'), findsOneWidget);
        await tester.tap(find.text('DELETE (1)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DELETE'));
        await tester.pumpAndSettle();
        expect(find.text('Sports Hub'), findsNothing);
        expect(find.text('Toffee Live'), findsOneWidget);
      },
    );

    testWidgets(
      'IptvScreen renders clean borderless solid playlist cards without StretchingOverscrollIndicator during pull-to-refresh',
      (tester) async {
        tester.view.physicalSize = const Size(411, 891);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final memService = _MemoryIptvService([
          IptvPlaylist(
            id: 'pl_blur_1',
            name: 'Solid Card 1',
            sourceType: IptvSourceType.m3uUrl,
            url: 'https://example.com/1.m3u',
            addedAt: DateTime.now(),
            lastSync: DateTime.now(),
            channelCount: 12,
          ),
        ]);
        await memService.saveGlobalSettings(
          const IptvGlobalSettings(backgroundMode: IptvBackgroundMode.animated),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iptvServiceProvider.overrideWithValue(memService),
            ],
            child: const MaterialApp(
              home: IptvScreen(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Solid Card 1'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(StretchingOverscrollIndicator), findsNothing);
        expect(find.byType(GlowingOverscrollIndicator), findsNothing);

        // Simulate pulling down to arm RefreshIndicator
        final gesture = await tester.startGesture(const Offset(200, 350));
        await gesture.moveBy(const Offset(0, 220));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        expect(find.byType(StretchingOverscrollIndicator), findsNothing);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  });

  group('Add Content Workflows (APK Feature Parity)', () {
    test('IptvPlaylist serializes Add Content metadata fields cleanly', () {
      final pl = IptvPlaylist(
        id: 'pl_meta_1',
        name: 'DRM Test',
        sourceType: IptvSourceType.directStream,
        url: 'https://cdn.example.com/stream.mpd',
        authorization: 'Bearer tok_123',
        requestType: 'post',
        subtitleUrl: 'https://cdn.example.com/subs.vtt',
        streamFormat: 'HLS',
        parserType: 'm3u_plus',
        stalkerToken: 'STK_1',
        stalkerExpiry: '2028-01-01',
        addedAt: DateTime(2026, 11, 25),
      );
      final restored = IptvPlaylist.fromJson(pl.toJson());
      expect(restored.authorization, 'Bearer tok_123');
      expect(restored.requestType, 'post');
      expect(restored.subtitleUrl, 'https://cdn.example.com/subs.vtt');
      expect(restored.streamFormat, 'HLS');
      expect(restored.parserType, 'm3u_plus');
      expect(restored.stalkerToken, 'STK_1');
      expect(restored.stalkerExpiry, '2028-01-01');
    });

    test('iptv_add_helpers parse URL schemes, ?title=, video extensions & extra headers', () {
      expect(isSupportedIptvScheme('rtsp://10.0.0.1:554/live'), isTrue);
      expect(isSupportedIptvScheme('srt://ingest.example.com:9000'), isTrue);
      expect(isSupportedIptvScheme('not-a-valid-scheme'), isFalse);

      expect(looksLikeDirectVideoUrl('https://cdn.example.com/film.mp4?token=1'), isTrue);
      expect(looksLikeDirectVideoUrl('https://cdn.example.com/list.m3u8'), isFalse);

      expect(
        extractTitleQueryParam('https://cdn.example.com/live.m3u8?title=Match%20Feed'),
        'Match Feed',
      );
      expect(
        inferPlaylistNameFromUrl('https://cdn.example.com/channels.m3u8'),
        'channels',
      );

      final parsedJson = parseExtraHeadersInput('{"X-Api-Key": "k1", "X-Geo": "US"}');
      expect(parsedJson, {'X-Api-Key': 'k1', 'X-Geo': 'US'});
      final parsedLines = parseExtraHeadersInput('X-One: v1\nX-Two: v2');
      expect(parsedLines, {'X-One': 'v1', 'X-Two': 'v2'});
    });

    testWidgets(
      'Network Video Stream supports ?title= auto-fill, MIME probe, User-Agent picker & Extra Headers modal',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        final memService = _MemoryIptvService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iptvServiceProvider.overrideWithValue(memService),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => IptvAddSourceDialog.show(
                        context,
                        initialType: IptvSourceType.directStream,
                      ),
                      child: const Text('OPEN DIALOG'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OPEN DIALOG'));
        await tester.pumpAndSettle();

        expect(find.text('Network Video Stream'), findsOneWidget);
        expect(find.text('Subtitle URL (optional)'), findsOneWidget);

        // Enter URL with ?title= param & .m3u8 to trigger title extraction + debounced MIME probe
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Media Stream URL'),
          'https://cdn.example.com/live/feed.m3u8?title=Premier%20Feed',
        );
        await tester.pump(const Duration(milliseconds: 550));
        await tester.pumpAndSettle();

        expect(find.text('> Mime Type: application/vnd.apple.mpegurl'), findsOneWidget);

        // Select Cloudflare DoH preset chip
        await tester.ensureVisible(find.text('Cloudflare'));
        await tester.tap(find.text('Cloudflare'));
        await tester.pumpAndSettle();

        // Enter Subtitle URL
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Subtitle URL (optional)'),
          'https://cdn.example.com/subs.vtt',
        );

        // Expand More Options -> pick User-Agent preset & edit Extra Headers table
        await tester.ensureVisible(find.text('More Options'));
        await tester.tap(find.text('More Options'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Authorization (optional)'),
          'Bearer token_xyz',
        );

        await tester.ensureVisible(find.byTooltip('Choose User-Agent Preset'));
        await tester.tap(find.byTooltip('Choose User-Agent Preset'));
        await tester.pumpAndSettle();
        expect(find.text('Select User-Agent'), findsOneWidget);
        await tester.tap(find.text('TiviMate'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byTooltip('Manage Extra Headers'));
        await tester.tap(find.byTooltip('Manage Extra Headers'));
        await tester.pumpAndSettle();
        expect(find.text('Manage Extra Header'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'X-Custom-Header'), 'X-Device-Id');
        await tester.enterText(find.widgetWithText(TextField, 'Value'), 'dev42');
        await tester.tap(find.text('SAVE').last);
        await tester.pumpAndSettle();

        // Submit outer dialog
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        final savedList = await memService.getSavedPlaylists();
        expect(savedList.length, 1);
        final saved = savedList.first;
        expect(saved.name, 'Premier Feed');
        expect(saved.dohEndpoint, 'https://cloudflare-dns.com/dns-query');
        expect(saved.subtitleUrl, 'https://cdn.example.com/subs.vtt');
        expect(saved.authorization, 'Bearer token_xyz');
        expect(saved.userAgent, contains('TiviMate'));
        expect(saved.headers['X-Device-Id'], 'dev42');
      },
    );

    testWidgets(
      'Playlist Link detects direct video URL & switches cleanly to Video Link mode',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iptvServiceProvider.overrideWithValue(_MemoryIptvService()),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => IptvAddSourceDialog.show(
                      context,
                      initialType: IptvSourceType.m3uUrl,
                    ),
                    child: const Text('OPEN M3U'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OPEN M3U'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Playlist URL'),
          'https://cdn.example.com/movie.mp4',
        );
        await tester.pump(const Duration(milliseconds: 550));
        await tester.pumpAndSettle();

        expect(
          find.text('This looks like a direct video URL — switch to Video Link?'),
          findsOneWidget,
        );
        await tester.tap(find.text('SWITCH'));
        await tester.pumpAndSettle();
        expect(find.text('Network Video Stream'), findsOneWidget);
      },
    );

    testWidgets(
      'Xtream Codes Api and STB/Stalker forms expose APK controls and persist metadata',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);

        final memService = _MemoryIptvService();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              iptvServiceProvider.overrideWithValue(memService),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => IptvAddSourceDialog.show(
                          context,
                          initialType: IptvSourceType.xtream,
                        ),
                        child: const Text('OPEN XTREAM'),
                      ),
                      ElevatedButton(
                        onPressed: () => IptvAddSourceDialog.show(
                          context,
                          initialType: IptvSourceType.stalker,
                        ),
                        child: const Text('OPEN STALKER'),
                      ),
                      ElevatedButton(
                        onPressed: () => IptvAddSourceDialog.show(
                          context,
                          initialType: IptvSourceType.m3uFile,
                        ),
                        child: const Text('OPEN LOCAL'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Xtream Codes Api
        await tester.tap(find.text('OPEN XTREAM'));
        await tester.pumpAndSettle();
        expect(find.text('Xtream Codes Api'), findsOneWidget);
        expect(find.text('Stream Format'), findsOneWidget);
        expect(find.text('Parser Type'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Host URL'),
          'http://xtream.example.com:8080',
        );
        await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'demo_user');
        await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'demo_pass');

        // Change Stream Format -> HLS
        await tester.tap(find.text('TS'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HLS').last);
        await tester.pumpAndSettle();

        // Change Parser Type -> m3u_plus
        await tester.tap(find.text('API Codes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('m3u_plus').last);
        await tester.pumpAndSettle();

        // Toggle Import series off
        await tester.tap(find.text('Import series'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        var savedList = await memService.getSavedPlaylists();
        final xtreamSaved = savedList.firstWhere((p) => p.sourceType == IptvSourceType.xtream);
        expect(xtreamSaved.streamFormat, 'HLS');
        expect(xtreamSaved.parserType, 'm3u_plus');
        expect(xtreamSaved.importSeries, isFalse);

        // 2. STB / Stalker / MAC Portal + live TEST CONNECTION
        await tester.tap(find.text('OPEN STALKER'));
        await tester.pumpAndSettle();
        expect(find.text('STB / Stalker / MAC Portal'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Server Address / Portal URL'),
          'http://portal.example.com/c/',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'MAC Address'),
          '00-1a-79-11-22-33',
        );
        await tester.tap(find.text('TEST CONNECTION'));
        await tester.pumpAndSettle();

        expect(find.text('STALKER_TOK_99'), findsOneWidget);
        expect(find.text('2027-12-31'), findsOneWidget);

        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        savedList = await memService.getSavedPlaylists();
        final stalkerSaved = savedList.firstWhere((p) => p.sourceType == IptvSourceType.stalker);
        expect(stalkerSaved.macAddress, '00:1A:79:11:22:33');
        expect(stalkerSaved.stalkerToken, 'STALKER_TOK_99');
        expect(stalkerSaved.stalkerExpiry, '2027-12-31');

        // 3. Local Playlist (M3U/JSON)
        await tester.tap(find.text('OPEN LOCAL'));
        await tester.pumpAndSettle();
        expect(find.text('BROWSE DEVICE FILE (.M3U / .JSON)'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Playlist Name'),
          'Local Bundle',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'File Path or Raw M3U / JSON Content'),
          '#EXTM3U\n#EXTINF:-1,Local TV\nhttps://example.com/local.m3u8',
        );
        await tester.tap(find.text('SAVE'));
        await tester.pumpAndSettle();

        savedList = await memService.getSavedPlaylists();
        expect(savedList.any((p) => p.sourceType == IptvSourceType.m3uFile && p.name == 'Local Bundle'), isTrue);
      },
    );
  });
}
