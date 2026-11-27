// `show` is required: flutter/foundation also exports a `Category` annotation
// class, which would otherwise clash with our Category model.
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../models/channel.dart';
import '../models/event.dart';
import '../models/category.dart';
import '../models/announcement.dart';
import '../models/hero_banner_item.dart';
import '../models/app_ui_config.dart';
import '../models/nav_destination.dart';
import 'catalog/catalog_store.dart';
import 'catalog/preferences_store.dart';

export 'catalog/catalog_store.dart' show CatalogStore, CategoryM3uMeta;
export 'catalog/preferences_store.dart' show PreferencesStore;

/// Hive-backed local store implementing both [CatalogStore] and
/// [PreferencesStore] with in-memory decode memoization.
///
/// Every `getLocal*` call used to re-decode the whole Hive payload into model
/// objects on the UI isolate. For a multi-thousand channel list that is a
/// visible frame drop, and it ran again on every `ref.invalidate`. Decoded
/// results are now memoized in memory and only dropped when the corresponding
/// `saveLocal*` writes new data.
class CacheService implements CatalogStore, PreferencesStore {
  List<Channel>? _channelsMemo;
  List<Category>? _categoriesMemo;
  List<SportEvent>? _eventsMemo;
  List<Announcement>? _announcementsMemo;
  List<HeroBannerItem>? _heroBannersMemo;
  Set<String>? _favoritesMemo;
  Map<String, List<Channel>>? _m3uChannelsMemo;
  Map<String, CategoryM3uMeta?>? _m3uMetaMemo;
  AppUiConfig? _uiConfigMemo;
  int? _channelsVersionMemo;

  static const String _m3uChannelsPrefix = 'm3u_channels_';
  static const String _m3uMetaPrefix = 'm3u_meta_';

  /// Drops every memoized decode. Used after a cache wipe.
  @override
  void invalidateMemo() {
    _channelsMemo = null;
    _categoriesMemo = null;
    _eventsMemo = null;
    _announcementsMemo = null;
    _heroBannersMemo = null;
    _favoritesMemo = null;
    _m3uChannelsMemo = null;
    _m3uMetaMemo = null;
    _uiConfigMemo = null;
    _channelsVersionMemo = null;
  }

  /// Reads a Hive box without throwing when the box failed to open at startup.
  Box? _boxOrNull(String name) {
    try {
      if (!Hive.isBoxOpen(name)) return null;
      return Hive.box(name);
    } catch (e) {
      debugPrint('CacheService: box "$name" unavailable: $e');
      return null;
    }
  }

  List<T> _decodeList<T>(
    String boxName,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final box = _boxOrNull(boxName);
    final List<dynamic>? rawList = box?.get(key) as List<dynamic>?;
    if (rawList == null) return const [];
    final out = <T>[];
    for (final e in rawList) {
      if (e is! Map) continue;
      try {
        out.add(fromJson(Map<String, dynamic>.from(e)));
      } catch (err) {
        // A single malformed row must never take down the whole list.
        debugPrint('CacheService: skipping malformed $T row: $err');
      }
    }
    return out;
  }

  // ─── Channels ───────────────────────────────────────────────
  @override
  List<Channel> getLocalChannels() {
    return _channelsMemo ??= _decodeList(
      AppConstants.channelsBox,
      'channels',
      Channel.fromJson,
    );
  }

  @override
  Future<void> saveLocalChannels(List<Channel> channels) async {
    // Prime rather than clear. SyncService already holds these objects freshly
    // parsed from Supabase, then invalidates `channelsProvider` — which used to
    // force a full re-decode of ~15k channels on the main thread immediately
    // after every sync. Adopting the caller's list skips that entirely.
    _channelsMemo = List<Channel>.unmodifiable(channels);
    final box = _boxOrNull(AppConstants.channelsBox);
    if (box == null) return;
    await box.put('channels', channels.map((c) => c.toJson()).toList());
  }

  // ─── Category M3U Channels & Sync Metadata ──────────────────
  @override
  List<Channel> getCategoryM3uChannels(String categoryId) {
    _m3uChannelsMemo ??= {};
    if (_m3uChannelsMemo!.containsKey(categoryId)) {
      return _m3uChannelsMemo![categoryId]!;
    }
    final channels = _decodeList(
      AppConstants.channelsBox,
      '$_m3uChannelsPrefix$categoryId',
      Channel.fromJson,
    );
    _m3uChannelsMemo![categoryId] = List<Channel>.unmodifiable(channels);
    return _m3uChannelsMemo![categoryId]!;
  }

  @override
  Future<void> saveCategoryM3uChannels(
    String categoryId,
    List<Channel> channels,
  ) async {
    _m3uChannelsMemo ??= {};
    _m3uChannelsMemo![categoryId] = List<Channel>.unmodifiable(channels);
    final box = _boxOrNull(AppConstants.channelsBox);
    if (box == null) return;
    await box.put(
      '$_m3uChannelsPrefix$categoryId',
      channels.map((c) => c.toJson()).toList(),
    );
  }

  @override
  CategoryM3uMeta? getCategoryM3uMeta(String categoryId) {
    _m3uMetaMemo ??= {};
    if (_m3uMetaMemo!.containsKey(categoryId)) {
      return _m3uMetaMemo![categoryId];
    }
    final raw = _boxOrNull(AppConstants.settingsBox)?.get('$_m3uMetaPrefix$categoryId');
    CategoryM3uMeta? meta;
    if (raw is Map) {
      try {
        meta = CategoryM3uMeta.fromJson(Map<String, dynamic>.from(raw));
      } catch (e) {
        debugPrint('CacheService: skipping malformed m3u meta for $categoryId: $e');
      }
    }
    _m3uMetaMemo![categoryId] = meta;
    return meta;
  }

  @override
  Future<void> saveCategoryM3uMeta(
    String categoryId,
    CategoryM3uMeta meta,
  ) async {
    _m3uMetaMemo ??= {};
    _m3uMetaMemo![categoryId] = meta;
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put('$_m3uMetaPrefix$categoryId', meta.toJson());
  }

  @override
  Future<void> clearCategoryM3uData(String categoryId) async {
    _m3uChannelsMemo?.remove(categoryId);
    _m3uMetaMemo?.remove(categoryId);
    await _boxOrNull(AppConstants.channelsBox)?.delete('$_m3uChannelsPrefix$categoryId');
    await _boxOrNull(AppConstants.settingsBox)?.delete('$_m3uMetaPrefix$categoryId');
  }

  @override
  Set<String> getCachedM3uCategoryIds() {
    final ids = <String>{};
    if (_m3uChannelsMemo != null) {
      ids.addAll(_m3uChannelsMemo!.keys);
    }
    if (_m3uMetaMemo != null) {
      ids.addAll(_m3uMetaMemo!.keys);
    }
    final channelsBox = _boxOrNull(AppConstants.channelsBox);
    if (channelsBox != null) {
      for (final key in channelsBox.keys) {
        if (key is String && key.startsWith(_m3uChannelsPrefix)) {
          ids.add(key.substring(_m3uChannelsPrefix.length));
        }
      }
    }
    final settingsBox = _boxOrNull(AppConstants.settingsBox);
    if (settingsBox != null) {
      for (final key in settingsBox.keys) {
        if (key is String && key.startsWith(_m3uMetaPrefix)) {
          ids.add(key.substring(_m3uMetaPrefix.length));
        }
      }
    }
    return ids;
  }

  /// True if either standard DB channels or any active M3U category's cached
  /// channels are available locally.
  @override
  bool hasAnyLocalChannelData() {
    if (getLocalChannels().isNotEmpty) return true;
    for (final cat in getLocalCategories()) {
      if (cat.active && cat.hasM3uUrl && getCategoryM3uChannels(cat.id).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  // ─── Events ─────────────────────────────────────────────────
  @override
  List<SportEvent> getLocalEvents() {
    return _eventsMemo ??= () {
      final events = _decodeList(
        AppConstants.eventsBox,
        'events',
        SportEvent.fromJson,
      ).toList();
      events.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return events;
    }();
  }

  @override
  Future<void> saveLocalEvents(List<SportEvent> events) async {
    // Primed, matching saveLocalChannels. Persist the sorted list so Hive
    // storage and the in-memory memo never diverge on event ordering.
    final sorted = events.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _eventsMemo = List<SportEvent>.unmodifiable(sorted);
    final box = _boxOrNull(AppConstants.eventsBox);
    if (box == null) return;
    await box.put('events', sorted.map((e) => e.toJson()).toList());
  }

  // ─── Categories ─────────────────────────────────────────────
  @override
  List<Category> getLocalCategories() {
    return _categoriesMemo ??= _decodeList(
      AppConstants.categoriesBox,
      'categories',
      Category.fromJson,
    );
  }

  @override
  Future<void> saveLocalCategories(List<Category> categories) async {
    _categoriesMemo = List<Category>.unmodifiable(categories);
    final box = _boxOrNull(AppConstants.categoriesBox);
    if (box == null) return;
    await box.put('categories', categories.map((c) => c.toJson()).toList());
  }

  // ─── Favorites ──────────────────────────────────────────────
  @override
  Set<String> getFavoriteChannelIds() {
    return _favoritesMemo ??= () {
      final box = _boxOrNull(AppConstants.favoritesBox);
      final raw = box?.get('channel_ids') as List<dynamic>?;
      if (raw == null) return <String>{};
      return raw.whereType<String>().toSet();
    }();
  }

  @override
  Future<void> saveFavoriteChannelIds(Set<String> ids) async {
    _favoritesMemo = Set<String>.unmodifiable(ids);
    final box = _boxOrNull(AppConstants.favoritesBox);
    if (box == null) return;
    await box.put('channel_ids', ids.toList(growable: false));
  }

  // ─── User Preference: Show Trending Tab ─────────────────────
  @override
  bool getShowTrendingTabUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    return box?.get('user_show_trending_tab') as bool? ?? true;
  }

  @override
  Future<void> saveShowTrendingTabUserPref(bool enabled) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put('user_show_trending_tab', enabled);
  }

  // ─── User Preference: Show Live Tab Counter ──────────────────
  @override
  bool getShowLiveTabCounterUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    return box?.get('user_show_live_tab_counter') as bool? ?? false;
  }

  @override
  Future<void> saveShowLiveTabCounterUserPref(bool enabled) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put('user_show_live_tab_counter', enabled);
  }

  // ─── User Preference: Show Sport Category Icons ──────────────
  @override
  bool getShowSportCategoryIconsUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    return box?.get('user_show_sport_category_icons') as bool? ?? true;
  }

  @override
  Future<void> saveShowSportCategoryIconsUserPref(bool enabled) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put('user_show_sport_category_icons', enabled);
  }

  // ─── User Preference: Navigation Tabs & Launch Screen ────────
  @override
  List<String> getCustomNavTabsUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    final raw = box?.get(AppConstants.customNavTabsKey);
    if (raw is List) {
      final list = raw.cast<String>().where((id) {
        return NavDestination.values.any((d) => d.id == id);
      }).toList();
      if (list.length >= 3 && list.length <= 5) {
        return list;
      }
    }
    return List<String>.from(NavDestination.defaultTabIds);
  }

  @override
  Future<void> saveCustomNavTabsUserPref(List<String> tabs) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put(AppConstants.customNavTabsKey, tabs);
  }

  @override
  String getDefaultLaunchPageUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    final raw = box?.get(AppConstants.defaultLaunchPageKey) as String?;
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return 'home';
  }

  @override
  Future<void> saveDefaultLaunchPageUserPref(String page) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put(AppConstants.defaultLaunchPageKey, page);
  }

  @override
  String getLastActiveNavTabUserPref() {
    final box = _boxOrNull(AppConstants.settingsBox);
    final raw = box?.get(AppConstants.lastActiveNavTabKey) as String?;
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return 'home';
  }

  @override
  Future<void> saveLastActiveNavTabUserPref(String tab) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put(AppConstants.lastActiveNavTabKey, tab);
  }

  // ─── Sync Versions ──────────────────────────────────────────
  @override
  int? getLocalChannelsVersion() => _channelsVersionMemo ??=
      _boxOrNull(AppConstants.settingsBox)?.get('channels_version') as int?;

  @override
  Future<void> saveLocalChannelsVersion(int version) async {
    _channelsVersionMemo = version;
    await _boxOrNull(AppConstants.settingsBox)?.put('channels_version', version);
  }

  @override
  int? getLocalEventsVersion() =>
      _boxOrNull(AppConstants.settingsBox)?.get('events_version') as int?;

  @override
  Future<void> saveLocalEventsVersion(int version) async {
    await _boxOrNull(AppConstants.settingsBox)?.put('events_version', version);
  }

  @override
  Future<void> clearAllCache() async {
    invalidateMemo();
    _uiConfigMemo = null;
    await _boxOrNull(AppConstants.channelsBox)?.clear();
    await _boxOrNull(AppConstants.eventsBox)?.clear();
    await _boxOrNull(AppConstants.categoriesBox)?.clear();
    await _boxOrNull(AppConstants.heroBannersBox)?.clear();
    final settingsBox = _boxOrNull(AppConstants.settingsBox);
    await settingsBox?.delete('channels_version');
    await settingsBox?.delete('events_version');
    await settingsBox?.delete('ui_config');
    await settingsBox?.delete('ui_config_json');
    await settingsBox?.delete('ui_config_version');
    if (settingsBox != null) {
      final m3uMetaKeys = settingsBox.keys
          .whereType<String>()
          .where((k) => k.startsWith(_m3uMetaPrefix))
          .toList(growable: false);
      for (final key in m3uMetaKeys) {
        await settingsBox.delete(key);
      }
    }
  }

  @override
  Future<void> resetLocalUiConfigToDefaults() async {
    _uiConfigMemo = AppUiConfig.defaults();
    final box = _boxOrNull(AppConstants.settingsBox);
    await box?.delete('ui_config');
    await box?.delete('ui_config_json');
    await box?.delete('ui_config_version');
  }

  // ─── Announcements ──────────────────────────────────────────
  @override
  List<Announcement> getLocalAnnouncements() {
    return _announcementsMemo ??= _decodeList(
      AppConstants.announcementsBox,
      'announcements',
      Announcement.fromJson,
    );
  }

  @override
  Future<void> saveLocalAnnouncements(List<Announcement> announcements) async {
    _announcementsMemo = List<Announcement>.unmodifiable(announcements);
    final box = _boxOrNull(AppConstants.announcementsBox);
    if (box == null) return;
    await box.put('announcements', announcements.map((a) => a.toJson()).toList());
  }

  // ─── Hero Banners ───────────────────────────────────────────
  @override
  List<HeroBannerItem> getLocalHeroBanners() {
    return _heroBannersMemo ??= _decodeList(
      AppConstants.heroBannersBox,
      'hero_banners',
      HeroBannerItem.fromJson,
    );
  }

  @override
  Future<void> saveLocalHeroBanners(List<HeroBannerItem> banners) async {
    _heroBannersMemo = List<HeroBannerItem>.unmodifiable(banners);
    final box = _boxOrNull(AppConstants.heroBannersBox);
    if (box == null) return;
    await box.put('hero_banners', banners.map((b) => b.toJson()).toList());
  }

  // ─── App UI Configuration ────────────────────────────────────
  @override
  bool hasLocalUiConfig() {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return false;
    final jsonStr = box.get('ui_config_json');
    if (jsonStr is String && jsonStr.isNotEmpty) return true;
    final raw = box.get('ui_config');
    return raw != null;
  }

  @override
  AppUiConfig getLocalUiConfig() {
    if (_uiConfigMemo != null) return _uiConfigMemo!;
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) {
      // Box is not open yet (e.g. during very early first frame).
      // Return defaults for this frame but do NOT memoize it,
      // so subsequent calls once the box opens load the real saved user theme!
      return AppUiConfig.defaults();
    }

    // 1. Try reading clean JSON string
    final jsonStr = box.get('ui_config_json');
    if (jsonStr is String && jsonStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonStr);
        _uiConfigMemo = AppUiConfig.fromJson(decoded);
        return _uiConfigMemo!;
      } catch (e) {
        debugPrint('CacheService: failed to decode ui_config_json: $e');
      }
    }

    // 2. Fallback to raw map
    final raw = box.get('ui_config');
    if (raw != null) {
      try {
        _uiConfigMemo = AppUiConfig.fromJson(raw);
        return _uiConfigMemo!;
      } catch (e) {
        debugPrint('CacheService: failed to decode raw cached ui_config: $e');
      }
    }

    // Only memoize defaults when the box is open and has no saved config
    return _uiConfigMemo = AppUiConfig.defaults();
  }

  @override
  Future<void> saveLocalUiConfig(AppUiConfig config) async {
    _uiConfigMemo = config;
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    try {
      final jsonStr = jsonEncode(config.toJson());
      await box.put('ui_config_json', jsonStr);
    } catch (e) {
      debugPrint('CacheService: failed to jsonEncode ui_config: $e');
    }
    await box.put('ui_config', config.toJson());
  }

  @override
  int? getLocalUiConfigVersion() {
    final box = _boxOrNull(AppConstants.settingsBox);
    return box?.get('ui_config_version') as int?;
  }

  @override
  Future<void> saveLocalUiConfigVersion(int version) async {
    final box = _boxOrNull(AppConstants.settingsBox);
    if (box == null) return;
    await box.put('ui_config_version', version);
  }
}

