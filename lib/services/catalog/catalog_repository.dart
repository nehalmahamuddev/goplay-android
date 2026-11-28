import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/announcement.dart';
import '../../models/app_ui_config.dart';
import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/event.dart';
import '../../models/hero_banner_item.dart';
import '../../utils/channel_name.dart';
import '../category_m3u_service.dart';
import 'catalog_store.dart';
import 'remote_catalog_adapter.dart';

/// Logical slices of the local catalog that can be refreshed independently.
enum CatalogSection {
  channels,
  categories,
  events,
  announcements,
  heroBanners,
  uiConfig,
}

/// Deep repository owning synchronized catalog storage, DB + category-M3U
/// channel merging, versioned sync, and change notifications.
///
/// Screens, widgets, and providers call this module instead of chaining
/// [SyncService], [CacheService], [SupabaseService], and manual
/// multi-provider `ref.invalidate(...)` choreography.
class CatalogRepository {
  CatalogRepository({
    required CatalogStore store,
    required RemoteCatalogAdapter remote,
    required CategoryM3uSyncService m3uSync,
    DateTime Function()? now,
    void Function(Set<CatalogSection> changed)? onSectionsChanged,
  })  : _store = store,
        _remote = remote,
        _m3uSync = m3uSync,
        _now = now ?? (() => DateTime.now().toUtc()),
        _onSectionsChanged = onSectionsChanged;

  final CatalogStore _store;
  final RemoteCatalogAdapter _remote;
  final CategoryM3uSyncService _m3uSync;
  final DateTime Function() _now;
  final void Function(Set<CatalogSection> changed)? _onSectionsChanged;

  Future<void>? _activeSync;
  DateTime? _lastCategoryVersionCheckAt;
  final Map<(String, String), DateTime> _lastCategorySyncAttemptAt = {};

  bool hasAnyLocalChannelData() => _store.hasAnyLocalChannelData();

  AppUiConfig loadUiConfig() => _store.getLocalUiConfig();

  int? getLocalChannelsVersion() => _store.getLocalChannelsVersion();

  int? getLocalEventsVersion() => _store.getLocalEventsVersion();

  int? getLocalUiConfigVersion() => _store.getLocalUiConfigVersion();

  Stream<void> watchRemoteCatalogChanges() => _remote.watchAppSettingsChanges();

  // ─── Unified Channel & Category Catalog ─────────────────────────────────

  /// Loads the unified channel list, merging DB channels with active local
  /// category M3U playlists and falling back to remote bootstrap on cold start.
  Future<List<Channel>> loadChannels() async {
    var merged = mergeLocalChannels();
    if (merged.isNotEmpty) return merged;

    final categories = _store.getLocalCategories();
    final hasM3uCategories =
        categories.any((c) => c.active && c.hasM3uUrl);
    if (hasM3uCategories) {
      await _m3uSync.syncAllActiveCategories(
        minInterval: const Duration(minutes: 15),
      );
      merged = mergeLocalChannels();
      if (merged.isNotEmpty) return merged;
    }

    if (!_store.hasAnyLocalChannelData()) {
      try {
        final remoteChannels = await _remote.getChannels();
        if (remoteChannels.isNotEmpty) {
          await _store.saveLocalChannels(remoteChannels);
        }
        if (categories.isEmpty) {
          final remoteCategories = await _remote.getCategories();
          if (remoteCategories.isNotEmpty) {
            await _store.saveLocalCategories(remoteCategories);
          }
        }
      } catch (e) {
        debugPrint('CatalogRepository: cold remote channel fallback failed: $e');
      }
      merged = mergeLocalChannels();
    }

    return merged;
  }

  /// Synchronously builds the merged local channel catalog without triggering
  /// network fetches.
  List<Channel> mergeLocalChannels() {
    return mergeDbAndCategoryM3uChannels(
      dbChannels: _store.getLocalChannels(),
      categories: _store.getLocalCategories(),
      readCategoryM3u: _store.getCategoryM3uChannels,
    );
  }

  /// Combines [dbChannels] with cached M3U playlists for active M3U-backed
  /// categories, replacing stale DB rows for those categories while keeping
  /// standard custom categories intact.
  static List<Channel> mergeDbAndCategoryM3uChannels({
    required List<Channel> dbChannels,
    required List<Category> categories,
    required List<Channel> Function(String categoryId) readCategoryM3u,
  }) {
    final m3uCategories = categories
        .where((c) => c.active && c.hasM3uUrl)
        .toList(growable: false);

    if (m3uCategories.isEmpty) {
      return dbChannels;
    }

    final excludedKeys = <String>{};
    for (final cat in m3uCategories) {
      final idKey = cat.id.trim().toLowerCase();
      final nameKey = cat.name.trim().toLowerCase();
      if (idKey.isNotEmpty) excludedKeys.add(idKey);
      if (nameKey.isNotEmpty) excludedKeys.add(nameKey);
    }

    final merged = <Channel>[];
    final seenIds = <String>{};

    for (final ch in dbChannels) {
      final chCat = (ch.category ?? '').trim().toLowerCase();
      if (excludedKeys.contains(chCat)) continue;
      if (ch.id.isEmpty || seenIds.add(ch.id)) {
        merged.add(ch);
      }
    }

    for (final cat in m3uCategories) {
      final m3uChannels = readCategoryM3u(cat.id);
      for (final ch in m3uChannels) {
        if (ch.id.isEmpty || seenIds.add(ch.id)) {
          merged.add(ch);
        }
      }
    }

    return merged;
  }

  /// True if [channel] belongs to [category] by exact or case-insensitive id/name.
  static bool channelMatchesCategory(Channel channel, Category category) {
    final raw = (channel.category ?? '').trim();
    if (raw.isEmpty) return false;
    if (raw == category.id || raw == category.name) return true;
    final lower = raw.toLowerCase();
    return lower == category.id.trim().toLowerCase() ||
        lower == category.name.trim().toLowerCase();
  }

  static const String uncategorizedKey = 'uncategorized';

  /// Groups [channels] by trimmed and lowercase category keys so every lookup
  /// caller shares the same O(n) index.
  static Map<String, List<Channel>> groupChannelsByCategory(
    List<Channel> channels,
  ) {
    final map = <String, List<Channel>>{};
    for (final ch in channels) {
      final raw = (ch.category ?? '').trim();
      final key = raw.isEmpty ? uncategorizedKey : raw;
      (map[key] ??= <Channel>[]).add(ch);
      final lower = key.toLowerCase();
      if (lower != key) {
        (map[lower] ??= <Channel>[]).add(ch);
      }
    }
    return map;
  }

  Future<List<Category>> loadCategories() async {
    var categories = _store.getLocalCategories();
    if (categories.isEmpty) {
      try {
        final remoteCategories = await _remote.getCategories();
        if (remoteCategories.isNotEmpty) {
          await _store.saveLocalCategories(remoteCategories);
          categories = remoteCategories;
        }
      } catch (e) {
        debugPrint('CatalogRepository: remote categories fetch failed: $e');
      }
    }
    final sorted = categories.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted;
  }

  /// Resolves channels for [category] from the unified [liveCatalog] first,
  /// hydrating uncached M3U or direct endpoints only when missing.
  Future<List<Channel>> loadCategoryChannels(
    Category category, {
    List<Channel>? liveCatalog,
  }) async {
    if (!category.active) return const [];
    final catalog = liveCatalog ??
        mergeLocalChannels().where((c) => c.isLive).toList(growable: false);
    final fromCatalog = catalog
        .where((ch) => channelMatchesCategory(ch, category))
        .toList(growable: false);

    if (category.hasM3uUrl) {
      if (fromCatalog.isEmpty && _store.getCategoryM3uMeta(category.id) == null) {
        final changed = await _m3uSync.syncCategory(category, force: true);
        if (changed) {
          _notify({CatalogSection.channels});
        }
        return _store
            .getCategoryM3uChannels(category.id)
            .where((c) => c.isLive)
            .toList(growable: false);
      }

      unawaited(refreshM3uCategoryIfDue(category).catchError((_) => false));
      return fromCatalog;
    }

    if (fromCatalog.isNotEmpty) return fromCatalog;

    try {
      final remoteDb = await _remote.getChannelsByCategory(category.id);
      final liveRemote = remoteDb.where((c) => c.isLive).toList(growable: false);
      if (liveRemote.isNotEmpty) return liveRemote;
    } catch (e) {
      debugPrint('CatalogRepository: category DB fetch failed for ${category.id}: $e');
    }

    final endpoint = (category.playzEndpoint ?? '').trim();
    if (category.isCustom && endpoint.isNotEmpty) {
      final direct = await _remote.fetchPlayzCategoryChannels(
        endpoint: endpoint,
        categoryId: category.id,
      );
      final liveDirect = direct.where((c) => c.isLive).toList(growable: false);
      if (liveDirect.isNotEmpty) return liveDirect;
    }

    return _store
        .getLocalChannels()
        .where((c) => c.isLive && channelMatchesCategory(c, category))
        .toList(growable: false);
  }

  Future<List<Channel>> loadTrendingChannels({
    List<Channel>? liveCatalog,
    int limit = 20,
  }) async {
    final channels = liveCatalog ??
        (await loadChannels()).where((c) => c.isLive).toList(growable: false);

    try {
      final remoteTrending = await _remote.getTrendingChannels(limit: limit);
      if (remoteTrending.isNotEmpty) {
        final resolved = resolveTrendingChannels(
          remoteTrending: remoteTrending,
          liveCatalog: channels,
          limit: limit,
        );
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } catch (e) {
      debugPrint('CatalogRepository: trending fetch fallback: $e');
    }

    return channels
        .where((ch) => ch.isTrending && ch.isLive)
        .take(limit)
        .toList(growable: false);
  }

  /// Resolves remote trending entries against [liveCatalog] by exact ID first,
  /// then by `(category, normalizedName)` and finally by `normalizedName` so
  /// DB-backed trending rows and legacy M3U IDs map cleanly to active M3U
  /// channels without duplicates.
  static List<Channel> resolveTrendingChannels({
    required List<Channel> remoteTrending,
    required List<Channel> liveCatalog,
    int limit = 20,
  }) {
    if (remoteTrending.isEmpty || liveCatalog.isEmpty || limit <= 0) {
      return const <Channel>[];
    }

    final byId = <String, Channel>{};
    final byCategoryAndName = <(String, String), Channel>{};
    final byName = <String, Channel>{};

    for (final ch in liveCatalog) {
      if (!ch.isLive) continue;
      if (ch.id.isNotEmpty) {
        byId.putIfAbsent(ch.id, () => ch);
      }
      final nameKey = _trendingNameMatchKey(ch.name);
      if (nameKey.isEmpty) continue;
      final catKey = (ch.category ?? '').trim().toLowerCase();
      if (catKey.isNotEmpty) {
        byCategoryAndName.putIfAbsent((catKey, nameKey), () => ch);
      }
      byName.putIfAbsent(nameKey, () => ch);
    }

    final resolved = <Channel>[];
    final seenIds = <String>{};

    for (final remote in remoteTrending) {
      if (!remote.isLive) continue;

      Channel? match = byId[remote.id];
      if (match == null) {
        final nameKey = _trendingNameMatchKey(remote.name);
        if (nameKey.isNotEmpty) {
          final catKey = (remote.category ?? '').trim().toLowerCase();
          if (catKey.isNotEmpty) {
            match = byCategoryAndName[(catKey, nameKey)];
          }
          match ??= byName[nameKey];
        }
      }

      if (match == null) continue;
      if (match.id.isEmpty || seenIds.add(match.id)) {
        resolved.add(match);
        if (resolved.length >= limit) break;
      }
    }

    return resolved;
  }

  static String _trendingNameMatchKey(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty || trimmed == 'Unknown Channel') return '';
    final normalized = normalizeChannelName(trimmed).toLowerCase();
    return normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // ─── Events, Announcements, Hero Banners, UI Config ─────────────────────

  Future<Map<String, String>> loadEventCategories() =>
      _remote.fetchEventCategories();

  Future<List<SportEvent>> loadEvents() async {
    final localEvents = _store.getLocalEvents();
    if (localEvents.isNotEmpty) return localEvents;

    try {
      final directEvents = await _remote.fetchLiveEvents();
      if (directEvents.isNotEmpty) {
        await _store.saveLocalEvents(directEvents);
        return _store.getLocalEvents();
      }
    } catch (e) {
      debugPrint('CatalogRepository: live events fallback failed: $e');
    }
    return localEvents;
  }

  Future<List<Announcement>> loadAnnouncements() async {
    final local = _store.getLocalAnnouncements();
    if (local.isNotEmpty) return local;

    try {
      final remote = await _remote.getAnnouncements();
      await _store.saveLocalAnnouncements(remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<List<HeroBannerItem>> loadHeroBanners() async {
    final local = _store.getLocalHeroBanners();
    if (local.isNotEmpty) return local;

    try {
      final remote = await _remote.getHeroBanners();
      await _store.saveLocalHeroBanners(remote);
      return remote;
    } catch (_) {
      return local;
    }
  }

  Future<void> saveUiConfig(AppUiConfig config) async {
    await _store.saveLocalUiConfig(config);
    _notify({CatalogSection.uiConfig});
  }

  Future<void> resetUiConfigToDefaults() async {
    await _store.resetLocalUiConfigToDefaults();
    _notify({CatalogSection.uiConfig});
  }

  Future<void> clearAllCache() async {
    await _store.clearAllCache();
    _notify(CatalogSection.values.toSet());
  }

  // ─── Background Sync & M3U Lifecycle ────────────────────────────────────

  /// Runs a coalesced version check against remote settings and refreshes any
  /// stale channels, categories, M3U playlists, events, announcements, banners,
  /// and UI config, notifying observers once for changed sections.
  Future<void> sync({bool forceM3uRefresh = false}) {
    final existing = _activeSync;
    if (existing != null && !forceM3uRefresh) {
      return existing;
    }

    final run = _runSync(forceM3uRefresh: forceM3uRefresh);
    _activeSync = run;
    return run.whenComplete(() {
      if (identical(_activeSync, run)) {
        _activeSync = null;
      }
    });
  }

  Future<void> _runSync({required bool forceM3uRefresh}) async {
    debugPrint('CatalogRepository: Starting background sync...');
    final changedSections = <CatalogSection>{};

    try {
      final remoteVersions = await _remote.getSyncVersions();
      if (remoteVersions == null) {
        debugPrint(
          'CatalogRepository: Remote versions unavailable; running direct M3U refresh.',
        );
        final m3uChanged = await _m3uSync.syncAllActiveCategories(
          force: forceM3uRefresh,
          minInterval: forceM3uRefresh ? null : const Duration(minutes: 15),
        );
        if (m3uChanged) {
          _notify({CatalogSection.channels, CatalogSection.categories});
        }
        if (!_store.hasAnyLocalChannelData()) {
          throw Exception(
            'Failed to connect to server. Please check your internet connection.',
          );
        }
        return;
      }

      final remoteChannelsVer = remoteVersions['channels_version'] as int?;
      final remoteEventsVer = remoteVersions['events_version'] as int?;
      final remoteUiVer = remoteVersions['ui_config_version'] as int?;

      final localChannelsVer = _store.getLocalChannelsVersion();
      final localEventsVer = _store.getLocalEventsVersion();

      debugPrint(
        'CatalogRepository: Versions — Channels local=$localChannelsVer/remote=$remoteChannelsVer | Events local=$localEventsVer/remote=$remoteEventsVer',
      );

      final cachedCategories = _store.getLocalCategories();
      final hasM3uCategories = cachedCategories.any((c) => c.active && c.hasM3uUrl);
      final channelsOutdated = remoteChannelsVer == null ||
          remoteChannelsVer != localChannelsVer ||
          cachedCategories.isEmpty ||
          (_store.getLocalChannels().isEmpty && !hasM3uCategories);

      if (channelsOutdated) {
        debugPrint(
          'CatalogRepository: Channels/categories changed or empty; syncing from remote...',
        );
        final results = await Future.wait([
          _remote.getChannels(),
          _remote.getCategories(),
        ]);
        final remoteChannels = results[0] as List<Channel>;
        final remoteCategories = results[1] as List<Category>;

        await _store.saveLocalChannels(remoteChannels);
        await _store.saveLocalCategories(remoteCategories);
        if (remoteChannelsVer != null) {
          await _store.saveLocalChannelsVersion(remoteChannelsVer);
        }

        await _m3uSync.reconcileCategories(remoteCategories);
        changedSections.addAll([
          CatalogSection.channels,
          CatalogSection.categories,
        ]);
      } else {
        final m3uChanged = await _m3uSync.syncAllActiveCategories(
          force: forceM3uRefresh,
          minInterval: forceM3uRefresh ? null : const Duration(minutes: 15),
        );
        if (m3uChanged) {
          changedSections.addAll([
            CatalogSection.channels,
            CatalogSection.categories,
          ]);
        }
      }

      if (remoteEventsVer != localEventsVer || _store.getLocalEvents().isEmpty) {
        try {
          debugPrint('CatalogRepository: Syncing live events...');
          final directEvents = await _remote.fetchLiveEvents();
          if (directEvents.isNotEmpty) {
            await _store.saveLocalEvents(directEvents);
            if (remoteEventsVer != null) {
              await _store.saveLocalEventsVersion(remoteEventsVer);
            }
            changedSections.add(CatalogSection.events);
          }
        } catch (e) {
          debugPrint('CatalogRepository: Live events sync non-fatal error: $e');
        }
      }

      try {
        final remoteAnnouncements = await _remote.getAnnouncements();
        await _store.saveLocalAnnouncements(remoteAnnouncements);
        changedSections.add(CatalogSection.announcements);
      } catch (e) {
        debugPrint('CatalogRepository: Announcements sync failed: $e');
      }

      try {
        final remoteHeroBanners = await _remote.getHeroBanners();
        await _store.saveLocalHeroBanners(remoteHeroBanners);
        changedSections.add(CatalogSection.heroBanners);
      } catch (e) {
        debugPrint('CatalogRepository: Hero banners sync failed: $e');
      }

      try {
        final localUiVer = _store.getLocalUiConfigVersion();
        if (remoteUiVer != null &&
            (remoteUiVer != localUiVer || !_store.hasLocalUiConfig())) {
          debugPrint(
            'CatalogRepository: UI Config version changed ($localUiVer -> $remoteUiVer).',
          );
          AppUiConfig? uiConfig;
          if (remoteVersions['ui_config'] is Map) {
            uiConfig = AppUiConfig.fromJson(
              Map<String, dynamic>.from(remoteVersions['ui_config'] as Map),
            );
          } else {
            uiConfig = await _remote.getUiConfig();
          }
          if (uiConfig != null) {
            await _store.saveLocalUiConfig(uiConfig);
            await _store.saveLocalUiConfigVersion(remoteUiVer);
            changedSections.add(CatalogSection.uiConfig);
          }
        }
      } catch (e) {
        debugPrint('CatalogRepository: UI Config sync failed: $e');
      }

      if (changedSections.isNotEmpty) {
        _notify(changedSections);
      }
      debugPrint('CatalogRepository: Background sync completed.');
    } catch (e, stackTrace) {
      debugPrint('CatalogRepository: Error during sync: $e\n$stackTrace');
    }
  }

  /// Refreshes all active M3U-backed categories directly from their stored
  /// `m3u_url` endpoints without hitting Supabase database tables.
  Future<bool> refreshM3uDirectly({
    bool force = false,
    Duration? minInterval,
  }) async {
    final changed = await _m3uSync.syncAllActiveCategories(
      force: force,
      minInterval: minInterval,
    );
    if (changed) {
      _notify({CatalogSection.channels, CatalogSection.categories});
    }
    return changed;
  }

  /// Refreshes a single M3U-backed [category] directly if due (throttled per
  /// category + URL by [cooldown] unless [force] is true).
  Future<bool> refreshM3uCategoryIfDue(
    Category category, {
    bool force = false,
    Duration cooldown = const Duration(seconds: 15),
  }) async {
    final url = category.effectiveM3uUrl;
    if (!category.active || url == null) return false;

    final key = (category.id, url);
    final now = _now();
    final last = _lastCategorySyncAttemptAt[key];
    if (!force && last != null && now.difference(last) < cooldown) {
      return false;
    }
    _lastCategorySyncAttemptAt[key] = now;

    final changed = await _m3uSync.syncCategory(category, force: force);
    if (changed) {
      _notify({CatalogSection.channels, CatalogSection.categories});
    }
    return changed;
  }

  /// Lightweight check for admin `m3u_url` edits when realtime events were missed
  /// while backgrounded.
  Future<bool> checkForCategoryChangesIfDue({
    Duration cooldown = const Duration(minutes: 2),
  }) async {
    final now = _now();
    if (_lastCategoryVersionCheckAt != null &&
        now.difference(_lastCategoryVersionCheckAt!) < cooldown) {
      return false;
    }
    _lastCategoryVersionCheckAt = now;

    try {
      final remoteVersions = await _remote.getSyncVersions();
      if (remoteVersions == null) return false;

      final remoteChannelsVer = remoteVersions['channels_version'] as int?;
      final localChannelsVer = _store.getLocalChannelsVersion();

      if (remoteChannelsVer != null && remoteChannelsVer != localChannelsVer) {
        final results = await Future.wait([
          _remote.getCategories(),
          _remote.getChannels(),
        ]);
        final remoteCategories = results[0] as List<Category>;
        final remoteChannels = results[1] as List<Channel>;

        await _store.saveLocalCategories(remoteCategories);
        await _store.saveLocalChannels(remoteChannels);
        await _store.saveLocalChannelsVersion(remoteChannelsVer);

        await _m3uSync.reconcileCategories(remoteCategories);
        _notify({CatalogSection.channels, CatalogSection.categories});
        return true;
      }

      return await refreshM3uDirectly();
    } catch (e) {
      debugPrint('CatalogRepository: Category change check failed: $e');
      return false;
    }
  }

  void _notify(Set<CatalogSection> sections) {
    if (sections.isEmpty) return;
    _onSectionsChanged?.call(sections);
  }
}
