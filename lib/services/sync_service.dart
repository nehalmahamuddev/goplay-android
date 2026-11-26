import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cache_service.dart';
import 'category_m3u_service.dart';
import 'supabase_service.dart';
import 'stream_decryptor.dart';
import '../models/category.dart';
import '../providers/app_providers.dart';
import '../providers/playz_providers.dart';
import '../models/app_ui_config.dart';

/// Orchestrates version-based background synchronization for channels,
/// categories (including M3U-backed categories), and live events.
class SyncService {
  final Ref _ref;
  DateTime? _lastVersionCheckAt;
  final Map<(String, String), DateTime> _lastCategorySyncAttemptAt = {};

  SyncService(this._ref);

  /// Compares local cache versions with remote Supabase versions, downloads any
  /// modified tables, reconciles category `m3u_url` changes, and refreshes
  /// M3U-backed categories directly from their locally saved links.
  Future<void> sync({bool forceM3uRefresh = false}) async {
    debugPrint('SyncService: Starting background sync...');
    try {
      final SupabaseService supabase = _ref.read(supabaseServiceProvider);
      final CacheService cache = _ref.read(cacheServiceProvider);
      final CategoryM3uSyncService m3uSync = _ref.read(categoryM3uSyncServiceProvider);

      // 1. Fetch lightweight remote version row from Supabase
      _lastVersionCheckAt = DateTime.now();
      final remoteVersions = await supabase.getSyncVersions();
      if (remoteVersions == null) {
        debugPrint('SyncService: Failed to fetch remote versions. Trying direct M3U refresh only.');
        final m3uChanged = await m3uSync.syncAllActiveCategories(force: forceM3uRefresh);
        if (m3uChanged) {
          invalidateChannelProviders();
        }
        if (!cache.hasAnyLocalChannelData()) {
          throw Exception('Failed to connect to server. Please check your internet connection.');
        }
        return;
      }

      final remoteChannelsVer = remoteVersions['channels_version'] as int;
      final remoteEventsVer = remoteVersions['events_version'] as int;

      final localChannelsVer = cache.getLocalChannelsVersion();
      final localEventsVer = cache.getLocalEventsVersion();

      debugPrint(
        'SyncService: Version check - Channels: local=$localChannelsVer, remote=$remoteChannelsVer | Events: local=$localEventsVer, remote=$remoteEventsVer',
      );

      bool channelsUpdated = false;
      final bool needsCategoryBootstrap = cache.getLocalCategories().isEmpty;
      final bool hasActiveM3uCategories =
          cache.getLocalCategories().any((c) => c.active && c.hasM3uUrl);
      final bool needsChannelBootstrap =
          cache.getLocalChannels().isEmpty && !hasActiveM3uCategories;

      // 2. Synchronize Categories & Channels from Supabase ONLY if version changed or cache empty
      if (localChannelsVer == null ||
          remoteChannelsVer > localChannelsVer ||
          needsCategoryBootstrap ||
          needsChannelBootstrap) {
        debugPrint('SyncService: Channels version changed or cache empty. Downloading from Supabase...');

        final remoteCategories = await supabase.getCategories();
        await cache.saveLocalCategories(remoteCategories);

        final remoteChannels = await supabase.getChannels();
        await cache.saveLocalChannels(remoteChannels);

        await m3uSync.reconcileCategories(remoteCategories);

        await cache.saveLocalChannelsVersion(remoteChannelsVer);
        channelsUpdated = true;
        debugPrint(
          'SyncService: Channels and categories synchronized (${remoteChannels.length} channels, ${remoteCategories.length} categories).',
        );
      } else {
        // 2b. Categories unchanged in DB: refresh directly from locally saved m3u_url(s)
        final m3uChanged = await m3uSync.syncAllActiveCategories(force: forceM3uRefresh);
        if (m3uChanged) {
          channelsUpdated = true;
        }
      }

      // 3. Synchronize Events directly from pabbdyzone.shop API
      try {
        debugPrint('SyncService: Syncing live events directly from pabbdyzone.shop...');
        final directEvents = await StreamDecryptor.fetchLiveEvents();
        if (directEvents.isNotEmpty) {
          await cache.saveLocalEvents(directEvents);
          _ref.invalidate(eventsProvider);
          _ref.invalidate(eventCategoriesProvider);
          debugPrint('SyncService: Live events synchronized directly (${directEvents.length} events).');
        }
      } catch (e) {
        debugPrint('SyncService: Direct events sync non-fatal error: $e');
      }

      // 4. Invalidate channels/categories providers if anything changed
      if (channelsUpdated) {
        invalidateChannelProviders();
      }

      // 5. Sync announcements (lightweight — no version check, always refresh)
      try {
        final remoteAnnouncements = await supabase.getAnnouncements();
        await cache.saveLocalAnnouncements(remoteAnnouncements);
      } catch (e) {
        debugPrint('SyncService: Announcements sync failed (non-fatal): $e');
      }

      // 6. Sync hero banners (lightweight — always refresh on sync)
      try {
        final remoteHeroBanners = await supabase.getHeroBanners();
        await cache.saveLocalHeroBanners(remoteHeroBanners);
        _ref.invalidate(heroBannersProvider);
      } catch (e) {
        debugPrint('SyncService: Hero banners sync failed (non-fatal): $e');
      }

      // 7. Synchronize Dynamic App UI Configuration
      try {
        final remoteUiVer = remoteVersions['ui_config_version'] as int? ?? 1;
        final localUiVer = cache.getLocalUiConfigVersion();
        final rawRemoteUiConfig = remoteVersions['ui_config'];

        if (localUiVer == null ||
            remoteUiVer != localUiVer ||
            localUiVer == 0 ||
            !cache.hasLocalUiConfig()) {
          debugPrint('SyncService: UI Config version changed ($localUiVer -> $remoteUiVer). Updating local cache...');
          AppUiConfig? newConfig;
          if (rawRemoteUiConfig is Map) {
            newConfig = AppUiConfig.fromJson(rawRemoteUiConfig);
          } else {
            newConfig = await supabase.getUiConfig();
          }

          if (newConfig != null) {
            await cache.saveLocalUiConfig(newConfig);
            await cache.saveLocalUiConfigVersion(remoteUiVer);
            _ref.invalidate(uiConfigProvider);
            debugPrint('SyncService: UI Config synchronized successfully (v$remoteUiVer).');
          }
        }
      } catch (e) {
        debugPrint('SyncService: UI Config sync failed (non-fatal): $e');
      }

      debugPrint('SyncService: Background sync check completed successfully.');
    } catch (e, stackTrace) {
      debugPrint('SyncService: Error occurred during synchronization: $e\n$stackTrace');
      final cache = _ref.read(cacheServiceProvider);
      if (!cache.hasAnyLocalChannelData()) {
        rethrow;
      }
    }
  }

  /// Checks `app_settings.channels_version` at most once per [cooldown] (e.g.
  /// on app resume). Only triggers a full Supabase category sync when the
  /// version actually incremented.
  Future<bool> checkForCategoryChangesIfDue({
    Duration cooldown = const Duration(seconds: 45),
  }) async {
    final now = DateTime.now();
    if (_lastVersionCheckAt != null &&
        now.difference(_lastVersionCheckAt!) < cooldown) {
      return false;
    }
    _lastVersionCheckAt = now;

    final supabase = _ref.read(supabaseServiceProvider);
    final cache = _ref.read(cacheServiceProvider);
    final remoteVersions = await supabase.getSyncVersions();
    if (remoteVersions == null) return false;

    final remoteChannelsVer = remoteVersions['channels_version'] as int?;
    final localChannelsVer = cache.getLocalChannelsVersion();
    if (remoteChannelsVer == null) return false;

    if (localChannelsVer == null || remoteChannelsVer > localChannelsVer) {
      await sync();
      return true;
    }
    return false;
  }

  /// Triggers a full sync when a Realtime event reports a newer remote
  /// `channels_version`.
  Future<bool> syncIfRemoteVersionNewer(int? remoteChannelsVersion) async {
    if (remoteChannelsVersion == null) return false;
    final localVersion = _ref.read(cacheServiceProvider).getLocalChannelsVersion();
    if (localVersion == null || remoteChannelsVersion > localVersion) {
      await sync();
      return true;
    }
    return false;
  }

  /// Refreshes all active M3U-backed categories directly from their locally
  /// saved `m3u_url`s with zero Supabase DB requests.
  Future<bool> refreshM3uDirectly({
    bool force = false,
    Duration? minInterval,
  }) async {
    final changed = await _ref
        .read(categoryM3uSyncServiceProvider)
        .syncAllActiveCategories(force: force, minInterval: minInterval);
    if (changed) {
      invalidateChannelProviders();
    }
    return changed;
  }

  /// Refreshes a single M3U-backed [category] directly from its locally saved
  /// `m3u_url` (throttled by [cooldown] per category+URL unless [force] is true).
  Future<bool> refreshM3uCategoryIfDue(
    Category category, {
    bool force = false,
    Duration cooldown = const Duration(seconds: 15),
  }) async {
    final url = category.effectiveM3uUrl;
    if (!category.active || url == null) return false;

    final key = (category.id, url);
    final now = DateTime.now();
    final last = _lastCategorySyncAttemptAt[key];
    if (!force && last != null && now.difference(last) < cooldown) {
      return false;
    }
    _lastCategorySyncAttemptAt[key] = now;

    final changed = await _ref
        .read(categoryM3uSyncServiceProvider)
        .syncCategory(category, force: force);
    if (changed) {
      invalidateChannelProviders();
    }
    return changed;
  }

  void invalidateChannelProviders() {
    debugPrint('SyncService: Invalidating channels and categories providers...');
    _ref.invalidate(rawChannelsProvider);
    _ref.invalidate(channelsProvider);
    _ref.invalidate(categoriesProvider);
    _ref.invalidate(playzCategoriesProvider);
  }
}
