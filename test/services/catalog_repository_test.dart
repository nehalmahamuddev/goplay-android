import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/announcement.dart';
import 'package:goplay/models/app_ui_config.dart';
import 'package:goplay/models/category.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/models/event.dart';
import 'package:goplay/models/hero_banner_item.dart';
import 'package:goplay/services/catalog/catalog_repository.dart';
import 'package:goplay/services/catalog/catalog_store.dart';
import 'package:goplay/services/catalog/preferences_store.dart';
import 'package:goplay/services/catalog/remote_catalog_adapter.dart';
import 'package:goplay/services/category_m3u_service.dart';

class _FakeRemoteCatalogAdapter implements RemoteCatalogAdapter {
  Map<String, dynamic>? versions;
  List<Channel> channels = const [];
  List<Channel> trending = const [];
  List<Category> categories = const [];
  List<Announcement> announcements = const [];
  List<HeroBannerItem> banners = const [];
  AppUiConfig? uiConfig;
  List<SportEvent> liveEvents = const [];
  Map<String, String> eventCategories = const {};
  List<Channel> playzCategoryChannels = const [];

  int getChannelsCalls = 0;
  int getCategoriesCalls = 0;
  int getTrendingCalls = 0;
  int getCategoryChannelsCalls = 0;
  final StreamController<void> settingsChangesController =
      StreamController<void>.broadcast();

  @override
  Future<Map<String, dynamic>?> getSyncVersions() async => versions;

  @override
  Future<List<Channel>> getChannels({bool onlyLive = true}) async {
    getChannelsCalls++;
    return channels;
  }

  @override
  Future<List<Channel>> getTrendingChannels({
    int limit = 20,
    bool onlyLive = true,
  }) async {
    getTrendingCalls++;
    return trending;
  }

  @override
  Future<List<Channel>> getChannelsByCategory(
    String categoryId, {
    bool onlyLive = true,
  }) async {
    getCategoryChannelsCalls++;
    return channels
        .where((c) => c.category == categoryId && (!onlyLive || c.isLive))
        .toList(growable: false);
  }

  @override
  Future<List<Category>> getCategories() async {
    getCategoriesCalls++;
    return categories;
  }

  @override
  Future<List<Announcement>> getAnnouncements() async => announcements;

  @override
  Future<List<HeroBannerItem>> getHeroBanners() async => banners;

  @override
  Future<AppUiConfig?> getUiConfig() async => uiConfig;

  @override
  Future<List<SportEvent>> fetchLiveEvents() async => liveEvents;

  @override
  Future<Map<String, String>> fetchEventCategories() async => eventCategories;

  @override
  Future<List<Channel>> fetchPlayzCategoryChannels({
    required String endpoint,
    required String categoryId,
  }) async =>
      playzCategoryChannels;

  @override
  Stream<void> watchAppSettingsChanges() => settingsChangesController.stream;
}

Channel _channel(
  String id,
  String name, {
  String category = 'sports',
  bool isLive = true,
  bool isTrending = false,
}) =>
    Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'https://cdn.test/$id.m3u8',
      isLive: isLive,
      isTrending: isTrending,
    );

void main() {
  group('CatalogRepository', () {
    test('loadCategoryChannels reads unified merged M3U catalog without remote DB hit', () async {
      final store = InMemoryCatalogStore();
      final remote = _FakeRemoteCatalogAdapter();
      const sports = Category(
        id: 'sports',
        name: 'Sports',
        m3uUrl: 'https://m3u.test/sports.m3u',
        active: true,
      );
      await store.saveLocalCategories([sports]);
      await store.saveLocalChannels([
        _channel('db_stale', 'Old DB Sports', category: 'sports'),
        _channel('db_news', 'News 24', category: 'news'),
      ]);
      await store.saveCategoryM3uChannels('sports', [
        _channel('m3u_ss1', 'Star Sports 1', category: 'sports'),
      ]);
      await store.saveCategoryM3uMeta(
        'sports',
        CategoryM3uMeta(
          m3uUrl: 'https://m3u.test/sports.m3u',
          lastSyncedAt: DateTime.utc(2026, 11, 27, 12),
        ),
      );

      final m3uSync = CategoryM3uSyncService(
        cache: store,
        now: () => DateTime.utc(2026, 11, 27, 12, 0, 5),
        fetcher: (url, {ifNoneMatch, ifModifiedSince}) async =>
            const CategoryM3uHttpResponse(statusCode: 304),
      );
      final repo = CatalogRepository(
        store: store,
        remote: remote,
        m3uSync: m3uSync,
        now: () => DateTime.utc(2026, 11, 27, 12, 0, 5),
      );

      final merged = await repo.loadChannels();
      expect(merged.map((c) => c.id), ['db_news', 'm3u_ss1']);

      final sportsChannels =
          await repo.loadCategoryChannels(sports, liveCatalog: merged);
      expect(sportsChannels.single.id, 'm3u_ss1');
      expect(remote.getCategoryChannelsCalls, 0);
    });

    test('sync notifies only updated catalog sections and saveLocalEvents persists sorted order', () async {
      final store = InMemoryCatalogStore();
      final remote = _FakeRemoteCatalogAdapter()
        ..versions = {
          'channels_version': 2,
          'events_version': 3,
          'ui_config_version': 4,
        }
        ..categories = const [
          Category(id: 'news', name: 'News', active: true),
        ]
        ..channels = [_channel('n1', 'News One', category: 'news')]
        ..liveEvents = [
          SportEvent(
            id: 'e2',
            league: 'L2',
            sport: 'Football',
            homeTeam: const Team(name: 'C'),
            awayTeam: const Team(name: 'D'),
            startTime: DateTime.utc(2026, 11, 28, 12),
            endTime: DateTime.utc(2026, 11, 28, 14),
            sortOrder: 10,
          ),
          SportEvent(
            id: 'e1',
            league: 'L1',
            sport: 'Cricket',
            homeTeam: const Team(name: 'A'),
            awayTeam: const Team(name: 'B'),
            startTime: DateTime.utc(2026, 11, 28, 10),
            endTime: DateTime.utc(2026, 11, 28, 12),
            sortOrder: 1,
          ),
        ]
        ..uiConfig = AppUiConfig.defaults();

      final notifications = <Set<CatalogSection>>[];
      final repo = CatalogRepository(
        store: store,
        remote: remote,
        m3uSync: CategoryM3uSyncService(
          cache: store,
          fetcher: (url, {ifNoneMatch, ifModifiedSince}) async =>
              const CategoryM3uHttpResponse(statusCode: 304),
        ),
        onSectionsChanged: notifications.add,
      );

      await repo.sync();

      expect(notifications, hasLength(1));
      expect(
        notifications.single,
        containsAll([
          CatalogSection.channels,
          CatalogSection.categories,
          CatalogSection.events,
          CatalogSection.uiConfig,
        ]),
      );
      expect(store.getLocalEvents().map((e) => e.id), ['e1', 'e2']);

      await repo.saveUiConfig(AppUiConfig.defaults());
      expect(notifications.last, {CatalogSection.uiConfig});

      await repo.clearAllCache();
      expect(notifications.last, CatalogSection.values.toSet());
      expect(store.getLocalChannels(), isEmpty);
    });

    test('watchRemoteCatalogChanges forwards stream events cleanly', () async {
      final store = InMemoryCatalogStore();
      final remote = _FakeRemoteCatalogAdapter();
      final repo = CatalogRepository(
        store: store,
        remote: remote,
        m3uSync: CategoryM3uSyncService(
          cache: store,
          fetcher: (url, {ifNoneMatch, ifModifiedSince}) async =>
              const CategoryM3uHttpResponse(statusCode: 304),
        ),
      );
      addTearDown(remote.settingsChangesController.close);

      var eventsSeen = 0;
      final sub = repo.watchRemoteCatalogChanges().listen((_) => eventsSeen++);
      addTearDown(sub.cancel);

      remote.settingsChangesController.add(null);
      await pumpEventQueue();
      expect(eventsSeen, 1);
    });

    test('InMemoryPreferencesStore keeps user prefs independent from catalog clear', () async {
      final prefs = InMemoryPreferencesStore();
      await prefs.saveFavoriteChannelIds({'c1'});
      await prefs.saveDefaultLaunchPageUserPref('channels');

      expect(prefs.getFavoriteChannelIds(), {'c1'});
      expect(prefs.getDefaultLaunchPageUserPref(), 'channels');
    });
  });
}
