import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;

import '../../models/channel.dart';
import '../../models/drm_config.dart';
import '../../models/iptv_playlist.dart';
import 'playlist_parser.dart';
import 'stream_url_parser.dart';

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

/// Network, file, Xtream Codes, Stalker portal, and XMLTV EPG ingestion seam.
abstract interface class IptvSourceAdapter {
  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist);

  Future<ParsedPlaylistResult> parseM3uFromUrlWithMeta(
    String url,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
    String? requestType,
  });

  Future<ParsedPlaylistResult> parseM3uFromFileOrTextWithMeta(
    String pathOrText,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
  });

  Future<Channel> resolveChannelForPlayback(Channel ch);

  Future<Map<String, List<IptvEpgProgramme>>> fetchAndParseEpg(
    String epgUrl, {
    Map<String, String>? headers,
  });

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
  });

  Future<List<Channel>> fetchStalkerChannels({
    required String portalUrl,
    required String macAddress,
    required String playlistId,
  });

  Future<String?> probeUrlMimeType(
    String url, {
    Map<String, String>? headers,
  });

  Future<StalkerTestResult> testStalkerConnection({
    required String portalUrl,
    required String macAddress,
  });
}

/// Production [IptvSourceAdapter] backed by Dio HTTP, local files, and isolates.
class DioIptvSourceAdapter implements IptvSourceAdapter {
  DioIptvSourceAdapter({Dio? dio})
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

  final Dio _dio;

  /// Adds HTTP cache-bypass headers for playlist/API/key fetches without
  /// mutating [headers] passed onward to playback [Channel.headers].
  Map<String, String> _withNoCacheHeaders(Map<String, String>? headers) {
    final out = <String, String>{
      if (headers != null) ...headers,
    };
    final lowerKeys = out.keys.map((k) => k.toLowerCase()).toSet();
    if (!lowerKeys.contains('cache-control')) {
      out['Cache-Control'] = 'no-cache, no-store, must-revalidate';
    }
    if (!lowerKeys.contains('pragma')) {
      out['Pragma'] = 'no-cache';
    }
    return out;
  }

  @override
  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist) async {
    try {
      var channels = <Channel>[];
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
      if (playlist.authorization != null &&
          playlist.authorization!.trim().isNotEmpty) {
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
          final parsedUrl = StreamUrlParser.parseUrlWithParams(
            playlist.url,
            baseHeaders: combinedHeaders,
            baseDrm: playlist.drm,
            baseManifestType: playlist.manifestType,
          );
          final directHeaders = Map<String, dynamic>.from(parsedUrl.headers);
          if (playlist.subtitleUrl != null &&
              playlist.subtitleUrl!.trim().isNotEmpty) {
            directHeaders['X-Subtitle-Url'] = playlist.subtitleUrl!.trim();
          }
          if (playlist.manifestType != null &&
              playlist.manifestType!.trim().isNotEmpty &&
              playlist.manifestType!.trim() != 'auto' &&
              parsedUrl.drm == null) {
            directHeaders['X-Manifest-Type'] = playlist.manifestType!.trim();
          }
          channels = [
            Channel(
              id: '${playlist.id}_direct',
              name: playlist.name,
              streamUrl: parsedUrl.url,
              quality: 'HD',
              isLive: true,
              drm: parsedUrl.drm,
              headers: directHeaders,
              category: 'Direct Stream',
            ),
          ];
          break;
      }

      if (playlist.hasRemoteEndpoint &&
          playlist.channels.isNotEmpty &&
          channels.isEmpty) {
        throw StateError(
          'Remote playlist returned 0 channels; keeping cached channels',
        );
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
      debugPrint(
        '[IptvSource] fetchAndParse failed for ${playlist.name}: $e',
      );
      rethrow;
    }
  }

  @override
  Future<ParsedPlaylistResult> parseM3uFromUrlWithMeta(
    String url,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
    String? requestType,
  }) async {
    final normalizedMethod = (requestType ?? 'download').toLowerCase();
    final requestHeaders = _withNoCacheHeaders(headers);
    final Response<String> response = normalizedMethod == 'post'
        ? await _dio.post<String>(
            url,
            options: Options(
              headers: requestHeaders,
              responseType: ResponseType.plain,
            ),
          )
        : await _dio.get<String>(
            url,
            options: Options(
              headers: requestHeaders,
              responseType: ResponseType.plain,
            ),
          );

    final content = response.data ?? '';
    return compute(
      isolateParsePlaylist,
      PlaylistParseParams(
        content: content,
        playlistId: playlistId,
        baseHeaders: headers ?? const {},
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
      ),
    );
  }

  @override
  Future<ParsedPlaylistResult> parseM3uFromFileOrTextWithMeta(
    String pathOrText,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
  }) async {
    var content = pathOrText;
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
      isolateParsePlaylist,
      PlaylistParseParams(
        content: content,
        playlistId: playlistId,
        baseHeaders: headers ?? const {},
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
      ),
    );
  }

  @override
  Future<Channel> resolveChannelForPlayback(Channel ch) async {
    var resolved = ch;

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
            headers: _withNoCacheHeaders({
              if (mac.isNotEmpty) 'Cookie': 'mac=$mac',
              'User-Agent':
                  'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
            }),
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
              .replaceFirst(
                RegExp(r'^(ffmpeg|ffrt)\s+', caseSensitive: false),
                '',
              )
              .trim();
          if (cleanUrl.isNotEmpty) {
            resolved = _copyChannelWith(resolved, streamUrl: cleanUrl);
          }
        }
      } catch (e) {
        debugPrint('[IptvSource] Stalker create_link resolution failed: $e');
      }
    }

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
          options: Options(
            headers: _withNoCacheHeaders(reqHeaders),
            responseType: ResponseType.plain,
          ),
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
        debugPrint('[IptvSource] Remote ClearKey fetch failed: $e');
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

  @override
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
          headers: _withNoCacheHeaders(headers),
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return const {};

      final xmlBytes = (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)
          ? gzip.decode(bytes)
          : bytes;

      final xmlContent = utf8.decode(xmlBytes, allowMalformed: true);
      return compute(parseXmltvEpg, xmlContent);
    } catch (e) {
      debugPrint('[IptvSource] EPG fetch failed for $trimmed: $e');
      return const {};
    }
  }

  @override
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
    final cleanHost = hostUrl.endsWith('/')
        ? hostUrl.substring(0, hostUrl.length - 1)
        : hostUrl;
    final liveExt = streamFormat.trim().toLowerCase() == 'hls' ? 'm3u8' : 'ts';

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
        debugPrint('[IptvSource] Xtream m3u_plus fetch fallback to API: $e');
      }
    }

    final apiUrl =
        '$cleanHost/player_api.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
    final allChannels = <Channel>[];

    Future<Map<String, String>> loadCatMap(String action) async {
      final map = <String, String>{};
      try {
        final res = await _dio.get(
          '$apiUrl&action=$action',
          options: Options(headers: _withNoCacheHeaders(headers)),
        );
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

    final liveCatMap =
        importLive ? await loadCatMap('get_live_categories') : <String, String>{};
    final vodCatMap =
        importVod ? await loadCatMap('get_vod_categories') : <String, String>{};
    final seriesCatMap = importSeries
        ? await loadCatMap('get_series_categories')
        : <String, String>{};

    if (importLive) {
      try {
        final streamRes = await _dio.get(
          '$apiUrl&action=get_live_streams',
          options: Options(headers: _withNoCacheHeaders(headers)),
        );
        if (streamRes.data is List) {
          var index = 0;
          for (final item in streamRes.data as List) {
            if (item is Map) {
              index++;
              final streamId = item['stream_id']?.toString() ?? '$index';
              final name = item['name']?.toString() ?? 'Stream $index';
              final logo = item['stream_icon']?.toString();
              final catId = item['category_id']?.toString();
              final epgId = item['epg_channel_id']?.toString();
              final category = liveCatMap[catId] ?? 'Live TV';
              final streamUrl =
                  '$cleanHost/live/$username/$password/$streamId.$liveExt';
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
        debugPrint('[IptvSource] Xtream Live Streams error: $e');
      }
    }

    if (importVod) {
      try {
        final vodRes = await _dio.get(
          '$apiUrl&action=get_vod_streams',
          options: Options(headers: _withNoCacheHeaders(headers)),
        );
        if (vodRes.data is List) {
          var index = 0;
          for (final item in vodRes.data as List) {
            if (item is Map) {
              index++;
              final streamId = item['stream_id']?.toString() ?? '$index';
              final name = item['name']?.toString() ?? 'Movie $index';
              final logo = item['stream_icon']?.toString();
              final catId = item['category_id']?.toString();
              final ext = item['container_extension']?.toString() ?? 'mp4';
              final streamUrl =
                  '$cleanHost/movie/$username/$password/$streamId.$ext';

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
        debugPrint('[IptvSource] Xtream VOD error: $e');
      }
    }

    if (importSeries) {
      try {
        final seriesRes = await _dio.get(
          '$apiUrl&action=get_series',
          options: Options(headers: _withNoCacheHeaders(headers)),
        );
        if (seriesRes.data is List) {
          var index = 0;
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
        debugPrint('[IptvSource] Xtream Series error: $e');
      }
    }

    if (allChannels.isEmpty) {
      try {
        final fallbackUrl =
            '$cleanHost/get.php?username=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}&type=m3u_plus&output=$liveExt';
        final m3uRes = await parseM3uFromUrlWithMeta(
          fallbackUrl,
          playlistId,
          headers: headers,
        );
        return m3uRes.channels;
      } catch (_) {}
    }

    return allChannels;
  }

  @override
  Future<List<Channel>> fetchStalkerChannels({
    required String portalUrl,
    required String macAddress,
    required String playlistId,
  }) async {
    final cleanUrl = portalUrl.endsWith('/')
        ? portalUrl.substring(0, portalUrl.length - 1)
        : portalUrl;
    final cleanMac = macAddress.replaceAll('-', ':').toUpperCase();
    final handshakeUrl =
        '$cleanUrl/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml';

    try {
      final res = await _dio.get(
        handshakeUrl,
        options: Options(
          headers: _withNoCacheHeaders({
            'Cookie': 'mac=$cleanMac',
            'User-Agent':
                'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
          }),
        ),
      );

      var token = '';
      if (res.data is Map && res.data['js'] is Map) {
        token = res.data['js']['token']?.toString() ?? '';
      }

      final genreMap = <String, String>{};
      try {
        final genreRes = await _dio.get(
          '$cleanUrl/server/load.php?type=itv&action=get_genres&token=$token&JsHttpRequest=1-xml',
          options: Options(
            headers: _withNoCacheHeaders({'Cookie': 'mac=$cleanMac'}),
          ),
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
        options: Options(
          headers: _withNoCacheHeaders({'Cookie': 'mac=$cleanMac'}),
        ),
      );

      if (chRes.data is Map &&
          chRes.data['js'] is Map &&
          chRes.data['js']['data'] is List) {
        final channels = <Channel>[];
        final items = chRes.data['js']['data'] as List;
        var i = 0;
        for (final item in items) {
          if (item is Map) {
            i++;
            final id = item['id']?.toString() ?? '$i';
            final name = item['name']?.toString() ?? 'Channel $i';
            final cmd = item['cmd']?.toString() ?? '';
            final logo = item['logo']?.toString();
            final genreId = item['tv_genre_id']?.toString();

            final rawStream = cmd
                .replaceFirst(RegExp(r'^ffmpeg\s+', caseSensitive: false), '')
                .trim();
            final effectiveUrl = (rawStream.startsWith('http://') ||
                    rawStream.startsWith('https://'))
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
      debugPrint('[IptvSource] Stalker portal load notice: $e');
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

  @override
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
      if (rawCt != null &&
          rawCt.trim().isNotEmpty &&
          headRes.statusCode != 405) {
        return rawCt.split(';').first.trim();
      }
    } catch (_) {}

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
        await (getRes.data as ResponseBody).stream
            .drain<void>()
            .catchError((_) {});
      }
      if (rawCt != null && rawCt.trim().isNotEmpty) {
        return rawCt.split(';').first.trim();
      }
    } catch (_) {}

    return null;
  }

  @override
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
      final handshakeUrl =
          '$cleanUrl/server/load.php?type=stb&action=handshake&token=&JsHttpRequest=1-xml';
      final res = await _dio.get<dynamic>(
        handshakeUrl,
        options: Options(
          headers: {'Cookie': 'mac=$cleanMac', 'User-Agent': stbUserAgent},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      dynamic payload = res.data;
      if (payload is String) {
        payload = jsonDecode(payload);
      }
      final js = (payload is Map) ? payload['js'] : null;
      final token = (js is Map) ? js['token']?.toString() : null;
      if (token == null || token.isEmpty) {
        return StalkerTestResult(
          mac: cleanMac,
          error: 'No handshake token returned by portal',
        );
      }

      String? expiry;
      try {
        final profileUrl =
            '$cleanUrl/server/load.php?type=stb&action=get_profile&token=${Uri.encodeComponent(token)}&JsHttpRequest=1-xml';
        final profileRes = await _dio.get<dynamic>(
          profileUrl,
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
          final expireBilling =
              pJs['expire_billing_date'] ?? pJs['tariff_plan_name'];
          if (expireBilling != null && expireBilling.toString().isNotEmpty) {
            expiry = expireBilling.toString();
          }
          if (pJs['phone'] != null &&
              pJs['phone'].toString().trim().isNotEmpty &&
              expiry == null) {
            expiry = pJs['phone'].toString().trim();
          }
        }
      } catch (_) {}

      return StalkerTestResult(token: token, expiry: expiry, mac: cleanMac);
    } catch (e) {
      return StalkerTestResult(mac: cleanMac, error: e.toString());
    }
  }
}
