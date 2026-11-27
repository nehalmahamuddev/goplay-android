import 'dart:convert';

import '../../models/drm_config.dart';

/// Shared URL, pipe-parameter, and DRM header parser used across Catalog
/// channels, Category M3U playlists, StreamDecryptor payloads, and IPTV sources.
abstract final class StreamUrlParser {
  /// Extracts base stream URL and `|`-delimited HTTP headers
  /// (e.g. `https://example.com/live.m3u8|User-Agent=Mozilla...&Referer=https://...`).
  static ({String url, Map<String, String> headers}) parsePipeHeaders(
    String rawUrl,
  ) {
    try {
      final decoded = Uri.decodeFull(rawUrl);
      if (!decoded.contains('|')) {
        return (url: decoded.trim(), headers: const <String, String>{});
      }

      final parts = decoded.split('|');
      final streamUrl = parts[0].trim();
      final headers = <String, String>{};

      if (parts.length > 1) {
        final queryParams = parts[1].split('&');
        for (final param in queryParams) {
          final kv = param.split('=');
          if (kv.length >= 2) {
            headers[kv[0].trim()] = kv.sublist(1).join('=').trim();
          }
        }
      }

      return (url: streamUrl, headers: headers);
    } catch (_) {
      return (url: rawUrl, headers: const <String, String>{});
    }
  }

  /// Parses `|`-delimited stream parameters including `exthttp`, `User-Agent`,
  /// `Referer`, `Origin`, `Cookie`, `drmscheme`, `drmlicense`, `clearkeys`,
  /// `widevine`, `playready`, and `manifesttype`.
  static ({String url, Map<String, String> headers, DrmConfig? drm})
      parseUrlWithParams(
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
    var sawExtHttp = false;

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
          mergeExtHttpHeaders(value, headers);
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

    final DrmConfig? overrideDrm = (licenseType != null || licenseKey != null)
        ? buildDrmFromKodiProps(
            licenseType: licenseType ?? drm?.type.name,
            licenseKey: licenseKey ?? drm?.licenseUrl,
            manifestType: manifestType,
            headers: headers,
          )
        : null;

    if (overrideDrm != null) {
      drm = overrideDrm;
    } else if (drm != null &&
        manifestType != null &&
        drm.manifestType != manifestType) {
      drm = drm.copyWith(manifestType: manifestType);
    }

    return (url: cleanUrl, headers: headers, drm: drm);
  }

  /// Decodes plain JSON or Base64 JSON `#EXTHTTP` header objects (including
  /// auto-decoding Base64 `dt-custom-data` values) into [target].
  static void mergeExtHttpHeaders(String raw, Map<String, String> target) {
    var candidate = raw.trim();
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

  /// Resolves a [DrmConfig] from KODIPROP or pipe DRM scheme/key attributes.
  static DrmConfig? buildDrmFromKodiProps({
    String? licenseType,
    String? licenseKey,
    String? manifestType,
    Map<String, String>? headers,
  }) {
    final typeRaw = licenseType?.trim().toLowerCase() ?? '';
    final keyRaw = licenseKey?.trim() ?? '';

    if (typeRaw.isEmpty &&
        keyRaw.isEmpty &&
        (manifestType == null || manifestType.isEmpty)) {
      return null;
    }

    DrmType resolvedType;
    if (typeRaw.contains('clearkey') || typeRaw == 'org.w3.clearkey') {
      resolvedType = DrmType.clearkey;
    } else if (typeRaw.contains('playready') ||
        typeRaw.contains('com.microsoft.playready')) {
      resolvedType = DrmType.playready;
    } else if (typeRaw.contains('widevine') ||
        typeRaw.contains('com.widevine.alpha')) {
      resolvedType = DrmType.widevine;
    } else if (keyRaw.startsWith('{') ||
        (!keyRaw.startsWith('http') && keyRaw.contains(':'))) {
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
          licenseHeaders:
              headers?.isNotEmpty == true ? Map.from(headers!) : null,
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

  static bool _looksLikeBase64(String s) {
    final trimmed = s.trim();
    if (trimmed.length < 4 || trimmed.contains('{') || trimmed.contains(' ')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/_\-=]+$').hasMatch(trimmed);
  }
}

/// Top-level helper preserved for callers importing `parseUrlWithParams`.
({String url, Map<String, String> headers, DrmConfig? drm}) parseUrlWithParams(
  String rawUrl, {
  Map<String, String> baseHeaders = const {},
  DrmConfig? baseDrm,
  String? baseManifestType,
}) =>
    StreamUrlParser.parseUrlWithParams(
      rawUrl,
      baseHeaders: baseHeaders,
      baseDrm: baseDrm,
      baseManifestType: baseManifestType,
    );
