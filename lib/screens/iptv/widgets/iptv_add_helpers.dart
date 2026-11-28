import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../providers/theme_provider.dart';

/// Default desktop Chrome User-Agent matching the APK's `DefaultUserAgent2`.
const String kDefaultIptvUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

/// DNS-over-HTTPS resolver presets from the reference app settings.
const List<({String label, String url})> kIptvDohPresets = [
  (label: 'Cloudflare', url: 'https://cloudflare-dns.com/dns-query'),
  (label: 'Google', url: 'https://dns.google/dns-query'),
  (label: 'AdGuard', url: 'https://dns.adguard-dns.com/dns-query'),
  (label: 'Quad9', url: 'https://dns.quad9.net/dns-query'),
];

/// DRM Scheme dropdown options.
const List<({String label, String value})> kIptvDrmSchemeOptions = [
  (label: 'None', value: 'none'),
  (label: 'ClearKey', value: 'clearkey'),
  (label: 'Widevine', value: 'widevine'),
  (label: 'PlayReady', value: 'playready'),
];

/// Manifest Type dropdown options matching `Network Video Stream`.
const List<({String label, String value})> kIptvManifestOptions = [
  (label: 'Automatic Selection', value: 'auto'),
  (label: 'Default (.mp4, .webm & more)', value: 'mp4'),
  (label: 'HLS (.m3u8, .ts, & more)', value: 'hls'),
  (label: 'DASH (.mpd, fMP4 & more)', value: 'dash'),
  (label: 'SmoothStreaming (.ism & more)', value: 'ss'),
];

/// DRM Key Encoding dropdown options.
const List<({String label, String value})> kIptvKeyEncodingOptions = [
  (label: 'Automatic Selection', value: 'auto'),
  (label: 'Base64', value: 'base64'),
  (label: 'HEX', value: 'hex'),
];

/// HTTP request mode choices for playlist/stream retrieval.
const List<String> kIptvRequestTypes = ['download', 'get', 'post'];

/// Xtream Codes API output format options.
const List<String> kIptvXtreamStreamFormats = ['TS', 'HLS'];

/// Xtream Codes parser engine options.
const List<String> kIptvXtreamParserTypes = ['m3u_plus', 'API Codes'];

/// Curated list of 35+ player/browser/device User-Agent presets matching the APK modal.
const List<({String name, String value})> kIptvUserAgentPresets = [
  (name: 'Default (Chrome Windows)', value: kDefaultIptvUserAgent),
  (name: 'OTT Navigator', value: 'OTT Navigator/1.6.7.5 (Linux; Android 11)'),
  (name: 'TiviMate', value: 'TiviMate/4.7.0 (Android TV)'),
  (name: 'IPTV Smarters Pro', value: 'IPTVSmartersPro'),
  (name: 'Perfect Player', value: 'Perfect Player/1.5.5 (Windows; U; en)'),
  (name: 'GSE Smart IPTV', value: 'GSE Smart IPTV/7.0 (iPhone; iOS 15.0)'),
  (name: 'IPTV Extreme', value: 'IPTV Extreme/7.0 (Android 11)'),
  (name: 'ProgTV', value: 'ProgTV/2.5 (Windows NT 10.0; Win64; x64)'),
  (name: 'SS IPTV', value: 'SS IPTV/1.9.5 (Android TV)'),
  (name: 'VLC Media Player', value: 'VLC/3.5.4 LibVLC/3.5.4'),
  (name: 'Kodi', value: 'Kodi/21.0 (Windows NT 10.0; Win64; x64)'),
  (name: 'Plex', value: 'Plex/4.92.0 (Windows)'),
  (name: 'Emby', value: 'Emby/4.8.0.0 (Windows)'),
  (name: 'Jellyfin', value: 'Jellyfin/10.8.0 (Windows)'),
  (name: 'MX Player', value: 'MX Player/1.46.2 (Android)'),
  (name: 'PotPlayer', value: 'PotPlayer/230228 (Windows NT 10.0)'),
  (name: 'MPC-HC', value: 'MPC-HC/2.1.0 (Windows NT 10.0)'),
  (name: 'ExoPlayer', value: 'ExoPlayerLib/2.19.1 (Linux; Android 13)'),
  (name: 'ExoPlayer (Android TV)', value: 'ExoPlayerLib/2.18.0 (Android TV)'),
  (name: 'ExoPlayer (Android 13)', value: 'ExoPlayerLib/2.19.1 (Android 13; Mobile)'),
  (name: 'Chrome (Android)', value: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'),
  (name: 'Firefox (Windows)', value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0'),
  (name: 'Edge (Windows)', value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0'),
  (name: 'Safari (iOS)', value: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1'),
  (name: 'Safari (macOS)', value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15'),
  (name: 'Samsung Browser', value: 'Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36'),
  (name: 'Android TV', value: 'Dalvik/2.1.0 (Linux; U; Android TV 12; SHIELD Android TV Build/SR1A)'),
  (name: 'Apple TV', value: 'AppleTV6,3/17.2 (Apple TV; U; en)'),
  (name: 'Amazon Fire TV', value: 'Dalvik/2.1.0 (Linux; U; Android 11; AFTMM Build/NS6294)'),
  (name: 'Roku', value: 'Roku/DVP-9.4 (297.10E04191A)'),
  (name: 'Samsung Tizen TV', value: 'Mozilla/5.0 (SMART-TV; LINUX; Tizen 7.0) AppleWebKit/537.36 (KHTML, like Gecko) 94.0.4606.31/7.0 TV Safari/537.36'),
  (name: 'LG webOS TV', value: 'Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/87.0.4280.88 Safari/537.36 WebAppManager'),
  (name: 'NVIDIA Shield', value: 'Dalvik/2.1.0 (Linux; U; Android 11; SHIELD Android TV Build/RQ1A)'),
  (name: 'Chromecast', value: 'Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.225 Safari/537.36 CrKey/1.56'),
  (name: 'MAG250 STB', value: 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3'),
  (name: 'Wget', value: 'Wget/1.21.4'),
  (name: 'cURL', value: 'curl/8.4.0'),
];

const MethodChannel _kFilePickerChannel = MethodChannel('com.goplay/file_picker');

/// Launches the Android SAF document picker (`ACTION_OPEN_DOCUMENT`) via Kotlin MethodChannel.
Future<({String name, String content, String uri})?> pickLocalPlaylistFile() async {
  try {
    final result = await _kFilePickerChannel.invokeMapMethod<String, dynamic>('pickPlaylistFile');
    if (result == null) return null;
    return (
      name: (result['name'] ?? 'playlist.m3u').toString(),
      content: (result['content'] ?? '').toString(),
      uri: (result['uri'] ?? '').toString(),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    rethrow;
  }
}

/// Scans standard storage folders for `.m3u` / `.m3u8` files as a fallback on
/// Android TV devices that lack a system DocumentsUI file picker.
Future<List<({String name, String path, int size})>> listLocalPlaylistFiles() async {
  try {
    final raw = await _kFilePickerChannel.invokeListMethod<dynamic>('listLocalPlaylistFiles');
    if (raw == null) return const [];
    return raw.whereType<Map>().map((entry) {
      return (
        name: (entry['name'] ?? 'playlist.m3u').toString(),
        path: (entry['path'] ?? '').toString(),
        size: (entry['size'] as num?)?.toInt() ?? 0,
      );
    }).where((f) => f.path.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

/// Reads a local playlist file selected from [listLocalPlaylistFiles].
Future<({String name, String content, String uri})?> readLocalPlaylistFile(String path) async {
  try {
    final result = await _kFilePickerChannel.invokeMapMethod<String, dynamic>(
      'readLocalPlaylistFile',
      path,
    );
    if (result == null) return null;
    return (
      name: (result['name'] ?? 'playlist.m3u').toString(),
      content: (result['content'] ?? '').toString(),
      uri: (result['uri'] ?? '').toString(),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    rethrow;
  }
}

/// Validates whether a stream/playlist input begins with a supported URI scheme or file path.
bool isSupportedIptvScheme(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  const schemes = [
    'http://',
    'https://',
    'udp://',
    'rtsp://',
    'rtmp://',
    'ws://',
    'wss://',
    'srt://',
    'ftp://',
    'content://',
    'file://',
  ];
  if (schemes.any(lower.startsWith)) return true;
  if (trimmed.startsWith('/') ||
      lower.startsWith('storage/') ||
      lower.startsWith('sdcard/') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
    return true;
  }
  return false;
}

/// Returns true if [input] looks like a direct media file rather than a playlist URL.
bool looksLikeDirectVideoUrl(String input) {
  final trimmed = input.trim().toLowerCase();
  if (trimmed.isEmpty) return false;
  final cleanPath = trimmed.split('?').first.split('#').first;
  const videoExts = ['.mp4', '.mkv', '.mov', '.avi', '.webm', '.ts', '.mpd', '.flv', '.3gp', '.mp3'];
  return videoExts.any(cleanPath.endsWith);
}

/// Extracts optional `?title=` query value used by player deep/stream links.
String? extractTitleQueryParam(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return null;
  final title = uri.queryParameters['title']?.trim();
  return (title != null && title.isNotEmpty) ? title : null;
}

/// Infers a clean display name from a stream/playlist URL or filename.
String inferPlaylistNameFromUrl(String rawUrl, {String fallback = 'My IPTV Playlist'}) {
  final titleParam = extractTitleQueryParam(rawUrl);
  if (titleParam != null && titleParam.isNotEmpty) {
    return titleParam;
  }
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri != null) {
    final segs = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (segs.isNotEmpty) {
      final last = Uri.decodeComponent(segs.last);
      final cleanStem = last.replaceFirst(RegExp(r'\.(m3u8?|json|xml|mpd|mp4|mkv|ts)$', caseSensitive: false), '');
      if (cleanStem.isNotEmpty) return cleanStem;
    }
    if (uri.host.isNotEmpty) return uri.host;
  }
  return fallback;
}

/// Parses Extra Headers input from either JSON `{"Key": "Val"}` or `Key: Val` lines.
Map<String, String> parseExtraHeadersInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const {};

  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final out = <String, String>{};
        for (final entry in decoded.entries) {
          final k = entry.key.toString().trim();
          final v = entry.value.toString().trim();
          if (k.isNotEmpty) out[k] = v;
        }
        return out;
      }
    } catch (_) {
      // Fallback to line parser below.
    }
  }

  final out = <String, String>{};
  for (final line in trimmed.split(RegExp(r'[\r\n]+'))) {
    final idx = line.indexOf(':');
    if (idx > 0) {
      final key = line.substring(0, idx).trim();
      final val = line.substring(idx + 1).trim();
      if (key.isNotEmpty) out[key] = val;
    }
  }
  return out;
}

/// Encodes a header map into JSON string (empty string if map is empty).
String formatExtraHeadersJson(Map<String, String> headers) {
  final cleaned = <String, String>{};
  for (final entry in headers.entries) {
    final k = entry.key.trim();
    if (k.isNotEmpty) cleaned[k] = entry.value.trim();
  }
  if (cleaned.isEmpty) return '';
  return jsonEncode(cleaned);
}

/// Single-choice User-Agent preset picker dialog with live search and custom entry.
Future<String?> showUserAgentPickerDialog(
  BuildContext context, {
  String currentValue = '',
}) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _UserAgentPickerDialog(currentValue: currentValue),
  );
}

class _UserAgentPickerDialog extends ConsumerStatefulWidget {
  final String currentValue;

  const _UserAgentPickerDialog({required this.currentValue});

  @override
  ConsumerState<_UserAgentPickerDialog> createState() => _UserAgentPickerDialogState();
}

class _UserAgentPickerDialogState extends ConsumerState<_UserAgentPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late String _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.currentValue.trim();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final q = _query.trim().toLowerCase();
    final filtered = kIptvUserAgentPresets.where((p) {
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.value.toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      backgroundColor: themeMode.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: themeMode.dividerColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      title: Row(
        children: [
          Icon(Icons.devices_other_rounded, size: 20, color: accentColor.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Select User-Agent',
              style: GoPlayType.title.copyWith(color: themeMode.onSurfaceColor, fontSize: 17),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: themeMode.onSurfaceMutedColor, size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search browser, player, device...',
                hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor.withAlpha(150), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: themeMode.onSurfaceMutedColor),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 16, color: themeMode.onSurfaceMutedColor),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: themeMode.cardColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: themeMode.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: themeMode.dividerColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accentColor.color, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: themeMode.dividerColor),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final isSelected = _selectedValue == item.value;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      size: 18,
                      color: isSelected ? accentColor.color : themeMode.onSurfaceMutedColor,
                    ),
                    title: Text(
                      item.name,
                      style: TextStyle(
                        color: isSelected ? accentColor.color : themeMode.onSurfaceColor,
                        fontSize: 13.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      item.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 11),
                    ),
                    onTap: () => Navigator.of(context).pop(item.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: TextStyle(color: themeMode.onSurfaceMutedColor)),
        ),
      ],
    );
  }
}

/// Interactive Key/Value table editor dialog (`Manage Extra Header`, APK `res/hb1.xml`).
Future<String?> showManageExtraHeadersDialog(
  BuildContext context, {
  String initialJson = '',
}) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _ManageExtraHeadersDialog(initialJson: initialJson),
  );
}

class _HeaderRowControllers {
  final TextEditingController keyCtrl;
  final TextEditingController valueCtrl;

  _HeaderRowControllers(String key, String value)
      : keyCtrl = TextEditingController(text: key),
        valueCtrl = TextEditingController(text: value);

  void dispose() {
    keyCtrl.dispose();
    valueCtrl.dispose();
  }
}

class _ManageExtraHeadersDialog extends ConsumerStatefulWidget {
  final String initialJson;

  const _ManageExtraHeadersDialog({required this.initialJson});

  @override
  ConsumerState<_ManageExtraHeadersDialog> createState() => _ManageExtraHeadersDialogState();
}

class _ManageExtraHeadersDialogState extends ConsumerState<_ManageExtraHeadersDialog> {
  final List<_HeaderRowControllers> _rows = [];

  @override
  void initState() {
    super.initState();
    final parsed = parseExtraHeadersInput(widget.initialJson);
    if (parsed.isEmpty) {
      _rows.add(_HeaderRowControllers('', ''));
    } else {
      for (final entry in parsed.entries) {
        _rows.add(_HeaderRowControllers(entry.key, entry.value));
      }
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_HeaderRowControllers('', ''));
    });
  }

  void _removeRow(int index) {
    if (_rows.length == 1) {
      _rows.first.keyCtrl.clear();
      _rows.first.valueCtrl.clear();
      return;
    }
    final removed = _rows.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _save() {
    final map = <String, String>{};
    for (final row in _rows) {
      final k = row.keyCtrl.text.trim();
      final v = row.valueCtrl.text.trim();
      if (k.isNotEmpty) {
        map[k] = v;
      }
    }
    Navigator.of(context).pop(formatExtraHeadersJson(map));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return AlertDialog(
      backgroundColor: themeMode.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: themeMode.dividerColor),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, size: 20, color: accentColor.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Manage Extra Header',
              style: GoPlayType.title.copyWith(color: themeMode.onSurfaceColor, fontSize: 17),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: themeMode.onSurfaceMutedColor, size: 20),
            tooltip: 'Close',
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Header Key',
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Value',
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: row.keyCtrl,
                          style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13),
                          decoration: _cellInputDecoration('X-Custom-Header', themeMode, accentColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: row.valueCtrl,
                          style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13),
                          decoration: _cellInputDecoration('Value', themeMode, accentColor),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => _removeRow(index),
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B6B), size: 19),
                        tooltip: 'Remove Header',
                        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('ADD HEADER'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor.color,
                  side: BorderSide(color: accentColor.color.withAlpha(110)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: TextStyle(color: themeMode.onSurfaceMutedColor)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: accentColor.color,
            foregroundColor: accentColor.onAccentColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  InputDecoration _cellInputDecoration(String hint, AppThemeMode themeMode, AppAccentColor accentColor) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor.withAlpha(130), fontSize: 12.5),
      filled: true,
      fillColor: themeMode.cardColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: themeMode.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: themeMode.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor.color, width: 1.5),
      ),
    );
  }
}
