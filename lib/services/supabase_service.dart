import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/channel.dart';
import '../models/event.dart';
import '../models/category.dart';
import '../models/announcement.dart';
import '../models/hero_banner_item.dart';
import '../models/stream_server.dart';
import '../models/app_ui_config.dart';

/// Service for all Supabase database operations
class SupabaseService {
  final SupabaseClient? _client;

  SupabaseService([this._client]);

  /// Fetch version tracking info from database
  Future<Map<String, dynamic>?> getSyncVersions() async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('app_settings')
          .select('channels_version, events_version, ui_config_version, ui_config')
          .eq('id', 1)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  // ─── Channels ───────────────────────────────────────────────



  /// Fetches ALL channels using pagination to bypass the 1000-row PostgREST limit.
  Future<List<Channel>> getChannels() async {
    final client = _client;
    if (client == null) return const [];
    const int batchSize = 1000;
    int offset = 0;
    final List<Channel> allChannels = [];

    while (true) {
      final response = await client
          .from('channels')
          .select('*, stream_servers(*)')
          .order('sort_order', ascending: true)
          .range(offset, offset + batchSize - 1);

      final batch = (response as List).map((e) => Channel.fromJson(e)).toList();
      allChannels.addAll(batch);

      if (batch.length < batchSize) break; // Last page reached
      offset += batchSize;
    }

    return allChannels;
  }

  Future<List<Channel>> getTrendingChannels({int limit = 20}) async {
    final client = _client;
    if (client == null) return const [];
    // 1. Try real-time RPC for dynamic trending (Admin pins + 24-48h top plays)
    try {
      final response = await client.rpc(
        'get_trending_channels',
        params: {'p_limit': limit},
      );
      if (response is List && response.isNotEmpty) {
        return response
            .map((e) => Channel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Supabase get_trending_channels RPC failed: $e, falling back to static query');
    }

    // 2. Fallback to static pinned query
    const int batchSize = 1000;
    int offset = 0;
    final List<Channel> allChannels = [];

    while (true) {
      final response = await client
          .from('channels')
          .select('*, stream_servers(*)')
          .eq('is_trending', true)
          .order('sort_order', ascending: true)
          .range(offset, offset + batchSize - 1);

      final batch = (response as List).map((e) => Channel.fromJson(e)).toList();
      allChannels.addAll(batch);

      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    return allChannels;
  }

  Future<List<Channel>> getChannelsByCategory(String categoryId) async {
    final client = _client;
    if (client == null) return const [];
    const int batchSize = 1000;
    int offset = 0;
    final List<Channel> allChannels = [];

    while (true) {
      final response = await client
          .from('channels')
          .select('*, stream_servers(*)')
          .eq('category', categoryId)
          .order('sort_order', ascending: true)
          .range(offset, offset + batchSize - 1);

      final batch = (response as List).map((e) => Channel.fromJson(e)).toList();
      allChannels.addAll(batch);

      if (batch.length < batchSize) break;
      offset += batchSize;
    }

    return allChannels;
  }

  Future<Channel?> getChannel(String id) async {
    final client = _client;
    if (client == null) return null;
    final response =
        await client.from('channels').select().eq('id', id).maybeSingle();
    if (response == null) return null;
    return Channel.fromJson(response);
  }

  // ─── Events ─────────────────────────────────────────────────
  Future<List<SportEvent>> getEvents() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('events')
        .select()
        .order('sort_order', ascending: true);
    return (response as List).map((e) => SportEvent.fromJson(e)).toList();
  }

  Future<List<SportEvent>> getLiveEvents() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('events')
        .select()
        .eq('status', 'live')
        .order('sort_order', ascending: true);
    return (response as List).map((e) => SportEvent.fromJson(e)).toList();
  }

  Future<List<SportEvent>> getUpcomingEvents() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('events')
        .select()
        .eq('status', 'upcoming')
        .order('sort_order', ascending: true);
    return (response as List).map((e) => SportEvent.fromJson(e)).toList();
  }

  Future<List<SportEvent>> getFeaturedEvents() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('events')
        .select()
        .eq('is_featured', true)
        .order('sort_order', ascending: true);
    return (response as List).map((e) => SportEvent.fromJson(e)).toList();
  }

  // ─── Categories ─────────────────────────────────────────────
  Future<List<Category>> getCategories() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('categories')
        .select()
        .order('sort_order', ascending: true);
    return (response as List).map((e) => Category.fromJson(e)).toList();
  }

  // ─── Announcements ─────────────────────────────────────────
  Future<List<Announcement>> getAnnouncements() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('announcements')
        .select()
        .eq('active', true)
        .order('created_at', ascending: false);
    return (response as List).map((e) => Announcement.fromJson(e)).toList();
  }

  // ─── Hero Banners ───────────────────────────────────────────
  Future<List<HeroBannerItem>> getHeroBanners() async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('hero_banners')
        .select()
        .eq('active', true)
        .order('sort_order', ascending: true);
    return (response as List).map((e) => HeroBannerItem.fromJson(e)).toList();
  }

  // ─── Favorites ──────────────────────────────────────────────
  Future<List<String>> getFavoriteIds(String deviceId, String itemType) async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('favorites')
        .select('item_id')
        .eq('device_id', deviceId)
        .eq('item_type', itemType);
    return (response as List).map((e) => e['item_id'] as String).toList();
  }

  Future<void> addFavorite(
      String deviceId, String itemType, String itemId) async {
    final client = _client;
    if (client == null) return;
    await client.from('favorites').upsert({
      'device_id': deviceId,
      'item_type': itemType,
      'item_id': itemId,
    }, onConflict: 'device_id,item_type,item_id');
  }

  Future<void> removeFavorite(
      String deviceId, String itemType, String itemId) async {
    final client = _client;
    if (client == null) return;
    await client
        .from('favorites')
        .delete()
        .eq('device_id', deviceId)
        .eq('item_type', itemType)
        .eq('item_id', itemId);
  }

  // ─── Watch History ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getWatchHistory(String deviceId) async {
    final client = _client;
    if (client == null) return const [];
    final response = await client
        .from('watch_history')
        .select()
        .eq('device_id', deviceId)
        .order('watched_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<void> upsertWatchHistory({
    required String deviceId,
    required String channelId,
    String? title,
    String? logo,
  }) async {
    final client = _client;
    if (client == null) return;
    // Check if entry exists
    final existing = await client
        .from('watch_history')
        .select('id')
        .eq('device_id', deviceId)
        .eq('channel_id', channelId)
        .maybeSingle();

    if (existing != null) {
      await client
          .from('watch_history')
          .update({'watched_at': DateTime.now().toIso8601String()})
          .eq('id', existing['id']);
    } else {
      await client.from('watch_history').insert({
        'device_id': deviceId,
        'channel_id': channelId,
        'title': title,
        'logo': logo,
      });
    }
  }

  // ─── Stream Servers (Unified Multi-Server Architecture) ───────
  Future<List<StreamServer>> getStreamServers(String channelId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final response = await client
          .from('stream_servers')
          .select()
          .eq('channel_id', channelId)
          .eq('active', true)
          .order('sort_order', ascending: true);

      return (response as List)
          .map((e) => StreamServer.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> upsertStreamServers(List<StreamServer> servers) async {
    final client = _client;
    if (client == null || servers.isEmpty) return;
    final payload = servers.map((s) => s.toJson()).toList();
    await client.from('stream_servers').upsert(payload, onConflict: 'id');
  }

  // ─── App UI Configuration ────────────────────────────────────
  Future<AppUiConfig?> getUiConfig() async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('app_settings')
          .select('ui_config')
          .eq('id', 1)
          .maybeSingle();
      if (response != null && response['ui_config'] != null) {
        return AppUiConfig.fromJson(Map<String, dynamic>.from(response['ui_config']));
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

