import 'dart:convert';

import '../../models/channel.dart';
import '../../models/drm_config.dart';
import '../../models/iptv_playlist.dart';
import 'stream_url_parser.dart';

/// Top-level result returned from isolate M3U/JSON playlist parsing.
class ParsedPlaylistResult {
  final List<Channel> channels;
  final String? detectedEpgUrl;

  const ParsedPlaylistResult({
    required this.channels,
    this.detectedEpgUrl,
  });
}

/// Isolate argument payload for [isolateParsePlaylist].
class PlaylistParseParams {
  final String content;
  final String playlistId;
  final Map<String, String> baseHeaders;
  final DrmConfig? defaultDrm;
  final String? defaultManifestType;

  const PlaylistParseParams({
    required this.content,
    required this.playlistId,
    this.baseHeaders = const {},
    this.defaultDrm,
    this.defaultManifestType,
  });
}

ParsedPlaylistResult isolateParsePlaylist(PlaylistParseParams params) {
  return parseM3uOrJsonContent(
    params.content,
    params.playlistId,
    baseHeaders: params.baseHeaders,
    defaultDrm: params.defaultDrm,
    defaultManifestType: params.defaultManifestType,
  );
}

/// Pure function to normalize a channel key for EPG lookup
/// (`lowercase().replaceAll(' ', '')`).
String normalizeEpgKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(' ', '');

/// Quality suffix regex used when normalizing channel names for EPG fallback.
final RegExp kEpgQualityRegex =
    RegExp(r'(\s+hd|\s+fhd|\s+sd|\s+4k)$', caseSensitive: false);

/// Matches an EPG programme list for [channel] using `tvgId` first, then
/// [kEpgQualityRegex]-stripped `channel.name` fallback.
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

/// Formats one or more [playlists] as a standard `#EXTM3U` document for
/// clipboard export or file sharing.
String buildM3uExportString(Iterable<IptvPlaylist> playlists) {
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

/// Parses either a M3U/M3U8 text playlist or a JSON playlist (`M3U8Entry` array
/// or flat channel array) purely in memory (safe for background isolates).
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

  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final List rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map) {
        final inner = decoded['channels'] ??
            decoded['items'] ??
            decoded['entries'] ??
            decoded['data'];
        if (inner is List) {
          rawList = inner;
        } else {
          rawList = [decoded];
        }
      } else {
        rawList = const [];
      }

      final channels = <Channel>[];
      var index = 0;
      for (final row in rawList) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);

        final extInf = map['EXTINF'] is Map
            ? Map<String, dynamic>.from(map['EXTINF'] as Map)
            : null;
        final kodiProp = map['KODIPROP'] is Map
            ? Map<String, dynamic>.from(map['KODIPROP'] as Map)
            : null;
        final extVlcOpt = map['EXTVLCOPT'] is Map
            ? Map<String, dynamic>.from(map['EXTVLCOPT'] as Map)
            : null;

        final rawUrl = (map['url'] ?? map['stream_url'] ?? map['streamUrl'] ?? '')
            .toString()
            .trim();
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
          StreamUrlParser.mergeExtHttpHeaders(exthttpRaw, entryHeaders);
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
          if (ua != null && ua.toString().isNotEmpty) {
            entryHeaders['User-Agent'] = ua.toString();
          }
          if (ref != null && ref.toString().isNotEmpty) {
            entryHeaders['Referer'] = ref.toString();
          }
          if (cookie != null && cookie.toString().isNotEmpty) {
            entryHeaders['Cookie'] = cookie.toString();
          }
          if (origin != null && origin.toString().isNotEmpty) {
            entryHeaders['Origin'] = origin.toString();
          }
        }

        DrmConfig? entryDrm = DrmConfig.fromJson(map['drm']) ?? defaultDrm;
        if (kodiProp != null) {
          final licType =
              (kodiProp['licenseType'] ?? kodiProp['license_type'])?.toString();
          final licKey =
              (kodiProp['licenseKey'] ?? kodiProp['license_key'])?.toString();
          final manifest =
              (kodiProp['manifestType'] ?? kodiProp['manifest_type'])
                  ?.toString();
          entryDrm = StreamUrlParser.buildDrmFromKodiProps(
                licenseType: licType,
                licenseKey: licKey,
                manifestType: manifest ?? defaultManifestType,
                headers: entryHeaders,
              ) ??
              entryDrm;
        }

        final parsedUrl = StreamUrlParser.parseUrlWithParams(
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
            category: (group != null && group.trim().isNotEmpty)
                ? group.trim()
                : 'Undefined',
            tvgId: (tvgId != null && tvgId.trim().isNotEmpty)
                ? tvgId.trim()
                : null,
            tvgUrl: (tvgUrl != null && tvgUrl.trim().isNotEmpty)
                ? tvgUrl.trim()
                : null,
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
      // Fall through to M3U parser if not valid playlist JSON.
    }
  }

  final lines = const LineSplitter().convert(content);
  final channels = <Channel>[];

  String? detectedEpgUrl;
  String? currentName;
  String? currentLogo;
  String? currentGroup;
  String? currentTvgId;
  String? currentTvgUrl;
  var currentHeaders = Map<String, String>.from(baseHeaders);
  String? currentLicenseType;
  String? currentLicenseKey;
  var currentManifestType = defaultManifestType;
  var hasExtInf = false;

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

  var index = 0;

  for (var i = 0; i < lines.length; i++) {
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
        StreamUrlParser.mergeExtHttpHeaders(rawHttp, currentHeaders);
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

    final baseDrm = StreamUrlParser.buildDrmFromKodiProps(
          licenseType: currentLicenseType,
          licenseKey: currentLicenseKey,
          manifestType: currentManifestType,
          headers: currentHeaders,
        ) ??
        defaultDrm;

    final parsedUrl = StreamUrlParser.parseUrlWithParams(
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
    final quoted =
        RegExp('$name="([^"]*)"', caseSensitive: false).firstMatch(line);
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
/// mapping both `<channel id>` and every `<display-name>` alias.
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
