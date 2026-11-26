import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:goplay/models/category.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/providers/app_providers.dart';
import 'package:goplay/providers/playz_providers.dart';
import 'package:goplay/services/cache_service.dart';
import 'package:goplay/services/category_m3u_service.dart';
import 'package:goplay/services/channel_stream_launcher.dart';
import 'package:goplay/services/supabase_service.dart';
import 'package:goplay/widgets/category_m3u_auto_sync_observer.dart';

enum _PlaylistMode { initial, notModified, sameBody, rotatedDrm, updated }

class _StubSupabaseService extends SupabaseService {
  _StubSupabaseService({
    this.channelsVersion = 1,
    this.categories = const [],
    this.channels = const [],
  });

  int channelsVersion;
  List<Category> categories;
  List<Channel> channels;

  int getSyncVersionsCalls = 0;
  int getCategoriesCalls = 0;
  int getChannelsCalls = 0;

  @override
  Future<Map<String, dynamic>?> getSyncVersions() async {
    getSyncVersionsCalls++;
    return {
      'channels_version': channelsVersion,
      'events_version': 1,
      'ui_config_version': 1,
    };
  }

  @override
  Future<List<Category>> getCategories() async {
    getCategoriesCalls++;
    return categories;
  }

  @override
  Future<List<Channel>> getChannels({bool onlyLive = true}) async {
    getChannelsCalls++;
    return channels;
  }

  @override
  Future<List<Channel>> getChannelsByCategory(
    String categoryId, {
    bool onlyLive = true,
  }) async {
    return channels.where((c) => c.category == categoryId).toList();
  }
}

void main() {
  group('Ticket 02: Local M3U Cache & Whole-App Unification', () {
    test('CacheService stores, memoizes, and clears category M3U channels and metadata', () async {
      final cache = CacheService();
      final channel = Channel(
        id: 'm3u_sports_tsports',
        name: 'T Sports',
        category: 'sports',
        streamUrl: 'https://cdn.test/ts.m3u8',
      );
      final meta = CategoryM3uMeta(
        m3uUrl: 'https://m3u.test/sports.m3u',
        etag: '"v1"',
        contentHash: '12:abc',
        lastSyncedAt: DateTime.utc(2026, 11, 26, 12),
      );

      await cache.saveCategoryM3uChannels('sports', [channel]);
      await cache.saveCategoryM3uMeta('sports', meta);

      expect(cache.getCategoryM3uChannels('sports'), hasLength(1));
      expect(cache.getCategoryM3uMeta('sports')?.m3uUrl, 'https://m3u.test/sports.m3u');
      expect(cache.getCachedM3uCategoryIds(), contains('sports'));
      expect(cache.hasAnyLocalChannelData(), isFalse); // No local category registered yet

      await cache.saveLocalCategories([
        const Category(
          id: 'sports',
          name: 'Sports',
          m3uUrl: 'https://m3u.test/sports.m3u',
          active: true,
        ),
      ]);
      expect(cache.hasAnyLocalChannelData(), isTrue);

      await cache.clearCategoryM3uData('sports');
      expect(cache.getCategoryM3uChannels('sports'), isEmpty);
      expect(cache.getCategoryM3uMeta('sports'), isNull);
    });

    test('rawChannelsProvider replaces DB channels for M3U categories regardless of type=custom', () async {
      final cache = CacheService();
      await cache.saveLocalCategories([
        const Category(
          id: 'sports',
          name: 'Sports',
          type: 'custom', // Even if admin did not flip type to 'm3u'
          m3uUrl: 'https://m3u.test/sports.m3u',
          sortOrder: 0,
          active: true,
        ),
        const Category(
          id: 'news',
          name: 'News',
          type: 'custom',
          sortOrder: 1,
          active: true,
        ),
      ]);
      await cache.saveLocalChannels([
        Channel(
          id: 'db_old_sports',
          name: 'Old DB Sports',
          category: 'sports',
          streamUrl: 'https://db.test/old.m3u8',
        ),
        Channel(
          id: 'db_news',
          name: 'DB News 24',
          category: 'news',
          streamUrl: 'https://db.test/news.m3u8',
        ),
      ]);
      await cache.saveCategoryM3uChannels('sports', [
        Channel(
          id: 'm3u_sports_live',
          name: 'M3U Live Sports',
          category: 'sports',
          streamUrl: 'https://m3u.test/live.m3u8',
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          supabaseServiceProvider.overrideWithValue(_StubSupabaseService()),
        ],
      );
      addTearDown(container.dispose);

      final channels = await container.read(channelsProvider.future);
      expect(channels.map((c) => c.id), containsAll(['m3u_sports_live', 'db_news']));
      expect(channels.map((c) => c.id), isNot(contains('db_old_sports')));

      final grouped = container.read(channelsByCategoryMapProvider).requireValue;
      expect(grouped['sports']?.single.name, 'M3U Live Sports');
      expect(grouped['news']?.single.name, 'DB News 24');

      final counts = container.read(activeCategoriesWithCountsProvider).requireValue;
      expect(counts.map((e) => (e.$1.id, e.$2)), [('sports', 1), ('news', 1)]);

      final searchHits = await container.read(filteredChannelsProvider('M3U Live').future);
      expect(searchHits.single.id, 'm3u_sports_live');
    });

    test('favorites survive M3U channel updates via unified rawChannelsProvider', () async {
      final cache = CacheService();
      await cache.saveLocalCategories([
        const Category(
          id: 'bangla',
          name: 'Bangla',
          type: 'm3u',
          m3uUrl: 'https://m3u.test/bangla.m3u',
          active: true,
        ),
      ]);
      await cache.saveCategoryM3uChannels('bangla', [
        Channel(
          id: 'm3u_bangla_somoy_tv',
          name: 'Somoy TV',
          category: 'bangla',
          streamUrl: 'https://m3u.test/somoy.m3u8',
        ),
      ]);
      await cache.saveFavoriteChannelIds({'m3u_bangla_somoy_tv'});

      final container = ProviderContainer(
        overrides: [cacheServiceProvider.overrideWithValue(cache)],
      );
      addTearDown(container.dispose);

      await container.read(rawChannelsProvider.future);
      final favs = container.read(favoriteChannelsProvider).requireValue;
      expect(favs.single.id, 'm3u_bangla_somoy_tv');

      final lookedUp = await container.read(channelProvider('m3u_bangla_somoy_tv').future);
      expect(lookedUp?.name, 'Somoy TV');
    });

    test('playzCategoryChannelsProvider fetches M3U when cache is empty and preserves cache on offline failure', () async {
      final cache = CacheService();
      const sportsCat = Category(
        id: 'sports',
        name: 'Sports',
        type: 'm3u',
        m3uUrl: 'https://m3u.test/sports.m3u',
        active: true,
      );
      await cache.saveLocalCategories([sportsCat]);

      var shouldFail = false;
      final syncService = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          if (shouldFail) throw Exception('Offline');
          return const CategoryM3uHttpResponse(
            statusCode: 200,
            body: '''
#EXTM3U
#EXTINF:-1,Star Sports 1
https://cdn.test/ss1_a.m3u8
#EXTINF:-1,Star Sports 1
https://cdn.test/ss1_b.m3u8
''',
          );
        },
      );

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          categoryM3uSyncServiceProvider.overrideWithValue(syncService),
          supabaseServiceProvider.overrideWithValue(_StubSupabaseService()),
        ],
      );
      addTearDown(container.dispose);

      final loaded = await container.read(playzCategoryChannelsProvider(sportsCat).future);
      expect(loaded, hasLength(1));
      expect(loaded.single.streamServers, hasLength(2));
      expect(cache.getCategoryM3uChannels('sports'), hasLength(1));

      // Offline error on subsequent refresh must keep cached channels intact
      shouldFail = true;
      final refreshed = await syncService.syncCategory(sportsCat, force: true);
      expect(refreshed, isFalse);
      expect(cache.getCategoryM3uChannels('sports'), hasLength(1));
    });
  });

  group('Ticket 03: Minimal-DB Admin m3u_url Change Detection', () {
    test('skips Supabase categories/channels queries when channels_version is unchanged and refreshes saved M3U URL', () async {
      final cache = CacheService();
      const sportsCat = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/sports_v1.m3u',
        active: true,
      );
      await cache.saveLocalCategories([sportsCat]);
      await cache.saveLocalChannelsVersion(5);

      final supabase = _StubSupabaseService(
        channelsVersion: 5,
        categories: [sportsCat],
      );

      var m3uFetches = 0;
      final m3uSync = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          m3uFetches++;
          return const CategoryM3uHttpResponse(
            statusCode: 200,
            body: '#EXTM3U\n#EXTINF:-1,Direct Channel\nhttps://cdn.test/direct.m3u8\n',
          );
        },
      );

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          supabaseServiceProvider.overrideWithValue(supabase),
          categoryM3uSyncServiceProvider.overrideWithValue(m3uSync),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncServiceProvider).sync();

      expect(supabase.getSyncVersionsCalls, 1);
      expect(supabase.getCategoriesCalls, 0);
      expect(supabase.getChannelsCalls, 0);
      expect(m3uFetches, 1);
      final channels = await container.read(channelsProvider.future);
      expect(channels.single.name, 'Direct Channel');
    });

    test('detects admin m3u_url change and clearing when channels_version increments', () async {
      final cache = CacheService();
      const oldSports = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/old.m3u',
        active: true,
      );
      await cache.saveLocalCategories([oldSports]);
      await cache.saveLocalChannelsVersion(5);
      await cache.saveCategoryM3uChannels('sports', [
        Channel(
          id: 'm3u_sports_old',
          name: 'Old M3U',
          category: 'sports',
          streamUrl: 'https://cdn.test/old.m3u8',
        ),
      ]);
      await cache.saveCategoryM3uMeta(
        'sports',
        const CategoryM3uMeta(m3uUrl: 'https://m3u.test/old.m3u'),
      );

      const newSports = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/new.m3u',
        active: true,
      );
      final supabase = _StubSupabaseService(
        channelsVersion: 6,
        categories: [newSports],
        channels: [
          Channel(
            id: 'db_sports_fallback',
            name: 'DB Fallback',
            category: 'sports',
            streamUrl: 'https://db.test/fallback.m3u8',
          ),
        ],
      );

      final fetchedUrls = <String>[];
      final m3uSync = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          fetchedUrls.add(url);
          return const CategoryM3uHttpResponse(
            statusCode: 200,
            body: '#EXTM3U\n#EXTINF:-1,New M3U Channel\nhttps://cdn.test/new.m3u8\n',
          );
        },
      );

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          supabaseServiceProvider.overrideWithValue(supabase),
          categoryM3uSyncServiceProvider.overrideWithValue(m3uSync),
        ],
      );
      addTearDown(container.dispose);

      final changed = await container
          .read(syncServiceProvider)
          .checkForCategoryChangesIfDue(cooldown: Duration.zero);

      expect(changed, isTrue);
      expect(fetchedUrls, ['https://m3u.test/new.m3u']);
      expect(cache.getCategoryM3uMeta('sports')?.m3uUrl, 'https://m3u.test/new.m3u');
      expect((await container.read(channelsProvider.future)).single.name, 'New M3U Channel');

      // Now admin clears m3u_url (version 7): M3U cache clears and DB channels take over
      supabase.channelsVersion = 7;
      supabase.categories = [
        const Category(id: 'sports', name: 'Sports', m3uUrl: null, active: true),
      ];

      await container
          .read(syncServiceProvider)
          .checkForCategoryChangesIfDue(cooldown: Duration.zero);

      expect(cache.getCategoryM3uChannels('sports'), isEmpty);
      expect(cache.getCategoryM3uMeta('sports'), isNull);
      expect((await container.read(channelsProvider.future)).single.name, 'DB Fallback');
    });
  });

  group('Ticket 04: Continuous Direct M3U Sync & Conditional Diffing', () {
    test('uses ETag / Last-Modified and content hash to skip re-parsing unchanged playlists and updates live on DRM/channel change', () async {
      final cache = CacheService();
      const sportsCat = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/live.m3u',
        active: true,
      );
      await cache.saveLocalCategories([sportsCat]);

      var mode = _PlaylistMode.initial;
      String? seenIfNoneMatch;
      String? seenIfModifiedSince;
      final supabase = _StubSupabaseService();

      final m3uSync = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          seenIfNoneMatch = ifNoneMatch;
          seenIfModifiedSince = ifModifiedSince;
          switch (mode) {
            case _PlaylistMode.initial:
              return const CategoryM3uHttpResponse(
                statusCode: 200,
                etag: '"etag-1"',
                lastModified: 'Thu, 26 Nov 2026 10:00:00 GMT',
                body:
                    '#EXTM3U\n#EXTINF:-1,Channel One\n#KODIPROP:inputstream.adaptive.license_type=clearkey\n#KODIPROP:inputstream.adaptive.license_key=00112233445566778899aabbccddeeff:11111111111111111111111111111111\nhttps://cdn.test/1.mpd\n',
              );
            case _PlaylistMode.notModified:
              return const CategoryM3uHttpResponse(statusCode: 304);
            case _PlaylistMode.sameBody:
              return const CategoryM3uHttpResponse(
                statusCode: 200,
                etag: '"etag-1b"',
                body:
                    '#EXTM3U\n#EXTINF:-1,Channel One\n#KODIPROP:inputstream.adaptive.license_type=clearkey\n#KODIPROP:inputstream.adaptive.license_key=00112233445566778899aabbccddeeff:11111111111111111111111111111111\nhttps://cdn.test/1.mpd\n',
              );
            case _PlaylistMode.rotatedDrm:
              return const CategoryM3uHttpResponse(
                statusCode: 200,
                etag: '"etag-drm"',
                body:
                    '#EXTM3U\n#EXTINF:-1,Channel One\n#KODIPROP:inputstream.adaptive.license_type=clearkey\n#KODIPROP:inputstream.adaptive.license_key=00112233445566778899aabbccddeeff:22222222222222222222222222222222\nhttps://cdn.test/1.mpd\n',
              );
            case _PlaylistMode.updated:
              return const CategoryM3uHttpResponse(
                statusCode: 200,
                etag: '"etag-2"',
                body:
                    '#EXTM3U\n#EXTINF:-1,Channel One\nhttps://cdn.test/1_v2.m3u8\n#EXTINF:-1,Channel Two\nhttps://cdn.test/2.m3u8\n',
              );
          }
        },
      );

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          supabaseServiceProvider.overrideWithValue(supabase),
          categoryM3uSyncServiceProvider.overrideWithValue(m3uSync),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial direct fetch (0 Supabase DB calls)
      expect(await container.read(syncServiceProvider).refreshM3uDirectly(), isTrue);
      expect(supabase.getSyncVersionsCalls, 0);
      expect((await container.read(channelsProvider.future)).length, 1);

      // 2. 304 Not Modified sends conditional headers and skips UI update
      mode = _PlaylistMode.notModified;
      expect(await container.read(syncServiceProvider).refreshM3uDirectly(), isFalse);
      expect(seenIfNoneMatch, '"etag-1"');
      expect(seenIfModifiedSince, 'Thu, 26 Nov 2026 10:00:00 GMT');

      // 3. 200 with identical body skips UI update via content hash
      mode = _PlaylistMode.sameBody;
      expect(await container.read(syncServiceProvider).refreshM3uDirectly(), isFalse);

      // 4. Rotated ClearKey with identical URL still triggers live update
      mode = _PlaylistMode.rotatedDrm;
      expect(await container.read(syncServiceProvider).refreshM3uDirectly(), isTrue);
      expect(
        (await container.read(channelsProvider.future)).single.drm?.key,
        '22222222222222222222222222222222',
      );

      // 5. Updated playlist adds new channel and updates live provider
      mode = _PlaylistMode.updated;
      expect(await container.read(syncServiceProvider).refreshM3uDirectly(), isTrue);
      final updatedChannels = await container.read(channelsProvider.future);
      expect(updatedChannels.map((c) => c.name), ['Channel One', 'Channel Two']);
      expect(updatedChannels.first.streamUrl, 'https://cdn.test/1_v2.m3u8');
      expect(supabase.getSyncVersionsCalls, 0);
    });

    test('coalesces concurrent syncCategory calls regardless of force flag', () async {
      final cache = CacheService();
      const cat = Category(
        id: 'bangla',
        name: 'Bangla',
        m3uUrl: 'https://m3u.test/bangla.m3u',
        active: true,
      );
      var fetchCount = 0;

      final m3uSync = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          fetchCount++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const CategoryM3uHttpResponse(
            statusCode: 200,
            body: '#EXTM3U\n#EXTINF:-1,BTV\nhttps://cdn.test/btv.m3u8\n',
          );
        },
      );

      final results = await Future.wait([
        m3uSync.syncCategory(cat, force: false),
        m3uSync.syncCategory(cat, force: true),
        m3uSync.syncCategory(cat, force: false),
      ]);

      expect(fetchCount, 1);
      expect(results, [true, true, true]);
    });

    testWidgets('ChannelStreamLauncher passes multi-server M3U dynamicChannels into player route', (tester) async {
      final parsed = parseCategoryM3uContent(
        '''
#EXTM3U
#EXTINF:-1,Star Sports 1
https://cdn.test/ss1_a.m3u8
#EXTINF:-1,Star Sports 1
https://cdn.test/ss1_b.m3u8
''',
        'sports',
      );
      final multiServerChannel = parsed.single;
      Map<String, dynamic>? capturedExtra;
      String? capturedLocation;

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ChannelStreamLauncher.launch(
                  context,
                  multiServerChannel,
                  scope: parsed,
                ),
                child: const Text('Play'),
              ),
            ),
          ),
          GoRoute(
            path: '/player/:channelId',
            builder: (context, state) {
              capturedLocation = state.matchedLocation;
              capturedExtra = state.extra as Map<String, dynamic>?;
              return const Scaffold(body: Text('Player'));
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(capturedLocation, '/player/${multiServerChannel.id}');
      final dynamicChannels = capturedExtra?['dynamicChannels'] as List<Channel>?;
      expect(dynamicChannels, hasLength(2));
      expect(dynamicChannels!.map((c) => c.name), ['Server 1', 'Server 2']);
      expect(
        dynamicChannels.map((c) => c.streamUrl),
        ['https://cdn.test/ss1_a.m3u8', 'https://cdn.test/ss1_b.m3u8'],
      );
    });

    testWidgets('CategoryM3uAutoSyncObserver polls directly on interval and app resume with zero DB hits', (tester) async {
      final cache = CacheService();
      const cat = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/sports.m3u',
        active: true,
      );
      await cache.saveLocalCategories([cat]);
      await cache.saveLocalChannelsVersion(1);

      var m3uFetches = 0;
      final supabase = _StubSupabaseService(channelsVersion: 1);
      final m3uSync = CategoryM3uSyncService(
        cache: cache,
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async {
          m3uFetches++;
          return CategoryM3uHttpResponse(
            statusCode: 200,
            body: '#EXTM3U\n#EXTINF:-1,Live $m3uFetches\nhttps://cdn.test/$m3uFetches.m3u8\n',
          );
        },
      );

      final container = ProviderContainer(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          supabaseServiceProvider.overrideWithValue(supabase),
          categoryM3uSyncServiceProvider.overrideWithValue(m3uSync),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CategoryM3uAutoSyncObserver(
              pollInterval: Duration(minutes: 15),
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );

      // Advance 15 minutes -> periodic direct M3U refresh fires without hitting DB
      await tester.pump(const Duration(minutes: 15));
      await tester.pump();
      expect(m3uFetches, 1);
      expect(supabase.getCategoriesCalls, 0);

      // Simulate app resume -> direct M3U refresh + lightweight version check
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(m3uFetches, 1); // Throttled within 15s minInterval after just-finished poll
      expect(supabase.getSyncVersionsCalls, 1);
      expect(supabase.getCategoriesCalls, 0);
    });
  });
}
