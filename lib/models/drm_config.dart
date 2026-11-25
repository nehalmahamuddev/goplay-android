import 'dart:convert';

/// Supported DRM protection schemes
enum DrmType { clearkey, widevine, playready }

/// DRM configuration for a channel stream.
///
/// ClearKey: kid + key (hex strings) are embedded locally — no license server,
/// or [licenseUrl] points to a remote ClearKey JSON/TXT endpoint fetched before play.
/// Widevine: licenseUrl is required; licenseHeaders are optional auth tokens.
/// PlayReady: supported via licenseUrl / licenseHeaders.
class DrmConfig {
  final DrmType type;

  // ── ClearKey fields ──
  final String? kid;
  final String? key;
  final Map<String, String>? clearKeys;

  // ── Widevine / PlayReady / Remote ClearKey fields ──
  final String? licenseUrl;
  final Map<String, String>? licenseHeaders;

  // ── Manifest / Key metadata ──
  final String? manifestType;
  final String? keyEncoding;

  const DrmConfig({
    required this.type,
    this.kid,
    this.key,
    this.clearKeys,
    this.licenseUrl,
    this.licenseHeaders,
    this.manifestType,
    this.keyEncoding,
  });

  DrmConfig copyWith({
    DrmType? type,
    String? kid,
    String? key,
    Map<String, String>? clearKeys,
    String? licenseUrl,
    Map<String, String>? licenseHeaders,
    String? manifestType,
    String? keyEncoding,
  }) {
    return DrmConfig(
      type: type ?? this.type,
      kid: kid ?? this.kid,
      key: key ?? this.key,
      clearKeys: clearKeys ?? this.clearKeys,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      licenseHeaders: licenseHeaders ?? this.licenseHeaders,
      manifestType: manifestType ?? this.manifestType,
      keyEncoding: keyEncoding ?? this.keyEncoding,
    );
  }

  /// Parse ClearKey pairs from any supported input format:
  /// - W3C ClearKey JWK JSON: `{"keys":[{"kty":"oct","k":"...","kid":"..."}]}`
  /// - Flat JSON object: `{"kidHex": "keyHex"}`
  /// - Comma-separated hex pairs: `kid1:key1,kid2:key2`
  /// - Single pair: `kid:key`
  ///
  /// Always normalizes Base64/Base64URL keys to lowercase hex strings so native
  /// `NativePlayerView.buildClearKeyDrm` can decode them uniformly.
  static Map<String, String> parseClearKeys(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const {};

    final out = <String, String>{};

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final keysList = decoded['keys'];
          if (keysList is List) {
            for (final item in keysList) {
              if (item is Map) {
                final kRaw = (item['k'] ?? item['key'])?.toString().trim();
                final kidRaw = (item['kid'] ?? item['id'])?.toString().trim();
                if (kRaw != null && kidRaw != null && kRaw.isNotEmpty && kidRaw.isNotEmpty) {
                  final kidHex = _normalizeToHex(kidRaw);
                  final keyHex = _normalizeToHex(kRaw);
                  if (kidHex != null && keyHex != null) {
                    out[kidHex] = keyHex;
                  }
                }
              }
            }
          } else {
            for (final entry in decoded.entries) {
              final kStr = entry.key.toString().trim();
              final vStr = entry.value?.toString().trim() ?? '';
              if (kStr.isEmpty || vStr.isEmpty || kStr == 'type') continue;
              final kidHex = _normalizeToHex(kStr);
              final keyHex = _normalizeToHex(vStr);
              if (kidHex != null && keyHex != null) {
                out[kidHex] = keyHex;
              }
            }
          }
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final kRaw = (item['k'] ?? item['key'])?.toString().trim();
              final kidRaw = (item['kid'] ?? item['id'])?.toString().trim();
              if (kRaw != null && kidRaw != null) {
                final kidHex = _normalizeToHex(kidRaw);
                final keyHex = _normalizeToHex(kRaw);
                if (kidHex != null && keyHex != null) {
                  out[kidHex] = keyHex;
                }
              }
            }
          }
        }
      } catch (_) {}
      if (out.isNotEmpty) return out;
    }

    // Comma-separated or single `kid:key` pairs
    final pairs = trimmed.split(',');
    for (final pair in pairs) {
      final idx = pair.indexOf(':');
      if (idx > 0 && idx < pair.length - 1) {
        final rawKid = pair.substring(0, idx).trim();
        final rawKey = pair.substring(idx + 1).trim();
        final kidHex = _normalizeToHex(rawKid);
        final keyHex = _normalizeToHex(rawKey);
        if (kidHex != null && keyHex != null) {
          out[kidHex] = keyHex;
        }
      }
    }
    return out;
  }

  static final RegExp _hexRegex = RegExp(r'^[0-9a-fA-F]+$');

  static String? _normalizeToHex(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.isEmpty) return null;
    if (_hexRegex.hasMatch(cleaned) && cleaned.length >= 16 && cleaned.length.isEven) {
      return cleaned.toLowerCase();
    }
    try {
      final standard = cleaned.replaceAll('-', '+').replaceAll('_', '/');
      final bytes = base64Decode(base64.normalize(standard));
      if (bytes.isEmpty) return null;
      final sb = StringBuffer();
      for (final b in bytes) {
        sb.write(b.toRadixString(16).padLeft(2, '0'));
      }
      return sb.toString();
    } catch (_) {
      return null;
    }
  }

  /// Parse DRM config from JSON/Hive map.
  /// Returns null if the json is null or not a Map.
  static DrmConfig? fromJson(dynamic json) {
    if (json == null || json is! Map) return null;
    final map = Map<String, dynamic>.from(json);

    final typeStr = (map['type'] as String? ?? 'clearkey').toLowerCase();
    final type = DrmType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => DrmType.clearkey,
    );

    Map<String, String>? clearKeys;
    final clearKeysJson = map['clearKeys'] ?? map['clearkeys'];
    if (clearKeysJson is Map) {
      clearKeys = Map<String, String>.from(
        clearKeysJson.map((k, v) => MapEntry(k.toString(), v.toString())),
      );
    } else if (map['keys'] is List) {
      clearKeys = {};
      for (final item in map['keys']) {
        if (item is Map) {
          final k = item['kid']?.toString();
          final v = item['key']?.toString();
          if (k != null && v != null) {
            clearKeys[k] = v;
          }
        }
      }
    }

    final kid = map['kid'] as String?;
    final key = map['key'] as String?;

    if (kid != null && key != null) {
      clearKeys ??= {};
      if (!clearKeys.containsKey(kid)) {
        clearKeys[kid] = key;
      }
    }

    return DrmConfig(
      type: type,
      kid: kid,
      key: key,
      clearKeys: clearKeys,
      licenseUrl: map['licenseUrl'] as String?,
      licenseHeaders: map['headers'] != null
          ? Map<String, String>.from(
              (map['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          : null,
      manifestType: map['manifestType'] as String?,
      keyEncoding: map['keyEncoding'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type.name};
    if (kid != null) map['kid'] = kid;
    if (key != null) map['key'] = key;
    if (clearKeys != null) map['clearKeys'] = clearKeys;
    if (licenseUrl != null) map['licenseUrl'] = licenseUrl;
    if (licenseHeaders != null) map['headers'] = licenseHeaders;
    if (manifestType != null) map['manifestType'] = manifestType;
    if (keyEncoding != null) map['keyEncoding'] = keyEncoding;
    return map;
  }

  /// Whether this is a ClearKey scheme (keys embedded or remote JSON).
  bool get isClearKey => type == DrmType.clearkey;

  /// Whether this is a Widevine scheme (requires license server).
  bool get isWidevine => type == DrmType.widevine;

  @override
  String toString() =>
      'DrmConfig(type: $type, kid: $kid, keysCount: ${clearKeys?.length ?? 0}, manifestType: $manifestType)';
}
