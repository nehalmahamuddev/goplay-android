import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/announcement.dart';
import '../../models/app_ui_config.dart';
import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/event.dart';
import '../../models/hero_banner_item.dart';
import '../stream_decryptor.dart';
import '../supabase_service.dart';

/// Seam isolating remote catalog & realtime transport (Supabase DB,
/// Supabase Realtime, and direct live-event APIs) from [CatalogRepository].
abstract interface class RemoteCatalogAdapter {
  Future<Map<String, dynamic>?> getSyncVersions();
  Future<List<Channel>> getChannels({bool onlyLive = true});
  Future<List<Channel>> getTrendingChannels({
    int limit = 20,
    bool onlyLive = true,
  });
  Future<List<Channel>> getChannelsByCategory(
    String categoryId, {
    bool onlyLive = true,
  });
  Future<List<Category>> getCategories();
  Future<List<Announcement>> getAnnouncements();
  Future<List<HeroBannerItem>> getHeroBanners();
  Future<AppUiConfig?> getUiConfig();
  Future<List<SportEvent>> fetchLiveEvents();
  Future<Map<String, String>> fetchEventCategories();
  Future<List<Channel>> fetchPlayzCategoryChannels({
    required String endpoint,
    required String categoryId,
  });

  /// Emits whenever remote `app_settings` metadata (such as `channels_version`)
  /// changes in real time. Returns an empty stream when realtime is unavailable.
  Stream<void> watchAppSettingsChanges();
}

/// Production [RemoteCatalogAdapter] backed by [SupabaseService], Supabase
/// Realtime, and [StreamDecryptor].
class SupabaseRemoteCatalogAdapter implements RemoteCatalogAdapter {
  final SupabaseService _supabase;
  final SupabaseClient? _realtimeClient;
  final bool _allowAmbientSupabaseInstance;

  const SupabaseRemoteCatalogAdapter({
    required SupabaseService supabase,
    SupabaseClient? realtimeClient,
    bool allowAmbientSupabaseInstance = true,
  })  : _supabase = supabase,
        _realtimeClient = realtimeClient,
        _allowAmbientSupabaseInstance = allowAmbientSupabaseInstance;

  @override
  Future<Map<String, dynamic>?> getSyncVersions() =>
      _supabase.getSyncVersions();

  @override
  Future<List<Channel>> getChannels({bool onlyLive = true}) =>
      _supabase.getChannels(onlyLive: onlyLive);

  @override
  Future<List<Channel>> getTrendingChannels({
    int limit = 20,
    bool onlyLive = true,
  }) =>
      _supabase.getTrendingChannels(limit: limit, onlyLive: onlyLive);

  @override
  Future<List<Channel>> getChannelsByCategory(
    String categoryId, {
    bool onlyLive = true,
  }) =>
      _supabase.getChannelsByCategory(categoryId, onlyLive: onlyLive);

  @override
  Future<List<Category>> getCategories() => _supabase.getCategories();

  @override
  Future<List<Announcement>> getAnnouncements() =>
      _supabase.getAnnouncements();

  @override
  Future<List<HeroBannerItem>> getHeroBanners() => _supabase.getHeroBanners();

  @override
  Future<AppUiConfig?> getUiConfig() => _supabase.getUiConfig();

  @override
  Future<List<SportEvent>> fetchLiveEvents() =>
      StreamDecryptor.fetchLiveEvents();

  @override
  Future<Map<String, String>> fetchEventCategories() =>
      StreamDecryptor.fetchEventCategories();

  @override
  Future<List<Channel>> fetchPlayzCategoryChannels({
    required String endpoint,
    required String categoryId,
  }) =>
      StreamDecryptor.fetchCategoryChannels(
        endpoint: endpoint,
        categoryId: categoryId,
      );

  @override
  Stream<void> watchAppSettingsChanges() {
    final client = _resolveRealtimeClient();
    if (client == null) return const Stream<void>.empty();

    late final StreamController<void> controller;
    RealtimeChannel? channel;

    controller = StreamController<void>.broadcast(
      onListen: () {
        try {
          channel = client
              .channel('public:app_settings:m3u_sync')
              .onPostgresChanges(
                event: PostgresChangeEvent.update,
                schema: 'public',
                table: 'app_settings',
                filter: PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'id',
                  value: 1,
                ),
                callback: (_) {
                  if (!controller.isClosed) {
                    controller.add(null);
                  }
                },
              )
              .subscribe();
        } catch (e) {
          debugPrint('RemoteCatalogAdapter: realtime subscription error: $e');
        }
      },
      onCancel: () {
        final active = channel;
        channel = null;
        if (active != null) {
          try {
            unawaited(client.removeChannel(active));
          } catch (_) {}
        }
      },
    );

    return controller.stream;
  }

  SupabaseClient? _resolveRealtimeClient() {
    if (_realtimeClient != null) return _realtimeClient;
    if (!_allowAmbientSupabaseInstance) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
}
