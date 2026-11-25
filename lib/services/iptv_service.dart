import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../models/channel.dart';
import '../models/drm_config.dart';
import '../models/iptv_playlist.dart';

/// Top-level result returned from isolate M3U/JSON playlist parsing.
class ParsedPlaylistResult {
  final List<Channel> channels;
  final String? detectedEpgUrl;

  const ParsedPlaylistResult({
    required this.channels,
    this.detectedEpgUrl,
  });
}

/// Connection handshake & account probe result for Stalker / MAG portals.
class StalkerTestResult {
  final String? token;
  final String? expiry;
  final String mac;
  final String? error;

  const StalkerTestResult({
    this.token,
    this.expiry,
    required this.mac,
    this.error,
  });

  bool get isSuccess => error == null && token != null && token!.isNotEmpty;
}

/// Pure function to normalize a channel key for EPG lookup (`lowercase().replaceAll(' ', '')`).
String normalizeEpgKey(String raw) => raw.trim().toLowerCase().replaceAll(' ', '');

/// Quality suffix regex matching `ViewPlaylistActivity.qualityRegex` in `context.md`.
final RegExp kEpgQualityRegex =
    RegExp(r'(\s+hd|\s+fhd|\s+sd|\s+4k)$', caseSensitive: false);

/// Matches an EPG programme list for [channel] using `tvgId` first, then
/// `qualityRegex`-stripped `channel.name` fallback (`context.md` §8.1).
List<IptvEpgProgramme> lookupEpgProgrammesForChannel(
  Channel channel,
  Map<String, List<IptvEpgProgramme>> epgMap,
) {
  if (epgMap.isEmpty) return const [];

  if (channel.tvgId != null && channel.tvgId!.trim().isNotEmpty) {
    final key = normalizeEpgKey(channel.tvgId!);
    final matched = epgMap[key];
    if (matched != null && matched.isNotEmpty) return matched;
  }

  final rawTitle = channel.name.trim();
  if (rawTitle.isNotEmpty) {
    final stripped = rawTitle.replaceFirst(kEpgQualityRegex, '');
    final fallbackKey = normalizeEpgKey(stripped);
    final matched = epgMap[fallbackKey];
    if (matched != null && matched.isNotEmpty) return matched;

    final rawKey = normalizeEpgKey(rawTitle);
    final matchedRaw = epgMap[rawKey];
    if (matchedRaw != null && matchedRaw.isNotEmpty) return matchedRaw;
  }

  return const [];
}

/// Service responsible for fetching, parsing, caching, and storing user-managed
/// IPTV playlists, view settings, EPG guides, and bookmarks.
class IptvService {
  final Dio _dio;
  static const String _boxName = 'iptv_playlists';
  static const String _globalSettingsKey = 'iptv_global_settings_v1';
  static const String _bookmarksKey = 'iptv_bookmarks_map_v1';
  static const String _viewConfigsKey = 'iptv_view_configs_map_v1';
  static const String _epgSourcesKey = 'iptv_epg_sources_v1';

  Box? _box;

  IptvService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 35),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                },
              ),
            );

  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  Box? _settingsBoxOrNull() {
    try {
      if (!Hive.isBoxOpen(AppConstants.settingsBox)) return null;
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  // ─── Playlist Storage Operations ─────────────────────────────────

  Future<List<IptvPlaylist>> getSavedPlaylists() async {
    try {
      final box = await _getBox();
      final List<IptvPlaylist> playlists = [];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is String) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          playlists.add(IptvPlaylist.fromJson(decoded));
        } else if (raw is Map) {
          playlists.add(IptvPlaylist.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      return playlists;
    } catch (e) {
      debugPrint('[IptvService] Error loading playlists: $e');
      return [];
    }
  }

  Future<void> savePlaylist(IptvPlaylist playlist) async {
    try {
      final box = await _getBox();
      await box.put(playlist.id, jsonEncode(playlist.toJson()));
    } catch (e) {
      debugPrint('[IptvService] Error saving playlist: $e');
    }
  }

  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists) async {
    try {
      final box = await _getBox();
      await box.clear();
      for (final p in playlists) {
        await box.put(p.id, jsonEncode(p.toJson()));
      }
    } catch (e) {
      debugPrint('[IptvService] Error saving all playlists: $e');
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      final box = await _getBox();
      await box.delete(id);
    } catch (e) {
      debugPrint('[IptvService] Error deleting playlist: $e');
    }
  }

  // ─── View Settings, Global Settings & Bookmarks Persistence ─────

  IptvGlobalSettings loadGlobalSettings() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_globalSettingsKey);
      if (raw is String && raw.isNotEmpty) {
        return IptvGlobalSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } else if (raw is Map) {
        return IptvGlobalSettings.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('[IptvService] loadGlobalSettings error: $e');
    }
    return const IptvGlobalSettings();
  }

  Future<void> saveGlobalSettings(IptvGlobalSettings settings) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      await box.put(_globalSettingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('[IptvService] saveGlobalSettings error: $e');
    }
  }

  Map<String, IptvViewConfig> loadViewConfigs() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_viewConfigsKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map;
        return decoded.map((k, v) => MapEntry(
              k.toString(),
              IptvViewConfig.fromJson(Map<String, dynamic>.from(v as Map)),
            ));
      } else if (raw is Map) {
        return raw.map((k, v) => MapEntry(
              k.toString(),
              IptvViewConfig.fromJson(Map<String, dynamic>.from(v as Map)),
            ));
      }
    } catch (e) {
      debugPrint('[IptvService] loadViewConfigs error: $e');
    }
    return const {};
  }

  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = configs.map((k, v) => MapEntry(k, v.toJson()));
      await box.put(_viewConfigsKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvService] saveViewConfigs error: $e');
    }
  }

  Map<String, IptvBookmarkItem> loadBookmarks() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_bookmarksKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map;
        final out = <String, IptvBookmarkItem>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            try {
              out[entry.key.toString()] = IptvBookmarkItem.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            } catch (_) {}
          }
        }
        return out;
      }
    } catch (e) {
      debugPrint('[IptvService] loadBookmarks error: $e');
    }
    return const {};
  }

  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = bookmarks.map((k, v) => MapEntry(k, v.toJson()));
      await box.put(_bookmarksKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvService] saveBookmarks error: $e');
    }
  }

  List<IptvEpgSource> loadSavedEpgSources() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_epgSourcesKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .whereType<Map>()
            .map((m) => IptvEpgSource.fromJson(Map<String, dynamic>.from(m)))
            .where((s) => s.url.trim().isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('[IptvService] loadSavedEpgSources error: $e');
    }
    return const [];
  }

  Future<void> saveEpgSources(List<IptvEpgSource> sources) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = sources.map((s) => s.toJson()).toList();
      await box.put(_epgSourcesKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvService] saveEpgSources error: $e');
    }
  }

  /// Formats one or more [playlists] as a standard `#EXTM3U` document for
  /// clipboard export or file sharing without duplicating serialization logic.
  static String buildM3uExportString(Iterable<IptvPlaylist> playlists) {
    final buffer = StringBuffer('#EXTM3U\n');
    for (final p in playlists) {
      for (final ch in p.channels) {
        final tvgId = ch.tvgId?.isNotEmpty == true ? ch.tvgId! : ch.id;
        final logo = ch.logo != null && ch.logo!.isNotEmpty
            ? ' tvg-logo="${ch.logo}"'
            : '';
        final group = ch.category != null && ch.category!.isNotEmpty
            ? ' group-title="${ch.category}"'
            : '';
        buffer.writeln('#EXTINF:-1 tvg-id="$tvgId"$logo$group,${ch.name}');
        buffer.writeln(ch.streamUrl);
      }
    }
    return buffer.toString();
  }

  // ─── Playlist Ingestion & Parsing ────────────────────────────────

  /// Refresh or parse an IPTV playlist based on its source type.
  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist) async {
    try {
      List<Channel> channels = [];
      String? detectedEpgUrl;

      final combinedHeaders = Map<String, String>.from(playlist.headers);
      if (playlist.userAgent != null && playlist.userAgent!.trim().isNotEmpty) {
        combinedHeaders['User-Agent'] = playlist.userAgent!.trim();
      }
      if (playlist.referer != null && playlist.referer!.trim().isNotEmpty) {
        combinedHeaders['Referer'] = playlist.referer!.trim();
      }
      if (playlist.cookie != null && playlist.cookie!.trim().isNotEmpty) {
        combinedHeaders['Cookie'] = playlist.cookie!.trim();
      }
      if (playlist.origin != null && playlist.origin!.trim().isNotEmpty) {
        combinedHeaders['Origin'] = playlist.origin!.trim();
      }
      if (playlist.authorization != null && playlist.authorization!.trim().isNotEmpty) {
        combinedHeaders['Authorization'] = playlist.authorization!.trim();
      }

      switch (playlist.sourceType) {
        case IptvSourceType.m3uUrl:
          final res = await parseM3uFromUrlWithMeta(
            playlist.url,
            playlist.id,
            headers: combinedHeaders,
            defaultDrm: playlist.drm,
            defaultManifestType: playlist.manifestType,
            requestType: playlist.requestType,
          );
          channels = res.channels;
          detectedEpgUrl = res.detectedEpgUrl;
          break;

        case IptvSourceType.m3uFile:
          final res = await parseM3uFromFileOrTextWithMeta(
            playlist.url,
            playlist.id,
            headers: combinedHeaders,
            defaultDrm: playlist.drm,
            defaultManifestType: playlist.manifestType,
          );
          channels = res.channels;
          detectedEpgUrl = res.detectedEpgUrl;
          break;

        case IptvSourceType.xtream:
          channels = await fetchXtreamChannels(
            hostUrl: playlist.url,
            username: playlist.username ?? '',
            password: playlist.password ?? '',
            playlistId: playlist.id,
            importLive: playlist.importLive,
            importVod: playlist.importVod,
            importSeries: playlist.importSeries,
            headers: combinedHeaders,
            streamFormat: playlist.streamFormat ?? 'TS',
            parserType: playlist.parserType ?? 'API Codes',
          );
          break;

        case IptvSourceType.stalker:
          channels = await fetchStalkerChannels(
            portalUrl: playlist.url,
            macAddress: playlist.macAddress ?? '',
            playlistId: playlist.id,
          );
          break;

        case IptvSourceType.directStream:
          final parsedUrl = parseUrlWithParams(
            playlist.url,
            baseHeaders: combinedHeaders,
            baseDrm: playlist.drm,
            baseManifestType: playlist.manifestType,
          );
          final directHeaders = Map<String, dynamic>.from(parsedUrl.headers);
          if (playlist.subtitleUrl != null && playlist.subtitleUrl!.trim().isNotEmpty) {
            directHeaders['X-Subtitle-Url'] = playlist.subtitleUrl!.trim();
          }
          if (playlist.manifestType != null &&
              playlist.manifestType!.trim().isNotEmpty &&
              playlist.manifestType!.trim() != 'auto' &&
              parsedUrl.drm == null) {
            directHeaders['X-Manifest-Type'] = playlist.manifestType!.trim();
          }
          final directChannel = Channel(
            id: '${playlist.id}_direct',
            name: playlist.name,
            streamUrl: parsedUrl.url,
            quality: 'HD',
            isLive: true,
            drm: parsedUrl.drm,
            headers: directHeaders,
            category: 'Direct Stream',
          );
          channels = [directChannel];
          break;
      }

      final effectiveEpgUrl =
          (playlist.epgUrl != null && playlist.epgUrl!.trim().isNotEmpty)
              ? playlist.epgUrl
              : detectedEpgUrl;

      return playlist.copyWith(
        channels: channels,
        channelCount: channels.length,
        epgUrl: effectiveEpgUrl,
        lastSync: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[IptvService] fetchAndParse failed for ${playlist.name}: $e');
      rethrow;
    }
  }

  /// Fetch an M3U/M3U8/JSON playlist over HTTP and parse in a background isolate.
  Future<List<Channel>> parseM3uFromUrl(
    String url,
    String playlistId, {
    Map<String, String>? headers,
  }) async {
    final res = await parseM3uFromUrlWithMeta(url, playlistId, headers: headers);
    return res.channels;
  }

  Future<ParsedPlaylistResult> parseM3uFromUrlWithMeta(
    String url,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
    String? requestType,
  }) async {
    final normalizedMethod = (requestType ?? 'download').toLowerCase();
    final Response<String> response = normalizedMethod == 'post'
        ? await _dio.post<String>(
            url,
            options: Options(
              headers: headers,
              responseType: ResponseType.plain,
            ),
          )
        : await _dio.get<String>(
            url,
            options: Options(
              headers: headers,
              responseType: ResponseType.plain,
            ),
          );

    final content = response.data ?? '';
    return compute(
      _isolateParsePlaylist,
      _ParseParams(
        content: content,
        playlistId: playlistId,
        baseHeaders: headers ?? const {},
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
      ),
    );
  }

  /// Parse M3U/JSON content from local file path or raw text.
  Future<List<Channel>> parseM3uFromFileOrText(
    String pathOrText,
    String playlistId,
  ) async {
    final res = await parseM3uFromFileOrTextWithMeta(pathOrText, playlistId);
    return res.channels;
  }

  Future<ParsedPlaylistResult> parseM3uFromFileOrTextWithMeta(
    String pathOrText,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
  }) async {
    String content = pathOrText;
    final trimmed = pathOrText.trim();
    if (!trimmed.contains('\n') &&
        (trimmed.startsWith('/') ||
            trimmed.startsWith('file://') ||
            RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed))) {
      final filePath =
          trimmed.startsWith('file://') ? Uri.parse(trimmed).toFilePath() : trimmed;
      final file = File(filePath);
      if (await file.exists()) {
        content = await file.readAsString();
      }
    }
    return compute(
      _isolateParsePlaylist,
      _ParseParams(
        content: content,
        playlistId: playlistId,
        baseHeaders: headers ?? const {},
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
      ),
    );
  }

  // ─── Playback Pre-Resolution (Stalker create_link & Remote ClearKey) ─

  /// Resolves lazy Stalker `create_link` URLs and remote ClearKey JSON endpoints
  /// immediately before opening `PlayerScreen`, matching `context.md` §10.
  Future<Channel> resolveChannelForPlayback(Channel ch) async {
    Channel resolved = ch;

    // 1. Lazy Stalker `create_link` resolution if needed
    final uri = Uri.tryParse(resolved.streamUrl);
    if (uri != null &&
        uri.queryParameters['action'] == 'create_link' &&
        uri.queryParameters['stalker_token'] != null) {
      final mac = uri.queryParameters['stalker_mac'] ?? '';
      final token = uri.queryParameters['stalker_token'] ?? '';
      final cmd = uri.queryParameters['cmd'] ?? '';
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      final portalBase = '${uri.scheme}://${uri.host}$portPart';
      final apiUrl =
          '$portalBase/server/load.php?type=itv&action=create_link&cmd=${Uri.encodeComponent(cmd)}&token=${Uri.encodeComponent(token)}&JsHttpRequest=1-xml';

      try {
        final res = await _dio.get(
          apiUrl,
          options: Options(
            headers: {
              if (mac.isNotEmpty) 'Cookie': 'mac=$mac',
              'User-Agent':
                  'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
            },
          ),
        );
        String? freshCmd;
        if (res.data is Map && res.data['js'] is Map) {
          freshCmd = res.data['js']['cmd']?.toString();
        } else if (res.data is String) {
          final decoded = jsonDecode(res.data as String);
          if (decoded is Map && decoded['js'] is Map) {
            freshCmd = decoded['js']['cmd']?.toString();
          }
        }
        if (freshCmd != null && freshCmd.isNotEmpty) {
          final cleanUrl = freshCmd
              .replaceFirst(RegExp(r'^(ffmpeg|ffrt)\s+', caseSensitive: false), '')
              .trim();
          if (cleanUrl.isNotEmpty) {
            resolved = _copyChannelWith(resolved, streamUrl: cleanUrl);
          }
        }
      } catch (e) {
        debugPrint('[IptvService] Stalker create_link resolution failed: $e');
      }
    }

    // 2. Fetch remote ClearKey JSON/TXT if ClearKey uses a remote URL
    final drm = resolved.drm;
    if (drm != null &&
        drm.isClearKey &&
        (drm.clearKeys == null || drm.clearKeys!.isEmpty) &&
        drm.licenseUrl != null &&
        drm.licenseUrl!.startsWith('http')) {
      try {
        final reqHeaders = <String, String>{
          for (final e in resolved.headers.entries) e.key: e.value.toString(),
          if (drm.licenseHeaders != null) ...drm.licenseHeaders!,
        };
        final res = await _dio.get<String>(
          drm.licenseUrl!,
          options: Options(headers: reqHeaders, responseType: ResponseType.plain),
        );
        final rawBody = res.data?.trim() ?? '';
        final parsedKeys = DrmConfig.parseClearKeys(rawBody);
        if (parsedKeys.isNotEmpty) {
          final first = parsedKeys.entries.first;
          resolved = _copyChannelWith(
            resolved,
            drm: drm.copyWith(
              kid: first.key,
              key: first.value,
              clearKeys: parsedKeys,
            ),
          );
        }
      } catch (e) {
        debugPrint('[IptvService] Remote ClearKey fetch failed: $e');
      }
    }

    return resolved;
  }

  Channel _copyChannelWith(Channel c, {String? streamUrl, DrmConfig? drm}) {
    return Channel(
      id: c.id,
      name: c.name,
      logo: c.logo,
      category: c.category,
      country: c.country,
      language: c.language,
      isLive: c.isLive,
      isTrending: c.isTrending,
      quality: c.quality,
      streamUrl: streamUrl ?? c.streamUrl,
      headers: c.headers,
      sortOrder: c.sortOrder,
      addedAt: c.addedAt,
      proxy: c.proxy,
      drm: drm ?? c.drm,
      playzLinks: c.playzLinks,
      isPlaylist: c.isPlaylist,
      linkNames: c.linkNames,
      hasVpnDetection: c.hasVpnDetection,
      streamServers: c.streamServers,
      tvgId: c.tvgId,
      tvgUrl: c.tvgUrl,
    );
  }

  // ─── XMLTV EPG Fetching & Isolate Parsing ────────────────────────

  Future<Map<String, List<IptvEpgProgramme>>> fetchAndParseEpg(
    String epgUrl, {
    Map<String, String>? headers,
  }) async {
    final trimmed = epgUrl.trim();
    if (trimmed.isEmpty) return const {};

    try {
      final response = await _dio.get<List<int>>(
        trimmed,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return const {};

      // Auto-detect GZIP magic header (0x1f 0x8b) for `.xml.gz` EPG feeds
      final List<int> xmlBytes = (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)
          ? gzip.decode(bytes)
          : bytes;

      final xmlContent = utf8.decode(xmlBytes, allowMalformed: true);
      return compute(parseXmltvEpg, xmlContent);
    } catch (e) {
      debugPrint('[IptvService] EPG fetch failed for $trimmed: $e');
      return const {};
    }
  }

  // ─── Xtream Codes API ────────────────────────────────────────────

  Future<List<Channel>> fetchXtreamChannels({
    required String hostUrl,
    required String username,
    required String password,
    required String playlistId,
    bool importLive = true,
    bool importVod = true,
    bool importSeries = true,
    Map<String, String>? headers,
    String streamFormat = 'TS',
    String parserType = 'API Codes',
  }) async {
    final cleanHost =
        hostUrl.endsWith('/') ? hostUrl.substring(0, hostUrl.length - 1) : hostUrl;
    final liveExt = streamFormat.trim().toLowerCase() == 'hls' ? 'm3u8' : 'ts';

    // When user selects `m3u_plus` parser type (matching APK Xtream dialog),
    // fetch directly via `/get.php?...&type=m3u_plus&output=...`.
    if (parserType.trim().toLowerCase() == 'm3u_plus') {
      try {
        final directM3uUrl =
            '$cleanHost/get.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&type=m3u_plus&output=$liveExt';
        final m3uRes = await parseM3uFromUrlWithMeta(
          directM3uUrl,
          playlistId,
          headers: headers,
        );
        if (m3uRes.channels.isNotEmpty) {
          return m3uRes.channels;
        }
      } catch (e) {
        debugPrint('[IptvService] Xtream m3u_plus fetch fallback to API: $e');
      }
    }

    final apiUrl =
        '$cleanHost/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';

    final List<Channel> allChannels = [];

    Future<Map<String, String>> loadCatMap(String action) async {
      final map = <String, String>{};
      try {
        final res = await _dio.get('$apiUrl&action=$action',
            options: Options(headers: headers));
        if (res.data is List) {
          for (final item in res.data as List) {
            if (item is Map) {
              final id = item['category_id']?.toString();
              final name = item['category_name']?.toString();
              if (id != null && name != null && name.isNotEmpty) {
                map[id] = name;
              }
            }
          }
        }
      } catch (_) {}
      return map;
    }

    final liveCatMap = importLive ? await loadCatMap('get_live_categories') : <String, String>{};
    final vodCatMap = importVod ? await loadCatMap('get_vod_categories') : <String, String>{};
    final seriesCatMap = importSeries ? await loadCatMap('get_series_categories') : <String, String>{};

    if (importLive) {
      try {
        final streamRes = await _dio.get('$apiUrl&action=get_live_streams',
            options: Options(headers: headers));
        if (streamRes.data is List) {
          int index = 0;
          for (final item in streamRes.data as List) {
            if (item is Map) {
              index++;
              final streamId = item['stream_id']?.toString() ?? '$index';
              final name = item['name']?.toString() ?? 'Stream $index';
              final logo = item['stream_icon']?.toString();
              final catId = item['category_id']?.toString();
              final epgId = item['epg_channel_id']?.toString();
              final category = liveCatMap[catId] ?? 'Live TV';
              final streamUrl = '$cleanHost/live/$username/$password/$streamId.$liveExt';
              allChannels.add(
                Channel(
                  id: '${playlistId}_xc_live_$streamId',
                  name: name,
                  logo: (logo != null && logo.isNotEmpty) ? logo : null,
                  category: category,
                  tvgId: (epgId != null && epgId.isNotEmpty) ? epgId : null,
                  streamUrl: streamUrl,
                  headers: headers ?? const {},
                  isLive: true,
                  quality: 'HD',
                  sortOrder: index,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[IptvService] Xtream Live Streams error: $e');
      }
    }

    if (importVod) {
      try {
        final vodRes = await _dio.get('$apiUrl&action=get_vod_streams',
            options: Options(headers: headers));
        if (vodRes.data is List) {
          int index = 0;
          for (final item in vodRes.data as List) {
            if (item is Map) {
              index++;
              final streamId = item['stream_id']?.toString() ?? '$index';
              final name = item['name']?.toString() ?? 'Movie $index';
              final logo = item['stream_icon']?.toString();
              final catId = item['category_id']?.toString();
              final ext = item['container_extension']?.toString() ?? 'mp4';
              final streamUrl = '$cleanHost/movie/$username/$password/$streamId.$ext';

              allChannels.add(
                Channel(
                  id: '${playlistId}_xc_vod_$streamId',
                  name: name,
                  logo: (logo != null && logo.isNotEmpty) ? logo : null,
                  category: vodCatMap[catId] ?? 'Movies / VOD',
                  streamUrl: streamUrl,
                  headers: headers ?? const {},
                  isLive: false,
                  quality: 'FHD',
                  sortOrder: allChannels.length + index,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[IptvService] Xtream VOD error: $e');
      }
    }

    if (importSeries) {
      try {
        final seriesRes = await _dio.get('$apiUrl&action=get_series',
            options: Options(headers: headers));
        if (seriesRes.data is List) {
          int index = 0;
          for (final item in seriesRes.data as List) {
            if (item is Map) {
              index++;
              final seriesId = item['series_id']?.toString() ?? '$index';
              final name = item['name']?.toString() ?? 'Series $index';
              final logo = item['cover']?.toString();
              final catId = item['category_id']?.toString();

              allChannels.add(
                Channel(
                  id: '${playlistId}_xc_series_$seriesId',
                  name: name,
                  logo: (logo != null && logo.isNotEmpty) ? logo : null,
                  category: seriesCatMap[catId] ?? 'Series',
                  streamUrl: '$cleanHost/series/$username/$password/$seriesId',
                  headers: headers ?? const {},
                  isLive: false,
                  quality: 'HD',
                  sortOrder: allChannels.length + index,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[IptvService] Xtream Series error: $e');
      }
    }

    // Fallback to M3U endpoint (`/get.php?type=m3u_plus&output=...`) matching `context.md` §2
    if (allChannels.isEmpty) {
      try {
        final fallbackUrl =
            '$cleanHost/get.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&type=m3u_plus&output=$liveExt';
        final m3uRes = await parseM3uFromUrlWithMeta(fallbackUrl, playlistId, headers: headers);
        return m3uRes.channels;
      } catch (_) {}
    }

    return allChannels;
  }

  // ─── Stalker / MAC Portal ────────────────────────────────────────

  Future<List<Channel>> fetchStalkerChannels({
    required String portalUrl,
    required String macAddress,
    required String playlistId,
  }) async {
    final cleanUrl =
        portalUrl.endsWith('/') ? portalUrl.substring(0, portalUrl.length - 1) : portalUrl;
    final cleanMac = macAddress.replaceAll('-', ':').toUpperCase();
    final handshakeUrl =
        '$cleanUrl/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml';

    try {
      final res = await _dio.get(
        handshakeUrl,
        options: Options(
          headers: {
            'Cookie': 'mac=$cleanMac',
            'User-Agent':
                'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
          },
        ),
      );

      String token = '';
      if (res.data is Map && res.data['js'] is Map) {
        token = res.data['js']['token']?.toString() ?? '';
      }

      // Fetch genres for category names
      final genreMap = <String, String>{};
      try {
        final genreRes = await _dio.get(
          '$cleanUrl/server/load.php?type=itv&action=get_genres&token=$token&JsHttpRequest=1-xml',
          options: Options(headers: {'Cookie': 'mac=$cleanMac'}),
        );
        if (genreRes.data is Map && genreRes.data['js'] is List) {
          for (final g in genreRes.data['js'] as List) {
            if (g is Map && g['id'] != null && g['title'] != null) {
              genreMap[g['id'].toString()] = g['title'].toString();
            }
          }
        }
      } catch (_) {}

      final allChannelsUrl =
          '$cleanUrl/server/load.php?type=itv&action=get_all_channels&token=$token&JsHttpRequest=1-xml';
      final chRes = await _dio.get(
        allChannelsUrl,
        options: Options(headers: {'Cookie': 'mac=$cleanMac'}),
      );

      if (chRes.data is Map && chRes.data['js'] is Map && chRes.data['js']['data'] is List) {
        final List<Channel> channels = [];
        final items = chRes.data['js']['data'] as List;
        int i = 0;
        for (final item in items) {
          if (item is Map) {
            i++;
            final id = item['id']?.toString() ?? '$i';
            final name = item['name']?.toString() ?? 'Channel $i';
            final cmd = item['cmd']?.toString() ?? '';
            final logo = item['logo']?.toString();
            final genreId = item['tv_genre_id']?.toString();

            final rawStream = cmd.replaceFirst(RegExp(r'^ffmpeg\s+', caseSensitive: false), '').trim();
            // Store lazy create_link trigger when portal requires token/cmd exchange (`context.md` §2 & §10)
            final effectiveUrl = (rawStream.startsWith('http://') || rawStream.startsWith('https://'))
                ? rawStream
                : '$cleanUrl?action=create_link&stalker_mac=${Uri.encodeComponent(cleanMac)}&stalker_token=${Uri.encodeComponent(token)}&cmd=${Uri.encodeComponent(cmd)}';

            channels.add(
              Channel(
                id: '${playlistId}_stalker_$id',
                name: name,
                logo: (logo != null && logo.isNotEmpty)
                    ? (logo.startsWith('http') ? logo : '$cleanUrl/$logo')
                    : null,
                category: genreMap[genreId] ?? 'Stalker TV',
                streamUrl: effectiveUrl,
                headers: {'Cookie': 'mac=$cleanMac'},
                isLive: true,
                quality: 'HD',
                sortOrder: i,
              ),
            );
          }
        }
        return channels;
      }
    } catch (e) {
      debugPrint('[IptvService] Stalker portal load notice: $e');
    }

    return [
      Channel(
        id: '${playlistId}_stalker_root',
        name: 'Stalker Portal ($cleanMac)',
        streamUrl: cleanUrl,
        headers: {'Cookie': 'mac=$cleanMac'},
        category: 'Stalker Portal',
        isLive: true,
      ),
    ];
  }

  /// Probe remote HTTP/HTTPS URL Content-Type header for live MIME inspection.
  Future<String?> probeUrlMimeType(
    String url, {
    Map<String, String>? headers,
  }) async {
    final trimmed = url.trim();
    final lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }

    final probeOptions = Options(
      headers: headers,
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    );

    try {
      final headRes = await _dio.head<dynamic>(trimmed, options: probeOptions);
      final rawCt = headRes.headers.value('content-type');
      if (rawCt != null && rawCt.trim().isNotEmpty && headRes.statusCode != 405) {
        return rawCt.split(';').first.trim();
      }
    } catch (_) {
      // Fall through to lightweight byte-range GET below.
    }

    try {
      final rangeHeaders = <String, String>{
        if (headers != null) ...headers,
        'Range': 'bytes=0-0',
      };
      final getRes = await _dio.get<dynamic>(
        trimmed,
        options: probeOptions.copyWith(
          headers: rangeHeaders,
          responseType: ResponseType.stream,
        ),
      );
      final rawCt = getRes.headers.value('content-type');
      if (getRes.data is ResponseBody) {
        await (getRes.data as ResponseBody).stream.drain<void>().catchError((_) {});
      }
      if (rawCt != null && rawCt.trim().isNotEmpty) {
        return rawCt.split(';').first.trim();
      }
    } catch (_) {}

    return null;
  }

  /// Handshake and fetch profile metadata (`token`, `expiry`) from a Stalker portal.
  Future<StalkerTestResult> testStalkerConnection({
    required String portalUrl,
    required String macAddress,
  }) async {
    final trimmed = portalUrl.trim();
    final cleanUrl =
        trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    final cleanMac = macAddress.trim().replaceAll('-', ':').toUpperCase();
    const stbUserAgent =
        'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

    try {
      final res = await _dio.get<dynamic>(
        '$cleanUrl/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml',
        options: Options(
          headers: {'Cookie': 'mac=$cleanMac', 'User-Agent': stbUserAgent},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      dynamic payload = res.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }
      final js = (payload is Map) ? payload['js'] : null;
      final token = (js is Map) ? js['token']?.toString().trim() : null;
      if (token == null || token.isEmpty) {
        return StalkerTestResult(
          mac: cleanMac,
          error: 'Handshake succeeded without token',
        );
      }

      String? expiry;
      try {
        final profileRes = await _dio.get<dynamic>(
          '$cleanUrl/server/load.php?type=stb&action=get_profile&token=${Uri.encodeComponent(token)}&JsHttpRequest=1-xml',
          options: Options(
            headers: {'Cookie': 'mac=$cleanMac', 'User-Agent': stbUserAgent},
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        dynamic profilePayload = profileRes.data;
        if (profilePayload is String) {
          profilePayload = jsonDecode(profilePayload);
        }
        final pJs = (profilePayload is Map) ? profilePayload['js'] : null;
        if (pJs is Map) {
          for (final key in const [
            'expire_billing_date',
            'tariff_expired_date',
            'phone',
            'end_date',
          ]) {
            final v = pJs[key]?.toString().trim();
            if (v != null && v.isNotEmpty && v != '0000-00-00 00:00:00') {
              expiry = v;
              break;
            }
          }
        }
      } catch (_) {
        // Profile info is optional; token alone proves connectivity.
      }

      return StalkerTestResult(
        token: token,
        expiry: expiry,
        mac: cleanMac,
      );
    } catch (e) {
      return StalkerTestResult(
        mac: cleanMac,
        error: e.toString(),
      );
    }
  }
}

// ─── Top-Level Parsers (Test-Accessible & Isolate-Safe) ─────────────

class _ParseParams {
  final String content;
  final String playlistId;
  final Map<String, String> baseHeaders;
  final DrmConfig? defaultDrm;
  final String? defaultManifestType;

  const _ParseParams({
    required this.content,
    required this.playlistId,
    this.baseHeaders = const {},
    this.defaultDrm,
    this.defaultManifestType,
  });
}

ParsedPlaylistResult _isolateParsePlaylist(_ParseParams params) {
  return parseM3uOrJsonContent(
    params.content,
    params.playlistId,
    baseHeaders: params.baseHeaders,
    defaultDrm: params.defaultDrm,
    defaultManifestType: params.defaultManifestType,
  );
}

/// Parses either a M3U/M3U8 text playlist or a JSON playlist (`M3U8Entry` array
/// or flat channel array) per `context.md` §4.2.
ParsedPlaylistResult parseM3uOrJsonContent(
  String content,
  String playlistId, {
  Map<String, String> baseHeaders = const {},
  DrmConfig? defaultDrm,
  String? defaultManifestType,
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const ParsedPlaylistResult(channels: []);
  }

  // 1. JSON playlist detection (`Lx/iLLiL1liiI;->iLlll1lIIL`)
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final List rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map) {
        final inner = decoded['channels'] ?? decoded['items'] ?? decoded['entries'] ?? decoded['data'];
        if (inner is List) {
          rawList = inner;
        } else {
          rawList = [decoded];
        }
      } else {
        rawList = const [];
      }

      final channels = <Channel>[];
      int index = 0;
      for (final row in rawList) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);

        final extInf = map['EXTINF'] is Map ? Map<String, dynamic>.from(map['EXTINF'] as Map) : null;
        final kodiProp = map['KODIPROP'] is Map ? Map<String, dynamic>.from(map['KODIPROP'] as Map) : null;
        final extVlcOpt = map['EXTVLCOPT'] is Map ? Map<String, dynamic>.from(map['EXTVLCOPT'] as Map) : null;

        final rawUrl = (map['url'] ?? map['stream_url'] ?? map['streamUrl'] ?? '').toString().trim();
        if (rawUrl.isEmpty) continue;

        index++;
        final name = (extInf?['title'] ??
                extInf?['tvgName'] ??
                extInf?['tvg_name'] ??
                map['name'] ??
                map['title'] ??
                'Channel $index')
            .toString()
            .trim();
        final logo = (extInf?['tvgLogo'] ??
                extInf?['tvg_logo'] ??
                extInf?['logo'] ??
                map['logo'] ??
                map['tvg-logo'])
            ?.toString();
        final group = (extInf?['groupTitle'] ??
                extInf?['group_title'] ??
                extInf?['group-title'] ??
                map['group'] ??
                map['category'])
            ?.toString();
        final tvgId = (extInf?['tvgId'] ??
                extInf?['tvg_id'] ??
                extInf?['tvg-id'] ??
                map['tvgId'] ??
                map['tvg_id'])
            ?.toString();
        final tvgUrl = (extInf?['tvgUrl'] ??
                extInf?['tvg_url'] ??
                extInf?['tvg-url'] ??
                map['tvgUrl'] ??
                map['tvg_url'])
            ?.toString();

        final entryHeaders = Map<String, String>.from(baseHeaders);
        if (map['headers'] is Map) {
          for (final h in (map['headers'] as Map).entries) {
            entryHeaders[h.key.toString()] = h.value.toString();
          }
        }
        final exthttpRaw = map['exthttp']?.toString();
        if (exthttpRaw != null && exthttpRaw.trim().isNotEmpty) {
          _mergeExtHttpHeaders(exthttpRaw, entryHeaders);
        }
        final authRaw = map['authorization']?.toString();
        if (authRaw != null && authRaw.trim().isNotEmpty) {
          entryHeaders['Authorization'] = authRaw.trim();
        }
        if (extVlcOpt != null) {
          final ua = extVlcOpt['httpUserAgent'] ?? extVlcOpt['http-user-agent'];
          final ref = extVlcOpt['httpReferrer'] ?? extVlcOpt['http-referrer'];
          final cookie = extVlcOpt['cookie'];
          final origin = extVlcOpt['httpOrigin'] ?? extVlcOpt['http-origin'];
          if (ua != null && ua.toString().isNotEmpty) entryHeaders['User-Agent'] = ua.toString();
          if (ref != null && ref.toString().isNotEmpty) entryHeaders['Referer'] = ref.toString();
          if (cookie != null && cookie.toString().isNotEmpty) entryHeaders['Cookie'] = cookie.toString();
          if (origin != null && origin.toString().isNotEmpty) entryHeaders['Origin'] = origin.toString();
        }

        DrmConfig? entryDrm = DrmConfig.fromJson(map['drm']) ?? defaultDrm;
        if (kodiProp != null) {
          final licType = (kodiProp['licenseType'] ?? kodiProp['license_type'])?.toString();
          final licKey = (kodiProp['licenseKey'] ?? kodiProp['license_key'])?.toString();
          final manifest = (kodiProp['manifestType'] ?? kodiProp['manifest_type'])?.toString();
          entryDrm = _buildDrmFromKodiProps(
            licenseType: licType,
            licenseKey: licKey,
            manifestType: manifest ?? defaultManifestType,
            headers: entryHeaders,
          ) ??
              entryDrm;
        }

        final parsedUrl = parseUrlWithParams(
          rawUrl,
          baseHeaders: entryHeaders,
          baseDrm: entryDrm,
          baseManifestType: defaultManifestType,
        );

        channels.add(
          Channel(
            id: '${playlistId}_j_${(tvgId != null && tvgId.isNotEmpty) ? tvgId : index}_$index',
            name: name.isEmpty ? 'Channel $index' : name,
            logo: (logo != null && logo.trim().isNotEmpty) ? logo.trim() : null,
            category: (group != null && group.trim().isNotEmpty) ? group.trim() : 'Undefined',
            tvgId: (tvgId != null && tvgId.trim().isNotEmpty) ? tvgId.trim() : null,
            tvgUrl: (tvgUrl != null && tvgUrl.trim().isNotEmpty) ? tvgUrl.trim() : null,
            streamUrl: parsedUrl.url,
            headers: parsedUrl.headers,
            drm: parsedUrl.drm,
            isLive: true,
            quality: _inferQualityBadge(name),
            sortOrder: index,
          ),
        );
      }

      if (channels.isNotEmpty) {
        return ParsedPlaylistResult(channels: channels);
      }
    } catch (_) {
      // Fall through to M3U parser if not valid playlist JSON
    }
  }

  // 2. Streaming M3U / M3U8 line-by-line parser (`Lx/IILLII1LIiL1;->i1lLLiILI`)
  final lines = const LineSplitter().convert(content);
  final List<Channel> channels = [];

  String? detectedEpgUrl;
  String? currentName;
  String? currentLogo;
  String? currentGroup;
  String? currentTvgId;
  String? currentTvgUrl;
  Map<String, String> currentHeaders = Map<String, String>.from(baseHeaders);
  String? currentLicenseType;
  String? currentLicenseKey;
  String? currentManifestType = defaultManifestType;
  bool hasExtInf = false;

  void resetItemState() {
    currentName = null;
    currentLogo = null;
    currentGroup = null;
    currentTvgId = null;
    currentTvgUrl = null;
    currentHeaders = Map<String, String>.from(baseHeaders);
    currentLicenseType = null;
    currentLicenseKey = null;
    currentManifestType = defaultManifestType;
    hasExtInf = false;
  }

  int index = 0;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXTM3U')) {
      final epgAttr = _extractAttr(line, ['url-tvg', 'x-tvg-url', 'tvg-url']);
      if (epgAttr != null && epgAttr.isNotEmpty) {
        detectedEpgUrl = epgAttr;
      }
      continue;
    }

    if (line.startsWith('#EXTINF:')) {
      resetItemState();
      hasExtInf = true;

      currentLogo = _extractAttr(line, ['tvg-logo']);
      currentGroup = _extractAttr(line, ['group-title']);
      currentTvgId = _extractAttr(line, ['tvg-id']);
      currentTvgUrl = _extractAttr(line, ['tvg-url']);
      final tvgName = _extractAttr(line, ['tvg-name']);

      final commaIndex = line.lastIndexOf(',');
      if (commaIndex != -1 && commaIndex < line.length - 1) {
        final titlePart = line.substring(commaIndex + 1).trim();
        currentName = titlePart.isNotEmpty ? titlePart : tvgName;
      } else {
        currentName = tvgName;
      }
      continue;
    }

    if (line.startsWith('#EXTVLCOPT:')) {
      final opt = line.substring('#EXTVLCOPT:'.length).trim();
      final eqIdx = opt.indexOf('=');
      if (eqIdx > 0) {
        final k = opt.substring(0, eqIdx).trim().toLowerCase();
        final v = opt.substring(eqIdx + 1).trim();
        if (v.isNotEmpty) {
          switch (k) {
            case 'http-user-agent':
              currentHeaders['User-Agent'] = v;
              break;
            case 'http-referrer':
            case 'http-referer':
              currentHeaders['Referer'] = v;
              break;
            case 'cookie':
              currentHeaders['Cookie'] = v;
              break;
            case 'http-origin':
              currentHeaders['Origin'] = v;
              break;
          }
        }
      }
      continue;
    }

    if (line.startsWith('#EXTHTTP:')) {
      final rawHttp = line.substring('#EXTHTTP:'.length).trim();
      if (rawHttp.isNotEmpty) {
        _mergeExtHttpHeaders(rawHttp, currentHeaders);
      }
      continue;
    }

    if (line.startsWith('#KODIPROP:')) {
      final prop = line.substring('#KODIPROP:'.length).trim();
      final eqIdx = prop.indexOf('=');
      if (eqIdx > 0) {
        final k = prop.substring(0, eqIdx).trim().toLowerCase();
        final v = prop.substring(eqIdx + 1).trim();
        if (k.contains('license_type') || k == 'licensetype') {
          currentLicenseType = v.toLowerCase();
        } else if (k.contains('license_key') || k == 'licensekey') {
          currentLicenseKey = v;
        } else if (k.contains('manifest_type') || k == 'manifesttype') {
          currentManifestType = v.toLowerCase();
        }
      }
      continue;
    }

    // Commented stream prefixes accepted by `Lx/IILLII1LIiL1` (`#http`, `#https`, `#rtmp`, `#rtsp`)
    String? candidateStream;
    final lower = line.toLowerCase();
    if (!line.startsWith('#')) {
      candidateStream = line;
    } else if (lower.startsWith('#http://') ||
        lower.startsWith('#https://') ||
        lower.startsWith('#rtmp://') ||
        lower.startsWith('#rtsp://')) {
      candidateStream = line.substring(1).trim();
    }

    if (candidateStream == null) continue;

    final isSupportedProtocol =
        RegExp(r'^(https?|rtmp|rtsp|mms|ftp)://', caseSensitive: false)
                .hasMatch(candidateStream) ||
            hasExtInf;
    if (!isSupportedProtocol) {
      continue;
    }

    final baseDrm = _buildDrmFromKodiProps(
          licenseType: currentLicenseType,
          licenseKey: currentLicenseKey,
          manifestType: currentManifestType,
          headers: currentHeaders,
        ) ??
        defaultDrm;

    final parsedUrl = parseUrlWithParams(
      candidateStream,
      baseHeaders: currentHeaders,
      baseDrm: baseDrm,
      baseManifestType: currentManifestType,
    );

    index++;
    final displayTitle = (currentName != null && currentName!.trim().isNotEmpty)
        ? currentName!.trim()
        : 'Channel $index';
    final safeIdPart =
        (currentTvgId != null && currentTvgId!.trim().isNotEmpty)
            ? currentTvgId!.trim()
            : '$index';

    channels.add(
      Channel(
        id: '${playlistId}_c_${safeIdPart}_$index',
        name: displayTitle,
        logo: (currentLogo != null && currentLogo!.trim().isNotEmpty)
            ? currentLogo!.trim()
            : null,
        category: (currentGroup != null && currentGroup!.trim().isNotEmpty)
            ? currentGroup!.trim()
            : 'Undefined',
        tvgId: (currentTvgId != null && currentTvgId!.trim().isNotEmpty)
            ? currentTvgId!.trim()
            : null,
        tvgUrl: (currentTvgUrl != null && currentTvgUrl!.trim().isNotEmpty)
            ? currentTvgUrl!.trim()
            : null,
        streamUrl: parsedUrl.url,
        headers: parsedUrl.headers,
        drm: parsedUrl.drm,
        isLive: true,
        quality: _inferQualityBadge(displayTitle),
        sortOrder: index,
      ),
    );

    resetItemState();
  }

  return ParsedPlaylistResult(
    channels: channels,
    detectedEpgUrl: detectedEpgUrl,
  );
}

String? _extractAttr(String line, List<String> names) {
  for (final name in names) {
    final quoted = RegExp('$name="([^"]*)"', caseSensitive: false).firstMatch(line);
    if (quoted != null) return quoted.group(1)?.trim();
    final singleQuoted =
        RegExp("$name='([^']*)'", caseSensitive: false).firstMatch(line);
    if (singleQuoted != null) return singleQuoted.group(1)?.trim();
  }
  return null;
}

String _inferQualityBadge(String name) {
  final upper = name.toUpperCase();
  if (upper.contains('4K') || upper.contains('UHD')) return '4K';
  if (upper.contains('FHD') || upper.contains('1080')) return 'FHD';
  if (upper.contains('SD')) return 'SD';
  return 'HD';
}

void _mergeExtHttpHeaders(String raw, Map<String, String> target) {
  String candidate = raw.trim();
  if (!candidate.startsWith('{') && _looksLikeBase64(candidate)) {
    try {
      candidate = utf8.decode(base64Decode(base64.normalize(candidate)));
    } catch (_) {}
  }
  if (!candidate.startsWith('{')) return;
  try {
    final decoded = jsonDecode(candidate);
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final k = entry.key.toString();
        var v = entry.value?.toString() ?? '';
        // `Lx/IILLII1LIiL1`: auto Base64-decode `dt-custom-data` if valid Base64
        if (k.toLowerCase() == 'dt-custom-data' && _looksLikeBase64(v)) {
          try {
            final decodedCustom =
                utf8.decode(base64Decode(base64.normalize(v.trim())));
            if (decodedCustom.isNotEmpty) v = decodedCustom;
          } catch (_) {}
        }
        target[k] = v;
      }
    }
  } catch (_) {}
}

bool _looksLikeBase64(String s) {
  final trimmed = s.trim();
  if (trimmed.length < 4 || trimmed.contains('{') || trimmed.contains(' ')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9+/_\-=]+$').hasMatch(trimmed);
}

DrmConfig? _buildDrmFromKodiProps({
  String? licenseType,
  String? licenseKey,
  String? manifestType,
  Map<String, String>? headers,
}) {
  final typeRaw = licenseType?.trim().toLowerCase() ?? '';
  final keyRaw = licenseKey?.trim() ?? '';

  if (typeRaw.isEmpty && keyRaw.isEmpty && (manifestType == null || manifestType.isEmpty)) {
    return null;
  }

  DrmType resolvedType;
  if (typeRaw.contains('clearkey') || typeRaw == 'org.w3.clearkey') {
    resolvedType = DrmType.clearkey;
  } else if (typeRaw.contains('playready') || typeRaw.contains('com.microsoft.playready')) {
    resolvedType = DrmType.playready;
  } else if (typeRaw.contains('widevine') || typeRaw.contains('com.widevine.alpha')) {
    resolvedType = DrmType.widevine;
  } else if (keyRaw.startsWith('{') || (!keyRaw.startsWith('http') && keyRaw.contains(':'))) {
    resolvedType = DrmType.clearkey;
  } else if (keyRaw.startsWith('http')) {
    resolvedType = DrmType.widevine;
  } else {
    return null;
  }

  if (resolvedType == DrmType.clearkey) {
    if (keyRaw.startsWith('http://') || keyRaw.startsWith('https://')) {
      return DrmConfig(
        type: DrmType.clearkey,
        licenseUrl: keyRaw,
        licenseHeaders: headers?.isNotEmpty == true ? Map.from(headers!) : null,
        manifestType: manifestType,
      );
    }
    final parsedKeys = DrmConfig.parseClearKeys(keyRaw);
    if (parsedKeys.isNotEmpty) {
      final first = parsedKeys.entries.first;
      return DrmConfig(
        type: DrmType.clearkey,
        kid: first.key,
        key: first.value,
        clearKeys: parsedKeys,
        manifestType: manifestType,
      );
    }
    return DrmConfig(type: DrmType.clearkey, manifestType: manifestType);
  }

  return DrmConfig(
    type: resolvedType,
    licenseUrl: keyRaw.isNotEmpty ? keyRaw : null,
    licenseHeaders: headers?.isNotEmpty == true ? Map.from(headers!) : null,
    manifestType: manifestType,
  );
}

/// Parses `|`-delimited stream parameters matching `DrmPlayerManager.processUrlParams`
/// (`context.md` §10).
({String url, Map<String, String> headers, DrmConfig? drm}) parseUrlWithParams(
  String rawUrl, {
  Map<String, String> baseHeaders = const {},
  DrmConfig? baseDrm,
  String? baseManifestType,
}) {
  final headers = Map<String, String>.from(baseHeaders);
  String? licenseType;
  String? licenseKey;
  String? manifestType = baseManifestType;
  DrmConfig? drm = baseDrm;

  final pipeIdx = rawUrl.indexOf('|');
  if (pipeIdx == -1) {
    return (url: rawUrl.trim(), headers: headers, drm: drm);
  }

  final cleanUrl = rawUrl.substring(0, pipeIdx).trim();
  final paramString = rawUrl.substring(pipeIdx + 1).trim();

  const metadataKeys = {
    'event',
    'title',
    'duration',
    'formatted',
    'tvglogo',
    'datemodified',
    'grouptitle',
  };

  final unusedParams = <String, String>{};
  bool sawExtHttp = false;

  for (final token in paramString.split('&')) {
    if (token.trim().isEmpty) continue;
    final eqIdx = token.indexOf('=');
    if (eqIdx <= 0) continue;

    final rawKey = token.substring(0, eqIdx).trim();
    final keyLower = rawKey.toLowerCase();
    var value = token.substring(eqIdx + 1).trim();
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {}

    if (metadataKeys.contains(keyLower)) {
      continue;
    }

    switch (keyLower) {
      case 'exthttp':
      case 'extraheader':
        sawExtHttp = true;
        _mergeExtHttpHeaders(value, headers);
        break;
      case 'authorization':
        headers['Authorization'] = value;
        break;
      case 'user-agent':
      case 'useragent':
      case 'httpuseragent':
      case 'http-useragent':
        headers['User-Agent'] = value;
        break;
      case 'referer':
      case 'referrer':
      case 'httpreferer':
      case 'httpreferrer':
        headers['Referer'] = value;
        break;
      case 'origin':
      case 'httporigin':
        headers['Origin'] = value;
        break;
      case 'cookie':
      case 'httpcookie':
        headers['Cookie'] = value;
        break;
      case 'drmscheme':
      case 'licensetype':
        licenseType = value.toLowerCase();
        break;
      case 'drmlicense':
      case 'licensekey':
      case 'clearkeys':
      case 'clearkey':
      case 'widevine':
      case 'playready':
        if (keyLower == 'clearkeys' || keyLower == 'clearkey') {
          licenseType ??= 'clearkey';
        } else if (keyLower == 'widevine') {
          licenseType ??= 'widevine';
        } else if (keyLower == 'playready') {
          licenseType ??= 'playready';
        }
        licenseKey = value;
        break;
      case 'manifesttype':
      case 'manifest_type':
      case 'manifest-type':
      case 'mime':
      case 'mimetype':
        manifestType = value.toLowerCase();
        break;
      default:
        unusedParams[rawKey] = value;
    }
  }

  if (!sawExtHttp && unusedParams.isNotEmpty) {
    headers.addAll(unusedParams);
  }

  final overrideDrm = _buildDrmFromKodiProps(
    licenseType: licenseType ?? drm?.type.name,
    licenseKey: licenseKey ?? drm?.licenseUrl,
    manifestType: manifestType,
    headers: headers,
  );

  if (overrideDrm != null) {
    drm = overrideDrm;
  } else if (drm != null && manifestType != null && drm.manifestType != manifestType) {
    drm = drm.copyWith(manifestType: manifestType);
  }

  return (url: cleanUrl, headers: headers, drm: drm);
}

// ─── XMLTV EPG Parser (Isolate-Runnable & Testable) ─────────────────

final RegExp _kChannelTagRegex = RegExp(
  r'<channel\b[^>]*id="([^"]*)"[^>]*>([\s\S]*?)<\/channel>',
  caseSensitive: false,
);
final RegExp _kDisplayNameRegex = RegExp(
  r'<display-name[^>]*>([\s\S]*?)<\/display-name>',
  caseSensitive: false,
);
final RegExp _kProgrammeTagRegex = RegExp(
  r'<programme\b([^>]*)>([\s\S]*?)<\/programme>',
  caseSensitive: false,
);
final RegExp _kTitleTagRegex = RegExp(
  r'<title[^>]*>([\s\S]*?)<\/title>',
  caseSensitive: false,
);
final RegExp _kDescTagRegex = RegExp(
  r'<desc[^>]*>([\s\S]*?)<\/desc>',
  caseSensitive: false,
);

/// Parses an XMLTV EPG document into normalized channel keys (`lowercase + no spaces`)
/// mapping both `<channel id>` and every `<display-name>` alias (`context.md` §8.1).
Map<String, List<IptvEpgProgramme>> parseXmltvEpg(String xmlContent) {
  if (xmlContent.trim().isEmpty) return const {};

  final channelAliases = <String, Set<String>>{};
  for (final m in _kChannelTagRegex.allMatches(xmlContent)) {
    final id = m.group(1)?.trim();
    final body = m.group(2) ?? '';
    if (id == null || id.isEmpty) continue;
    final normId = normalizeEpgKey(id);
    final aliases = channelAliases.putIfAbsent(normId, () => {normId});
    for (final dn in _kDisplayNameRegex.allMatches(body)) {
      final nameText = _decodeXmlEntities(dn.group(1) ?? '');
      if (nameText.isNotEmpty) {
        aliases.add(normalizeEpgKey(nameText));
      }
    }
  }

  final out = <String, List<IptvEpgProgramme>>{};
  for (final m in _kProgrammeTagRegex.allMatches(xmlContent)) {
    final attrs = m.group(1) ?? '';
    final body = m.group(2) ?? '';

    final chRaw = _extractAttr(attrs, ['channel']);
    final startRaw = _extractAttr(attrs, ['start']);
    final stopRaw = _extractAttr(attrs, ['stop']);
    if (chRaw == null || startRaw == null || stopRaw == null) continue;

    final startTime = _parseXmltvTimestamp(startRaw);
    final stopTime = _parseXmltvTimestamp(stopRaw);
    if (startTime == null || stopTime == null) continue;

    final titleMatch = _kTitleTagRegex.firstMatch(body);
    final title = _decodeXmlEntities(titleMatch?.group(1) ?? '').trim();
    if (title.isEmpty) continue;

    final descMatch = _kDescTagRegex.firstMatch(body);
    final desc = descMatch != null
        ? _decodeXmlEntities(descMatch.group(1) ?? '').trim()
        : null;

    final normCh = normalizeEpgKey(chRaw);
    final prog = IptvEpgProgramme(
      channelKey: normCh,
      title: title,
      description: (desc != null && desc.isNotEmpty) ? desc : null,
      startTime: startTime,
      stopTime: stopTime,
    );

    final targetKeys = channelAliases[normCh] ?? {normCh};
    for (final key in targetKeys) {
      out.putIfAbsent(key, () => <IptvEpgProgramme>[]).add(prog);
    }
  }

  for (final list in out.values) {
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
  }
  return out;
}

DateTime? _parseXmltvTimestamp(String raw) {
  final cleaned = raw.trim();
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:\s*([+-]\d{2}:?\d{2}|Z))?',
  ).firstMatch(cleaned);
  if (match == null) return DateTime.tryParse(cleaned)?.toLocal();

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '0') ?? 0;
  final tzRaw = match.group(7);

  if (tzRaw == null) {
    return DateTime(year, month, day, hour, minute, second);
  }
  if (tzRaw == 'Z') {
    return DateTime.utc(year, month, day, hour, minute, second).toLocal();
  }

  final compactTz = tzRaw.replaceAll(':', '');
  if (compactTz.length == 5) {
    final sign = compactTz[0] == '-' ? -1 : 1;
    final tzH = int.tryParse(compactTz.substring(1, 3)) ?? 0;
    final tzM = int.tryParse(compactTz.substring(3, 5)) ?? 0;
    final offset = Duration(hours: tzH, minutes: tzM) * sign;
    return DateTime.utc(year, month, day, hour, minute, second)
        .subtract(offset)
        .toLocal();
  }
  return DateTime(year, month, day, hour, minute, second);
}

String _decodeXmlEntities(String input) {
  return input
      .replaceAll('<![CDATA[', '')
      .replaceAll(']]>', '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .trim();
}
