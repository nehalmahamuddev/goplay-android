import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../models/drm_config.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import 'iptv_add_helpers.dart';

/// Unified Add / Edit dialog matching the reference APK's 5 media/playlist forms:
/// Network Video Stream, Playlist Link (M3U/JSON), Local Playlist (M3U/JSON),
/// Xtream Codes Api, and STB / Stalker / MAC Portal.
class IptvAddSourceDialog extends ConsumerStatefulWidget {
  final IptvSourceType initialType;
  final IptvPlaylist? existingPlaylist;

  const IptvAddSourceDialog({
    super.key,
    this.initialType = IptvSourceType.m3uUrl,
    this.existingPlaylist,
  });

  static Future<IptvPlaylist?> show(
    BuildContext context, {
    IptvSourceType initialType = IptvSourceType.m3uUrl,
    IptvPlaylist? existingPlaylist,
  }) {
    return showDialog<IptvPlaylist>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: IptvAddSourceDialog(
          initialType: existingPlaylist?.sourceType ?? initialType,
          existingPlaylist: existingPlaylist,
        ),
      ),
    );
  }

  @override
  ConsumerState<IptvAddSourceDialog> createState() => _IptvAddSourceDialogState();
}

class _IptvAddSourceDialogState extends ConsumerState<IptvAddSourceDialog> {
  final _formKey = GlobalKey<FormState>();

  late IptvSourceType _sourceType;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _subtitleUrlCtrl;
  late final TextEditingController _drmLicenseCtrl;
  late final TextEditingController _dohCtrl;
  late final TextEditingController _epgCtrl;
  late final TextEditingController _userAgentCtrl;
  late final TextEditingController _refererCtrl;
  late final TextEditingController _cookieCtrl;
  late final TextEditingController _originCtrl;
  late final TextEditingController _authorizationCtrl;
  late final TextEditingController _extraHeadersCtrl;

  // Local playlist / raw paste controller
  late final TextEditingController _localContentCtrl;
  String? _pickedFileName;
  bool _isPickingFile = false;

  // Xtream fields
  late final TextEditingController _xtreamHostCtrl;
  late final TextEditingController _xtreamUserCtrl;
  late final TextEditingController _xtreamPassCtrl;
  bool _obscureXtreamPassword = true;
  String _xtreamStreamFormat = 'TS';
  String _xtreamParserType = 'API Codes';
  bool _importLive = true;
  bool _importVod = true;
  bool _importSeries = true;

  // Stalker fields & live probe state
  late final TextEditingController _stalkerUrlCtrl;
  late final TextEditingController _stalkerMacCtrl;
  String? _stalkerToken;
  String? _stalkerExpiry;
  String? _stalkerTestError;
  bool _isTestingStalker = false;

  // Dropdown state
  String _drmScheme = 'none'; // none, clearkey, widevine, playready
  String _manifestType = 'auto'; // auto, mp4, hls, dash, ss
  String _keyEncoding = 'auto'; // auto, base64, hex
  String _requestType = 'download'; // download, get, post
  bool _showMoreOptions = false;

  // URL watcher & MIME inspection state
  Timer? _mimeDebounce;
  String? _probedMime;
  bool _isProbingMime = false;
  bool _showVideoLinkSwitchHint = false;
  bool _nameEditedManually = false;

  bool _isSaving = false;
  String? _errorMsg;

  bool get _isEditing => widget.existingPlaylist != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPlaylist;
    _sourceType = existing?.sourceType ?? widget.initialType;
    _nameEditedManually = existing != null && existing.name.trim().isNotEmpty;

    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _urlCtrl = TextEditingController(
      text: (_sourceType == IptvSourceType.m3uUrl || _sourceType == IptvSourceType.directStream)
          ? (existing?.url ?? '')
          : '',
    );
    _subtitleUrlCtrl = TextEditingController(text: existing?.subtitleUrl ?? '');
    _localContentCtrl = TextEditingController(
      text: _sourceType == IptvSourceType.m3uFile ? (existing?.url ?? '') : '',
    );

    String initLicense = '';
    if (existing?.drm != null) {
      final drm = existing!.drm!;
      _drmScheme = drm.type.name;
      if (drm.manifestType != null && drm.manifestType!.isNotEmpty) {
        _manifestType = drm.manifestType!;
      }
      if (drm.keyEncoding != null && drm.keyEncoding!.isNotEmpty) {
        _keyEncoding = drm.keyEncoding!;
      }
      if (drm.licenseUrl != null && drm.licenseUrl!.isNotEmpty) {
        initLicense = drm.licenseUrl!;
      } else if (drm.clearKeys != null && drm.clearKeys!.isNotEmpty) {
        initLicense = drm.clearKeys!.entries.map((e) => '${e.key}:${e.value}').join(',');
      } else if (drm.kid != null && drm.key != null) {
        initLicense = '${drm.kid}:${drm.key}';
      }
    }
    if (existing?.manifestType != null && existing!.manifestType!.isNotEmpty) {
      _manifestType = existing.manifestType!;
    }

    _drmLicenseCtrl = TextEditingController(text: initLicense);
    _dohCtrl = TextEditingController(text: existing?.dohEndpoint ?? '');
    _epgCtrl = TextEditingController(text: existing?.epgUrl ?? '');

    final initialUa = existing != null ? (existing.userAgent ?? '') : kDefaultIptvUserAgent;
    _userAgentCtrl = TextEditingController(text: initialUa);
    _refererCtrl = TextEditingController(text: existing?.referer ?? '');
    _cookieCtrl = TextEditingController(text: existing?.cookie ?? '');
    _originCtrl = TextEditingController(text: existing?.origin ?? '');
    _authorizationCtrl = TextEditingController(text: existing?.authorization ?? '');
    _extraHeadersCtrl = TextEditingController(
      text: existing != null ? formatExtraHeadersJson(existing.headers) : '',
    );
    _requestType = existing?.requestType ?? 'download';

    _xtreamHostCtrl = TextEditingController(
      text: _sourceType == IptvSourceType.xtream ? (existing?.url ?? '') : '',
    );
    _xtreamUserCtrl = TextEditingController(text: existing?.username ?? '');
    _xtreamPassCtrl = TextEditingController(text: existing?.password ?? '');
    _xtreamStreamFormat = existing?.streamFormat ?? 'TS';
    _xtreamParserType = existing?.parserType ?? 'API Codes';
    _importLive = existing?.importLive ?? true;
    _importVod = existing?.importVod ?? true;
    _importSeries = existing?.importSeries ?? true;

    _stalkerUrlCtrl = TextEditingController(
      text: _sourceType == IptvSourceType.stalker ? (existing?.url ?? '') : '',
    );
    _stalkerMacCtrl = TextEditingController(text: existing?.macAddress ?? '');
    _stalkerToken = existing?.stalkerToken;
    _stalkerExpiry = existing?.stalkerExpiry;

    // Expand More Options automatically when editing a playlist with custom headers
    if (existing != null &&
        ((existing.referer?.isNotEmpty ?? false) ||
            (existing.cookie?.isNotEmpty ?? false) ||
            (existing.origin?.isNotEmpty ?? false) ||
            (existing.authorization?.isNotEmpty ?? false) ||
            existing.headers.isNotEmpty ||
            (existing.requestType != null && existing.requestType != 'download'))) {
      _showMoreOptions = true;
    }

    if (_urlCtrl.text.isNotEmpty) {
      _scheduleMimeProbe(_urlCtrl.text);
    }
  }

  @override
  void dispose() {
    _mimeDebounce?.cancel();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _subtitleUrlCtrl.dispose();
    _drmLicenseCtrl.dispose();
    _dohCtrl.dispose();
    _epgCtrl.dispose();
    _userAgentCtrl.dispose();
    _refererCtrl.dispose();
    _cookieCtrl.dispose();
    _originCtrl.dispose();
    _authorizationCtrl.dispose();
    _extraHeadersCtrl.dispose();
    _localContentCtrl.dispose();
    _xtreamHostCtrl.dispose();
    _xtreamUserCtrl.dispose();
    _xtreamPassCtrl.dispose();
    _stalkerUrlCtrl.dispose();
    _stalkerMacCtrl.dispose();
    super.dispose();
  }

  String get _dialogTitle {
    final prefix = _isEditing ? 'Edit' : '';
    switch (_sourceType) {
      case IptvSourceType.directStream:
        return _isEditing ? '$prefix Video Stream' : 'Network Video Stream';
      case IptvSourceType.m3uUrl:
        return _isEditing ? '$prefix Playlist' : 'Add New Playlist';
      case IptvSourceType.m3uFile:
        return _isEditing ? '$prefix Local Playlist' : 'Local Playlist (M3U/JSON)';
      case IptvSourceType.xtream:
        return _isEditing ? '$prefix Xtream Codes Api' : 'Xtream Codes Api';
      case IptvSourceType.stalker:
        return _isEditing ? '$prefix STB / Stalker Portal' : 'STB / Stalker / MAC Portal';
    }
  }

  void _onUrlChanged(String value) {
    final titleParam = extractTitleQueryParam(value);
    if (titleParam != null && !_nameEditedManually && _nameCtrl.text.trim() != titleParam) {
      _nameCtrl.text = titleParam;
    }

    final shouldSuggestVideo = _sourceType == IptvSourceType.m3uUrl && looksLikeDirectVideoUrl(value);
    if (shouldSuggestVideo != _showVideoLinkSwitchHint) {
      setState(() => _showVideoLinkSwitchHint = shouldSuggestVideo);
    } else {
      setState(() {});
    }

    _scheduleMimeProbe(value);
  }

  void _scheduleMimeProbe(String url) {
    _mimeDebounce?.cancel();
    final trimmed = url.trim().toLowerCase();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (_probedMime != null || _isProbingMime) {
        setState(() {
          _probedMime = null;
          _isProbingMime = false;
        });
      }
      return;
    }

    setState(() {
      _isProbingMime = true;
      _probedMime = null;
    });

    _mimeDebounce = Timer(const Duration(milliseconds: 450), () async {
      final target = _urlCtrl.text.trim();
      final mime = await ref.read(iptvServiceProvider).probeUrlMimeType(
            target,
            headers: _buildHeaderPreview(),
          );
      if (!mounted || _urlCtrl.text.trim() != target) return;
      setState(() {
        _isProbingMime = false;
        _probedMime = mime;
      });
    });
  }

  Map<String, String> _buildHeaderPreview() {
    final map = <String, String>{
      ...parseExtraHeadersInput(_extraHeadersCtrl.text),
    };
    if (_userAgentCtrl.text.trim().isNotEmpty) {
      map['User-Agent'] = _userAgentCtrl.text.trim();
    }
    if (_refererCtrl.text.trim().isNotEmpty) {
      map['Referer'] = _refererCtrl.text.trim();
    }
    if (_cookieCtrl.text.trim().isNotEmpty) {
      map['Cookie'] = _cookieCtrl.text.trim();
    }
    if (_originCtrl.text.trim().isNotEmpty) {
      map['Origin'] = _originCtrl.text.trim();
    }
    if (_authorizationCtrl.text.trim().isNotEmpty) {
      map['Authorization'] = _authorizationCtrl.text.trim();
    }
    return map;
  }

  Future<void> _openUserAgentPicker() async {
    final chosen = await showUserAgentPickerDialog(
      context,
      currentValue: _userAgentCtrl.text,
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _userAgentCtrl.text = chosen;
    });
  }

  Future<void> _openExtraHeadersEditor() async {
    final updatedJson = await showManageExtraHeadersDialog(
      context,
      initialJson: _extraHeadersCtrl.text,
    );
    if (!mounted || updatedJson == null) return;
    setState(() {
      _extraHeadersCtrl.text = updatedJson;
    });
  }

  Future<void> _browseLocalFile() async {
    setState(() {
      _isPickingFile = true;
      _errorMsg = null;
    });
    try {
      final picked = await pickLocalPlaylistFile();
      if (!mounted) return;
      if (picked != null) {
        final stem = picked.name
            .replaceFirst(RegExp(r'\.(m3u8?|json|txt)$', caseSensitive: false), '')
            .trim();
        setState(() {
          _pickedFileName = picked.name;
          _localContentCtrl.text = picked.content;
          if (!_nameEditedManually && stem.isNotEmpty) {
            _nameCtrl.text = stem;
          }
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.message ?? 'Could not read selected file.';
      });
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _testStalkerPortal() async {
    final portal = _stalkerUrlCtrl.text.trim();
    final mac = _stalkerMacCtrl.text.trim();
    if (!isSupportedIptvScheme(portal) || mac.isEmpty) {
      setState(() {
        _stalkerTestError = 'Enter both a valid Portal URL and MAC Address first.';
      });
      return;
    }

    setState(() {
      _isTestingStalker = true;
      _stalkerTestError = null;
    });

    final result = await ref.read(iptvServiceProvider).testStalkerConnection(
          portalUrl: portal,
          macAddress: mac,
        );
    if (!mounted) return;

    setState(() {
      _isTestingStalker = false;
      _stalkerToken = result.token;
      _stalkerExpiry = result.expiry;
      _stalkerTestError = result.error;
    });
  }

  DrmConfig? _buildDrmConfig() {
    if (_drmScheme == 'none') return null;
    final rawLicense = _drmLicenseCtrl.text.trim();
    final encoding = _keyEncoding == 'auto' ? null : _keyEncoding;
    final manifest = _manifestType == 'auto' ? null : _manifestType;

    switch (_drmScheme) {
      case 'clearkey':
        if (rawLicense.isEmpty) return null;
        if (rawLicense.toLowerCase().startsWith('http://') ||
            rawLicense.toLowerCase().startsWith('https://')) {
          return DrmConfig(
            type: DrmType.clearkey,
            licenseUrl: rawLicense,
            manifestType: manifest,
            keyEncoding: encoding,
          );
        }
        final clearKeys = DrmConfig.parseClearKeys(rawLicense);
        if (clearKeys.isNotEmpty) {
          final first = clearKeys.entries.first;
          return DrmConfig(
            type: DrmType.clearkey,
            kid: first.key,
            key: first.value,
            clearKeys: clearKeys,
            manifestType: manifest,
            keyEncoding: encoding,
          );
        }
        return DrmConfig(
          type: DrmType.clearkey,
          licenseUrl: rawLicense,
          manifestType: manifest,
          keyEncoding: encoding,
        );

      case 'widevine':
        return DrmConfig(
          type: DrmType.widevine,
          licenseUrl: rawLicense,
          manifestType: manifest,
          keyEncoding: encoding,
        );

      case 'playready':
        return DrmConfig(
          type: DrmType.playready,
          licenseUrl: rawLicense,
          manifestType: manifest,
          keyEncoding: encoding,
        );
    }
    return null;
  }

  String _resolvePlaylistName() {
    final explicit = _nameCtrl.text.trim();
    if (explicit.isNotEmpty) return explicit;

    switch (_sourceType) {
      case IptvSourceType.directStream:
        return inferPlaylistNameFromUrl(_urlCtrl.text, fallback: 'Direct Stream');
      case IptvSourceType.m3uUrl:
        return inferPlaylistNameFromUrl(_urlCtrl.text, fallback: 'My IPTV Playlist');
      case IptvSourceType.m3uFile:
        if (_pickedFileName != null && _pickedFileName!.trim().isNotEmpty) {
          return _pickedFileName!
              .replaceFirst(RegExp(r'\.(m3u8?|json|txt)$', caseSensitive: false), '')
              .trim();
        }
        return 'Local Playlist';
      case IptvSourceType.xtream:
        return inferPlaylistNameFromUrl(_xtreamHostCtrl.text, fallback: 'Xtream Codes');
      case IptvSourceType.stalker:
        return inferPlaylistNameFromUrl(_stalkerUrlCtrl.text, fallback: 'Stalker Portal');
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      String targetUrl = '';
      switch (_sourceType) {
        case IptvSourceType.m3uUrl:
        case IptvSourceType.directStream:
          targetUrl = _urlCtrl.text.trim();
          break;
        case IptvSourceType.m3uFile:
          targetUrl = _localContentCtrl.text.trim();
          break;
        case IptvSourceType.xtream:
          targetUrl = _xtreamHostCtrl.text.trim();
          break;
        case IptvSourceType.stalker:
          targetUrl = _stalkerUrlCtrl.text.trim();
          break;
      }

      final extraHeaders = parseExtraHeadersInput(_extraHeadersCtrl.text);
      final name = _resolvePlaylistName();
      final now = DateTime.now();
      final existing = widget.existingPlaylist;
      final manifestVal = _manifestType == 'auto' ? null : _manifestType;

      final playlist = IptvPlaylist(
        id: existing?.id ?? 'iptv_${now.millisecondsSinceEpoch}',
        name: name,
        sourceType: _sourceType,
        url: targetUrl,
        username: _sourceType == IptvSourceType.xtream ? _xtreamUserCtrl.text.trim() : null,
        password: _sourceType == IptvSourceType.xtream ? _xtreamPassCtrl.text.trim() : null,
        macAddress: _sourceType == IptvSourceType.stalker
            ? _stalkerMacCtrl.text.trim().replaceAll('-', ':').toUpperCase()
            : null,
        epgUrl: _epgCtrl.text.trim().isNotEmpty ? _epgCtrl.text.trim() : null,
        dohEndpoint: _dohCtrl.text.trim().isNotEmpty ? _dohCtrl.text.trim() : null,
        userAgent: _userAgentCtrl.text.trim().isNotEmpty ? _userAgentCtrl.text.trim() : null,
        referer: _refererCtrl.text.trim().isNotEmpty ? _refererCtrl.text.trim() : null,
        cookie: _cookieCtrl.text.trim().isNotEmpty ? _cookieCtrl.text.trim() : null,
        origin: _originCtrl.text.trim().isNotEmpty ? _originCtrl.text.trim() : null,
        authorization:
            _authorizationCtrl.text.trim().isNotEmpty ? _authorizationCtrl.text.trim() : null,
        requestType: _requestType,
        subtitleUrl:
            _subtitleUrlCtrl.text.trim().isNotEmpty ? _subtitleUrlCtrl.text.trim() : null,
        streamFormat: _sourceType == IptvSourceType.xtream ? _xtreamStreamFormat : null,
        parserType: _sourceType == IptvSourceType.xtream ? _xtreamParserType : null,
        stalkerToken: _sourceType == IptvSourceType.stalker ? _stalkerToken : null,
        stalkerExpiry: _sourceType == IptvSourceType.stalker ? _stalkerExpiry : null,
        manifestType: manifestVal,
        drm: _buildDrmConfig(),
        headers: extraHeaders,
        importLive: _importLive,
        importVod: _importVod,
        importSeries: _importSeries,
        hideAllCategory: existing?.hideAllCategory ?? false,
        addedAt: existing?.addedAt ?? now,
      );

      final notifier = ref.read(iptvPlaylistsProvider.notifier);
      final saved = _isEditing
          ? await notifier.updatePlaylist(playlist, resync: true)
          : await notifier.addPlaylist(playlist);

      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = 'Failed to save source: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Container(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeMode.dividerColor, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(themeMode),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMsg != null) ...[
                      _buildErrorBanner(_errorMsg!),
                      const SizedBox(height: 12),
                    ],
                    if (_sourceType == IptvSourceType.directStream) _buildVideoLinkForm(),
                    if (_sourceType == IptvSourceType.m3uUrl) _buildPlaylistLinkForm(),
                    if (_sourceType == IptvSourceType.m3uFile) _buildLocalPlaylistForm(),
                    if (_sourceType == IptvSourceType.xtream) _buildXtreamForm(),
                    if (_sourceType == IptvSourceType.stalker) _buildStalkerForm(),
                  ],
                ),
              ),
            ),
          ),
          _buildFooter(themeMode, accentColor),
        ],
      ),
    );
  }

  Widget _buildHeader(AppThemeMode themeMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dialogTitle,
              style: GoPlayType.title.copyWith(
                color: themeMode.onSurfaceColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: themeMode.onSurfaceMutedColor),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GoPlayTheme.error.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: GoPlayTheme.error.withAlpha(110)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: GoPlayTheme.error, fontSize: 12.5),
      ),
    );
  }

  Widget _buildVideoLinkForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _nameCtrl,
          label: 'Enter video name',
          hint: 'Auto-detected if left empty',
          onChanged: (_) => _nameEditedManually = true,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _urlCtrl,
          label: 'Media Stream URL',
          hint: 'https://example.com/stream.mpd or .m3u8',
          helper:
              'File video: MP4, MOV, MKV, AVI, 3GP, WebM. Streaming: M3U8, MPD, TS. Protocol: http, https, udp, rtsp, rtmp, ws, srt, ftp',
          keyboardType: TextInputType.url,
          onChanged: _onUrlChanged,
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Enter a stream URL';
            if (!isSupportedIptvScheme(t)) {
              return 'Start with http://, https://, rtsp://, udp://, rtmp://, ws://, srt://, or ftp://';
            }
            return null;
          },
        ),
        _buildMimeHelperRow(),
        const SizedBox(height: 14),
        _buildField(
          controller: _drmLicenseCtrl,
          label: 'DRM License (optional)',
          hint: 'kid:key, JSON, or https://license...',
          helper:
              'Supported formats: TEXT, kid:key, JSON, HTTP, and HTTPS. If you wish to use more than one kid:key pair, separate each pair with a comma (,). Example: kid1:key1,kid2:key2,kid3:key3.',
          maxLines: 3,
          minLines: 1,
          onChanged: (val) {
            final t = val.trim();
            if (_drmScheme == 'none' &&
                t.isNotEmpty &&
                (t.contains(':') && !t.startsWith('http') || t.startsWith('{'))) {
              setState(() => _drmScheme = 'clearkey');
            }
          },
        ),
        const SizedBox(height: 14),
        _buildDropdown<String>(
          label: 'DRM Scheme (optional)',
          value: _drmScheme,
          helper: 'It must match the type of DRM that has been inserted',
          items: kIptvDrmSchemeOptions
              .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
              .toList(),
          onChanged: (v) => setState(() => _drmScheme = v ?? 'none'),
        ),
        const SizedBox(height: 14),
        _buildDropdown<String>(
          label: 'Manifest type (optional)',
          value: _manifestType,
          helper:
              'Sometimes certain videos require a specific manifest type, leave this empty if you are not sure',
          items: kIptvManifestOptions
              .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
              .toList(),
          onChanged: (v) => setState(() => _manifestType = v ?? 'auto'),
        ),
        const SizedBox(height: 14),
        _buildDropdown<String>(
          label: 'DRM Key Encoding (Optional)',
          value: _keyEncoding,
          helper: 'Select the encoding type for the DRM key. If unsure, leave it empty.',
          items: kIptvKeyEncodingOptions
              .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
              .toList(),
          onChanged: (v) => setState(() => _keyEncoding = v ?? 'auto'),
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _subtitleUrlCtrl,
          label: 'Subtitle URL (optional)',
          hint: 'https://example.com/subtitles.vtt or .srt',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),
        _buildDohSection(),
        const SizedBox(height: 12),
        _buildMoreOptionsAccordion(includeDrmFallback: false),
      ],
    );
  }

  Widget _buildPlaylistLinkForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _nameCtrl,
          label: 'Playlist Name (optional)',
          hint: 'Auto-detected from URL or ?title= if empty',
          onChanged: (_) => _nameEditedManually = true,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _urlCtrl,
          label: 'Playlist URL',
          hint: 'https://example.com/playlist.m3u8',
          helper: 'Supported formats: .m3u, .m3u8, .json (http, https, ftp)',
          keyboardType: TextInputType.url,
          onChanged: _onUrlChanged,
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Enter a playlist URL';
            if (!isSupportedIptvScheme(t)) {
              return 'Start with http://, https://, or ftp://';
            }
            return null;
          },
        ),
        _buildMimeHelperRow(),
        if (_showVideoLinkSwitchHint) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ref.watch(activeAccentColorProvider).color.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ref.watch(activeAccentColorProvider).color.withAlpha(90)),
            ),
            child: Row(
              children: [
                Icon(Icons.movie_filter_rounded, size: 18, color: ref.watch(activeAccentColorProvider).color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'This looks like a direct video URL — switch to Video Link?',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sourceType = IptvSourceType.directStream;
                      _showVideoLinkSwitchHint = false;
                    });
                  },
                  child: Text(
                    'SWITCH',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ref.watch(activeAccentColorProvider).color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buildDohSection(),
        const SizedBox(height: 14),
        _buildField(
          controller: _epgCtrl,
          label: 'EPG URL (optional)',
          hint: 'https://example.com/guide.xml',
          helper: 'If the playlist contains #EXTM3U url-tvg="...", it will be detected automatically.',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 14),
        _buildUserAgentField(),
        const SizedBox(height: 12),
        _buildMoreOptionsAccordion(includeUserAgent: false, includeDrmFallback: true),
      ],
    );
  }

  Widget _buildLocalPlaylistForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: (_isSaving || _isPickingFile) ? null : _browseLocalFile,
          icon: _isPickingFile
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open_rounded, size: 19),
          label: Text(
            _isPickingFile ? 'OPENING FILE PICKER...' : 'BROWSE DEVICE FILE (.M3U / .JSON)',
            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: ref.watch(activeAccentColorProvider).color,
            backgroundColor: ref.watch(activeAccentColorProvider).color.withAlpha(18),
            side: BorderSide(color: ref.watch(activeAccentColorProvider).color.withAlpha(90)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_pickedFileName != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: GoPlayTheme.success.withAlpha(24),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: GoPlayTheme.success.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 16, color: GoPlayTheme.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: $_pickedFileName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: GoPlayTheme.success, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _buildField(
          controller: _nameCtrl,
          label: 'Playlist Name',
          hint: 'e.g. Local Channels',
          onChanged: (_) => _nameEditedManually = true,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _localContentCtrl,
          label: 'File Path or Raw M3U / JSON Content',
          hint: '#EXTM3U\n#EXTINF:-1,Channel Name\nhttps://...\nOR /storage/emulated/0/Download/list.m3u',
          helper: 'Pick a file above, paste raw M3U/JSON playlist text, or enter a local file path.',
          maxLines: 6,
          minLines: 4,
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Select a local file or paste M3U / JSON content';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _epgCtrl,
          label: 'EPG URL (optional)',
          hint: 'https://example.com/guide.xml',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _buildMoreOptionsAccordion(includeDrmFallback: true),
      ],
    );
  }

  Widget _buildXtreamForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _nameCtrl,
          label: 'Playlist Name (optional)',
          hint: 'Auto-detected from Host if empty',
          onChanged: (_) => _nameEditedManually = true,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _xtreamHostCtrl,
          label: 'Host URL',
          hint: 'http://provider.example.com:8080',
          keyboardType: TextInputType.url,
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Enter Xtream host URL';
            if (!t.startsWith('http://') && !t.startsWith('https://')) {
              return 'Host must start with http:// or https://';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _xtreamUserCtrl,
          label: 'Username',
          hint: 'username',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter username' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _xtreamPassCtrl,
          obscureText: _obscureXtreamPassword,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: _inputDecoration(
            label: 'Password',
            hint: 'password',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureXtreamPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
                color: Colors.white54,
              ),
              tooltip: _obscureXtreamPassword ? 'Show Password' : 'Hide Password',
              onPressed: () => setState(() => _obscureXtreamPassword = !_obscureXtreamPassword),
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter password' : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildDropdown<String>(
                label: 'Stream Format',
                value: _xtreamStreamFormat,
                items: kIptvXtreamStreamFormats
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() => _xtreamStreamFormat = v ?? 'TS'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDropdown<String>(
                label: 'Parser Type',
                value: _xtreamParserType,
                items: kIptvXtreamParserTypes
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _xtreamParserType = v ?? 'API Codes'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(18)),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: _importLive,
                onChanged: (v) => setState(() => _importLive = v),
                title: const Text(
                  'Import live channel',
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                dense: true,
                activeThumbColor: ref.watch(activeAccentColorProvider).color,
              ),
              Divider(height: 1, color: Colors.white.withAlpha(14)),
              SwitchListTile.adaptive(
                value: _importVod,
                onChanged: (v) => setState(() => _importVod = v),
                title: const Text(
                  'Import VODs',
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                dense: true,
                activeThumbColor: ref.watch(activeAccentColorProvider).color,
              ),
              Divider(height: 1, color: Colors.white.withAlpha(14)),
              SwitchListTile.adaptive(
                value: _importSeries,
                onChanged: (v) => setState(() => _importSeries = v),
                title: const Text(
                  'Import series',
                  style: TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                dense: true,
                activeThumbColor: ref.watch(activeAccentColorProvider).color,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildMoreOptionsAccordion(includeDrmFallback: false),
      ],
    );
  }

  Widget _buildStalkerForm() {
    final portalPreview =
        _stalkerUrlCtrl.text.trim().isEmpty ? '—' : _stalkerUrlCtrl.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _nameCtrl,
          label: 'Playlist Name (optional)',
          hint: 'Auto-detected from Portal if empty',
          onChanged: (_) => _nameEditedManually = true,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _stalkerUrlCtrl,
          label: 'Server Address / Portal URL',
          hint: 'http://portal.example.com/c/',
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          validator: (v) {
            final t = v?.trim() ?? '';
            if (t.isEmpty) return 'Enter Stalker portal URL';
            if (!t.startsWith('http://') && !t.startsWith('https://')) {
              return 'Portal URL must start with http:// or https://';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _stalkerMacCtrl,
          label: 'MAC Address',
          hint: '00:1A:79:XX:XX:XX',
          helper: 'Standard MAG STB hardware MAC address associated with this portal.',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a valid MAC address' : null,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ref.watch(activeThemeModeProvider).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ref.watch(activeThemeModeProvider).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.router_rounded, size: 16, color: ref.watch(activeAccentColorProvider).color),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Portal Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: (_isSaving || _isTestingStalker) ? null : _testStalkerPortal,
                    icon: _isTestingStalker
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: Text(_isTestingStalker ? 'TESTING...' : 'TEST CONNECTION'),
                    style: TextButton.styleFrom(
                      foregroundColor: ref.watch(activeAccentColorProvider).color,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildStatusRow('TOKEN', _stalkerToken ?? 'Not tested'),
              const SizedBox(height: 4),
              _buildStatusRow('EXPIRED', _stalkerExpiry ?? '—'),
              const SizedBox(height: 4),
              _buildStatusRow('MAC PORTAL', portalPreview),
              if (_stalkerTestError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _stalkerTestError!,
                  style: const TextStyle(color: GoPlayTheme.error, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: GoPlayTheme.darkOnSurfaceMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildMimeHelperRow() {
    if (!_isProbingMime && (_probedMime == null || _probedMime!.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        children: [
          if (_isProbingMime)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            ),
          Expanded(
            child: Text(
              '> Mime Type: ${_isProbingMime ? 'Loading...' : _probedMime}',
              style: TextStyle(
                color: ref.watch(activeAccentColorProvider).color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDohSection() {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _dohCtrl,
          label: 'DNS over HTTPS (DoH) Endpoint (optional)',
          hint: 'https://cloudflare-dns.com/dns-query',
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: kIptvDohPresets.map((preset) {
            final selected = _dohCtrl.text.trim() == preset.url;
            return ActionChip(
              label: Text(preset.label, style: const TextStyle(fontSize: 11.5)),
              avatar: Icon(
                selected ? Icons.check_circle_rounded : Icons.dns_rounded,
                size: 14,
                color: selected ? accentColor.color : themeMode.onSurfaceMutedColor,
              ),
              backgroundColor: selected
                  ? accentColor.color.withAlpha(28)
                  : themeMode.cardColor,
              side: BorderSide(
                color: selected
                    ? accentColor.color.withAlpha(110)
                    : themeMode.dividerColor,
              ),
              labelStyle: TextStyle(
                color: selected ? accentColor.color : themeMode.onSurfaceMutedColor,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  _dohCtrl.text = preset.url;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUserAgentField() {
    return TextFormField(
      controller: _userAgentCtrl,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      onChanged: (_) => setState(() {}),
      decoration: _inputDecoration(
        label: 'User-Agent (optional)',
        hint: 'Custom browser or player User-Agent',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, size: 19, color: ref.watch(activeAccentColorProvider).color),
              tooltip: 'Choose User-Agent Preset',
              onPressed: _openUserAgentPicker,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
            ),
            if (_userAgentCtrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                tooltip: 'Clear User-Agent',
                onPressed: () => setState(() => _userAgentCtrl.clear()),
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraHeaderField() {
    return TextFormField(
      controller: _extraHeadersCtrl,
      maxLines: 3,
      minLines: 1,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      onChanged: (_) => setState(() {}),
      decoration: _inputDecoration(
        label: 'Extra Header (optional)',
        hint: '{"X-Api-Key": "value"} or Header: Value',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, size: 19, color: ref.watch(activeAccentColorProvider).color),
              tooltip: 'Manage Extra Headers',
              onPressed: _openExtraHeadersEditor,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
            ),
            if (_extraHeadersCtrl.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                tooltip: 'Clear Extra Headers',
                onPressed: () => setState(() => _extraHeadersCtrl.clear()),
                constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreOptionsAccordion({
    bool includeUserAgent = true,
    required bool includeDrmFallback,
  }) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _showMoreOptions = !_showMoreOptions),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: _showMoreOptions ? accentColor.color : themeMode.onSurfaceMutedColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showMoreOptions ? 'Hide More Options' : 'More Options',
                    style: TextStyle(
                      color: _showMoreOptions ? accentColor.color : themeMode.onSurfaceColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  _showMoreOptions ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: themeMode.onSurfaceMutedColor,
                ),
              ],
            ),
          ),
        ),
        if (_showMoreOptions) ...[
          const SizedBox(height: 8),
          _buildDropdown<String>(
            label: 'Request type',
            value: _requestType,
            items: kIptvRequestTypes
                .map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                .toList(),
            onChanged: (v) => setState(() => _requestType = v ?? 'download'),
          ),
          const SizedBox(height: 12),
          if (includeUserAgent) ...[
            _buildUserAgentField(),
            const SizedBox(height: 12),
          ],
          _buildField(
            controller: _refererCtrl,
            label: 'Referer (optional)',
            hint: 'https://player-origin.example.com/',
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _originCtrl,
            label: 'Origin (optional)',
            hint: 'https://player-origin.example.com',
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _authorizationCtrl,
            label: 'Authorization (optional)',
            hint: 'Bearer <access_token>',
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: _cookieCtrl,
            label: 'Cookie (optional)',
            hint: 'session=...; Edge-Cache-Cookie=...',
          ),
          const SizedBox(height: 12),
          _buildExtraHeaderField(),
          if (includeDrmFallback) ...[
            const SizedBox(height: 14),
            const Text(
              'Default DRM Fallback (optional)',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _buildDropdown<String>(
              label: 'DRM Scheme (optional)',
              value: _drmScheme,
              items: kIptvDrmSchemeOptions
                  .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
                  .toList(),
              onChanged: (v) => setState(() => _drmScheme = v ?? 'none'),
            ),
            if (_drmScheme != 'none') ...[
              const SizedBox(height: 10),
              _buildField(
                controller: _drmLicenseCtrl,
                label: 'Default DRM License',
                hint: 'kid:key or https://license.example.com/',
              ),
            ],
            const SizedBox(height: 10),
            _buildDropdown<String>(
              label: 'Manifest type (optional)',
              value: _manifestType,
              items: kIptvManifestOptions
                  .map((o) => DropdownMenuItem(value: o.value, child: Text(o.label)))
                  .toList(),
              onChanged: (v) => setState(() => _manifestType = v ?? 'auto'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildFooter(AppThemeMode themeMode, AppAccentColor accentColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: themeMode.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: themeMode.onSurfaceMutedColor,
                side: BorderSide(color: themeMode.dividerColor),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _isSaving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor.color,
                foregroundColor: accentColor.onAccentColor,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accentColor.onAccentColor),
                    )
                  : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? minLines,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: (val) {
        if (onChanged != null) {
          onChanged(val);
        } else {
          setState(() {});
        }
      },
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        helper: helper,
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 17, color: Colors.white54),
                tooltip: 'Clear $label',
                onPressed: () {
                  controller.clear();
                  if (onChanged != null) {
                    onChanged('');
                  } else {
                    setState(() {});
                  }
                },
              )
            : null,
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? helper,
  }) {
    final themeMode = ref.watch(activeThemeModeProvider);

    return DropdownButtonFormField<T>(
      key: ValueKey('${label}_$value'),
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: true,
      dropdownColor: themeMode.surfaceContainerHigh,
      style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13.5),
      decoration: _inputDecoration(label: label, helper: helper),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 4,
      helperStyle: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 11.5),
      labelStyle: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 13.5),
      hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor.withAlpha(120), fontSize: 13),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: themeMode.cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: GoPlayTheme.error),
      ),
    );
  }
}
