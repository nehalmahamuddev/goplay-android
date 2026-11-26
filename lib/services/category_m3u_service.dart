import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import '../models/category.dart';
import '../models/channel.dart';
import '../models/drm_config.dart';
import '../models/stream_server.dart';
import '../utils/channel_name.dart';
import 'cache_service.dart';
import 'iptv_service.dart';

/// Result of a conditional HTTP fetch for a category's M3U playlist.
class CategoryM3uHttpResponse {
  final int statusCode;
  final String? body;
  final String? etag;
  final String? lastModified;

  const CategoryM3uHttpResponse({
    required this.statusCode,
    this.body,
    this.etag,
    this.lastModified,
  });
}

typedef CategoryM3uFetcher = Future<CategoryM3uHttpResponse> Function(
  String url, {
  String? ifNoneMatch,
  String? ifModifiedSince,
});

/// Synchronizes M3U-backed categories directly from their locally stored
/// `m3u_url` using conditional HTTP headers (`ETag` / `Last-Modified`) and
/// content-hash diffing, without requiring Supabase database queries.
class CategoryM3uSyncService {
  final CacheService _cache;
  final CategoryM3uFetcher _fetcher;
  final DateTime Function() _now;
  final Map<(String, String), Future<bool>> _inFlight = {};

  CategoryM3uSyncService({
    required CacheService cache,
    Dio? dio,
    CategoryM3uFetcher? fetcher,
    DateTime Function()? now,
  })  : _cache = cache,
        _now = now ?? (() => DateTime.now().toUtc()),
        _fetcher = fetcher ?? _defaultFetcher(dio ?? _createDefaultDio());

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; Pixel 3 XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
        },
      ),
    );
  }

  static CategoryM3uFetcher _defaultFetcher(Dio dio) {
    return (
      String url, {
      String? ifNoneMatch,
      String? ifModifiedSince,
    }) async {
      final reqHeaders = <String, String>{};
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) {
        reqHeaders['If-None-Match'] = ifNoneMatch;
      }
      if (ifModifiedSince != null && ifModifiedSince.isNotEmpty) {
        reqHeaders['If-Modified-Since'] = ifModifiedSince;
      }

      final response = await dio.get<String>(
        url,
        options: Options(
          headers: reqHeaders.isEmpty ? null : reqHeaders,
          responseType: ResponseType.plain,
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );

      return CategoryM3uHttpResponse(
        statusCode: response.statusCode ?? 200,
        body: response.data,
        etag: response.headers.value('etag'),
        lastModified: response.headers.value('last-modified'),
      );
    };
  }

  /// Syncs a single [category] directly from its saved `m3uUrl`.
  ///
  /// Returns `true` if the locally cached channel list actually changed.
  /// Concurrent calls for the same category + URL are coalesced.
  Future<bool> syncCategory(Category category, {bool force = false}) {
    final url = category.effectiveM3uUrl;
    if (!category.active || url == null) {
      return Future.value(false);
    }

    final flightKey = (category.id, url);
    final existing = _inFlight[flightKey];
    if (existing != null) return existing;

    final future = _runSyncCategory(category, url, force: force);
    _inFlight[flightKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[flightKey], future)) {
        _inFlight.remove(flightKey);
      }
    });
  }

  Future<bool> _runSyncCategory(
    Category category,
    String url, {
    required bool force,
  }) async {
    final prevMeta = _cache.getCategoryM3uMeta(category.id);
    final cachedChannels = _cache.getCategoryM3uChannels(category.id);
    final urlChanged = prevMeta == null || prevMeta.m3uUrl != url;

    try {
      final response = await _fetcher(
        url,
        ifNoneMatch: (!force && !urlChanged && cachedChannels.isNotEmpty)
            ? prevMeta.etag
            : null,
        ifModifiedSince: (!force && !urlChanged && cachedChannels.isNotEmpty)
            ? prevMeta.lastModified
            : null,
      );

      final syncedAt = _now();

      if (response.statusCode == 304) {
        if (!urlChanged) {
          await _cache.saveCategoryM3uMeta(
            category.id,
            CategoryM3uMeta(
              m3uUrl: url,
              etag: response.etag ?? prevMeta.etag,
              lastModified: response.lastModified ?? prevMeta.lastModified,
              contentHash: prevMeta.contentHash,
              lastSyncedAt: syncedAt,
            ),
          );
        }
        return false;
      }

      final rawBody = response.body ?? '';
      if (rawBody.trim().isEmpty) {
        return false;
      }

      final hash = computeM3uContentHash(rawBody);
      if (!force &&
          !urlChanged &&
          prevMeta.contentHash == hash &&
          cachedChannels.isNotEmpty) {
        await _cache.saveCategoryM3uMeta(
          category.id,
          CategoryM3uMeta(
            m3uUrl: url,
            etag: response.etag ?? prevMeta.etag,
            lastModified: response.lastModified ?? prevMeta.lastModified,
            contentHash: hash,
            lastSyncedAt: syncedAt,
          ),
        );
        return false;
      }

      final parsed = await parseCategoryM3uInBackground(rawBody, category.id);
      if (parsed.isEmpty) {
        return false;
      }

      final changed = urlChanged ||
          cachedChannels.isEmpty ||
          prevMeta.contentHash != hash ||
          !_channelsEqual(cachedChannels, parsed);

      await _cache.saveCategoryM3uChannels(category.id, parsed);
      await _cache.saveCategoryM3uMeta(
        category.id,
        CategoryM3uMeta(
          m3uUrl: url,
          etag: response.etag,
          lastModified: response.lastModified,
          contentHash: hash,
          lastSyncedAt: syncedAt,
        ),
      );
      return changed;
    } catch (e) {
      debugPrint('CategoryM3uSyncService: sync failed for ${category.id}: $e');
      return false;
    }
  }

  /// Syncs all active M3U-backed categories currently stored locally.
  ///
  /// Returns `true` if any category's channel list changed.
  Future<bool> syncAllActiveCategories({
    bool force = false,
    Duration? minInterval,
  }) async {
    final m3uCategories = _cache
        .getLocalCategories()
        .where((c) => c.active && c.hasM3uUrl)
        .toList(growable: false);

    if (m3uCategories.isEmpty) return false;

    final now = _now();
    final due = <Category>[
      for (final cat in m3uCategories)
        if (_needsM3uSync(cat, force: force, minInterval: minInterval, now: now)) cat,
    ];

    if (due.isEmpty) return false;

    var anyChanged = false;
    const chunkSize = 4;
    for (var i = 0; i < due.length; i += chunkSize) {
      final end = (i + chunkSize < due.length) ? i + chunkSize : due.length;
      final batch = due.sublist(i, end);
      final results = await Future.wait(
        batch.map((cat) => syncCategory(cat, force: force)),
      );
      if (results.any((changed) => changed)) {
        anyChanged = true;
      }
    }

    return anyChanged;
  }

  /// Reconciles local M3U caches after Supabase category metadata updates.
  ///
  /// - Clears cached M3U data for categories removed, deactivated, or whose
  ///   `m3uUrl` was cleared.
  /// - Immediately refreshes active categories whose `m3uUrl` was newly added
  ///   or changed.
  ///
  /// Returns `true` if any cached M3U channel list changed.
  Future<bool> reconcileCategories(List<Category> nextCategories) async {
    var anyChanged = false;
    final nextById = {for (final c in nextCategories) c.id: c};

    // 1. Clean up stale/removed/deactivated/cleared M3U category caches
    final cachedIds = _cache.getCachedM3uCategoryIds();
    for (final id in cachedIds) {
      final nextCat = nextById[id];
      if (nextCat == null || !nextCat.active || !nextCat.hasM3uUrl) {
        final hadChannels = _cache.getCategoryM3uChannels(id).isNotEmpty;
        await _cache.clearCategoryM3uData(id);
        if (hadChannels) anyChanged = true;
      }
    }

    // 2. Refresh categories whose m3uUrl is new, changed, or uncached
    final toRefresh = <Category>[
      for (final cat in nextCategories)
        if (cat.active && cat.hasM3uUrl && _isCategoryStaleOrUrlChanged(cat)) cat,
    ];

    if (toRefresh.isNotEmpty) {
      final results = await Future.wait(
        toRefresh.map((cat) => syncCategory(cat, force: true)),
      );
      if (results.any((changed) => changed)) {
        anyChanged = true;
      }
    }

    return anyChanged;
  }

  bool _isCategoryStaleOrUrlChanged(Category cat) {
    final meta = _cache.getCategoryM3uMeta(cat.id);
    final cached = _cache.getCategoryM3uChannels(cat.id);
    return meta == null || meta.m3uUrl != cat.effectiveM3uUrl || cached.isEmpty;
  }

  bool _needsM3uSync(
    Category cat, {
    required bool force,
    Duration? minInterval,
    required DateTime now,
  }) {
    if (force || minInterval == null) return true;
    if (_isCategoryStaleOrUrlChanged(cat)) return true;
    final lastSyncedAt = _cache.getCategoryM3uMeta(cat.id)?.lastSyncedAt;
    return lastSyncedAt == null || now.difference(lastSyncedAt) >= minInterval;
  }
}

/// Fast deterministic content hash (`<length>:<64-bit FNV-1a hex>`) for diffing
/// M3U playlist bodies without external dependencies.
String computeM3uContentHash(String content) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (var i = 0; i < content.length; i++) {
    hash ^= content.codeUnitAt(i);
    hash = (hash * prime) & 0x7fffffffffffffff;
  }
  return '${content.length}:${hash.toRadixString(16)}';
}

bool _channelsEqual(List<Channel> a, List<Channel> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final ca = a[i];
    final cb = b[i];
    if (ca.id != cb.id ||
        ca.name != cb.name ||
        ca.logo != cb.logo ||
        ca.tvgId != cb.tvgId ||
        ca.quality != cb.quality ||
        _serverSignature(ca.streamUrl, ca.headers, ca.drm) !=
            _serverSignature(cb.streamUrl, cb.headers, cb.drm) ||
        ca.streamServers.length != cb.streamServers.length) {
      return false;
    }
    for (var j = 0; j < ca.streamServers.length; j++) {
      final sa = ca.streamServers[j];
      final sb = cb.streamServers[j];
      if (sa.name != sb.name ||
          _serverSignature(sa.streamUrl, sa.headers, sa.drm) !=
              _serverSignature(sb.streamUrl, sb.headers, sb.drm)) {
        return false;
      }
    }
  }
  return true;
}

/// Top-level isolate entrypoint for parsing a category's M3U/JSON playlist.
List<Channel> _parseCategoryM3uIsolate(({String content, String categoryId}) args) {
  return parseCategoryM3uContent(args.content, args.categoryId);
}

/// Parses [content] (M3U/M3U8 or JSON playlist) on a background isolate,
/// assigning every channel to [categoryId] and merging duplicate names into
/// multi-server channels.
Future<List<Channel>> parseCategoryM3uInBackground(
  String content,
  String categoryId,
) {
  return compute(
    _parseCategoryM3uIsolate,
    (content: content, categoryId: categoryId),
  );
}

/// Parses a category's M3U/M3U8 or JSON playlist into [Channel] models.
///
/// - Assigns every entry's `category` to [categoryId], ignoring `group-title`.
/// - Merges entries that share the same normalized display name into one
///   [Channel] with ordered [StreamServer] entries (`Server 1`, `Server 2`, …).
/// - Produces deterministic IDs from [categoryId] and `tvg-id` (or normalized
///   name) so favorites and watch history survive playlist reorders and token
///   rotations.
List<Channel> parseCategoryM3uContent(String content, String categoryId) {
  final parsed = parseM3uOrJsonContent(content, 'm3u_$categoryId');
  if (parsed.channels.isEmpty) return const [];

  final groups = <String, List<Channel>>{};
  for (final ch in parsed.channels) {
    final normalized = normalizeChannelName(ch.name).trim().toLowerCase();
    final key = normalized.isNotEmpty ? normalized : ch.name.trim().toLowerCase();
    (groups[key] ??= <Channel>[]).add(ch);
  }

  final usedIds = <String>{};
  final result = <Channel>[];
  var sortOrder = 0;

  for (final entry in groups.entries) {
    final entries = entry.value;
    final first = entries.first;

    String? bestLogo;
    String? bestTvgId;
    String? bestTvgUrl;
    for (final item in entries) {
      if (bestLogo == null && item.logo != null && item.logo!.trim().isNotEmpty) {
        bestLogo = item.logo!.trim();
      }
      if (bestTvgId == null && item.tvgId != null && item.tvgId!.trim().isNotEmpty) {
        bestTvgId = item.tvgId!.trim();
      }
      if (bestTvgUrl == null && item.tvgUrl != null && item.tvgUrl!.trim().isNotEmpty) {
        bestTvgUrl = item.tvgUrl!.trim();
      }
    }

    final channelId = _allocateStableChannelId(
      categoryId: categoryId,
      identityToken: bestTvgId ?? entry.key,
      usedIds: usedIds,
    );

    final servers = _buildDeduplicatedServers(channelId, entries);
    if (servers.isEmpty) continue;

    final primary = servers.first;
    result.add(
      Channel(
        id: channelId,
        name: first.name,
        logo: bestLogo,
        category: categoryId,
        isLive: true,
        quality: first.quality,
        streamUrl: primary.streamUrl,
        headers: primary.headers,
        drm: primary.drm,
        sortOrder: sortOrder++,
        streamServers: servers,
        tvgId: bestTvgId,
        tvgUrl: bestTvgUrl,
      ),
    );
  }

  return result;
}

List<StreamServer> _buildDeduplicatedServers(
  String channelId,
  List<Channel> entries,
) {
  final servers = <StreamServer>[];
  final seenSignatures = <String>{};

  for (final item in entries) {
    final url = item.streamUrl.trim();
    if (url.isEmpty) continue;

    final signature = _serverSignature(url, item.headers, item.drm);
    if (!seenSignatures.add(signature)) continue;

    final idx = servers.length;
    servers.add(
      StreamServer(
        id: '${channelId}_srv_${idx + 1}',
        channelId: channelId,
        name: 'Server ${idx + 1}',
        streamUrl: url,
        drm: item.drm,
        headers: item.headers,
        hasHeader: item.headers.isNotEmpty,
        sortOrder: idx,
        active: true,
      ),
    );
  }

  return servers;
}

String _serverSignature(
  String url,
  Map<String, dynamic> headers,
  DrmConfig? drm,
) {
  final sortedHeaders = headers.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final headerSig = sortedHeaders.map((e) => '${e.key}=${e.value}').join('&');
  final drmSig = drm == null
      ? ''
      : '${drm.type.name}|${drm.kid ?? ''}|${drm.key ?? ''}|${drm.licenseUrl ?? ''}';
  return '$url||$headerSig||$drmSig';
}

String _allocateStableChannelId({
  required String categoryId,
  required String identityToken,
  required Set<String> usedIds,
}) {
  final catPart = _sanitizeIdPart(categoryId);
  final itemPart = _sanitizeIdPart(identityToken);
  final base = 'm3u_${catPart.isEmpty ? 'cat' : catPart}_${itemPart.isEmpty ? 'ch' : itemPart}';

  if (usedIds.add(base)) return base;

  var suffix = 2;
  while (!usedIds.add('${base}_$suffix')) {
    suffix++;
  }
  return '${base}_$suffix';
}

String _sanitizeIdPart(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
