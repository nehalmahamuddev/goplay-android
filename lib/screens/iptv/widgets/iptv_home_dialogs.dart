import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';

/// Interactive multi-section How-To Guide replicating the APK's
/// `GuideActivity` and `bottom_dialog_guide_playlist` (`res/UI.xml`).
class IptvGuideSheet extends ConsumerStatefulWidget {
  const IptvGuideSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IptvGuideSheet(),
    );
  }

  @override
  ConsumerState<IptvGuideSheet> createState() => _IptvGuideSheetState();
}

class _IptvGuideSheetState extends ConsumerState<IptvGuideSheet> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final steps = _selectedTab == 0 ? _playlistSteps : _streamSteps;
    final sheetBg =
        Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            themeMode.bottomNavColor;
    final recessedBg = Color.lerp(
      sheetBg,
      Colors.black,
      themeMode.isDark ? 0.38 : 0.04,
    )!;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: accentColor.color,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'IPTV & DRM Stream Guide',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: themeMode.onSurfaceMutedColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tab switcher (Playlist Guide vs Network Stream & DRM)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: recessedBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: themeMode.dividerColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _GuideTabButton(
                    label: 'Playlists & EPG',
                    selected: _selectedTab == 0,
                    onTap: () => setState(() => _selectedTab = 0),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _GuideTabButton(
                    label: 'Network & DRM',
                    selected: _selectedTab == 1,
                    onTap: () => setState(() => _selectedTab = 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selectedTab == 0
                        ? 'How to Add a Playlist to Your IPTV App'
                        : 'How to Add a Video to Your Network Stream',
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accentColor.color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < steps.length; i++) ...[
                    _GuideStepTile(
                      stepNumber: i + 1,
                      title: steps[i].title,
                      body: steps[i].body,
                      backgroundColor: recessedBg,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: recessedBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: themeMode.dividerColor),
                    ),
                    child: Text(
                      'Tip: Long-press and drag the ⋮⋮ handle on any playlist card in Custom Order mode to reorder playlists, or use the grid select icon to batch-export or delete multiple playlists.',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12,
                        color: themeMode.onSurfaceMutedColor,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref
                        .read(iptvPlaylistsProvider.notifier)
                        .importSamplePlaylist();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor.color,
                    side: BorderSide(color: themeMode.dividerColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('LOAD SAMPLE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor.color,
                    foregroundColor: accentColor.onAccentColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'GOT IT',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideStepData {
  final String title;
  final String body;
  const _GuideStepData(this.title, this.body);
}

const List<_GuideStepData> _playlistSteps = [
  _GuideStepData(
    'Open the Add Menu (+)',
    'Tap the (+) button in the bottom-right corner and select Playlist Link (M3U/JSON), Local Playlist, Xtream Codes, or STB / Stalker / MAC Portal.',
  ),
  _GuideStepData(
    'Enter Source & Optional EPG',
    'Give your playlist a name and paste the URL (supports .m3u, .m3u8, .json, .html, .php). Optionally attach an XMLTV (.xml / .xml.gz) EPG URL or DNS-over-HTTPS endpoint.',
  ),
  _GuideStepData(
    'Browse Categories & Layouts',
    'Tap any card or [Playlist] to jump between category tabs, filter channels live, switch between List, Grid, Poster, and Square views, or bookmark channels with category folders.',
  ),
  _GuideStepData(
    'Manage TV Guides (XMLTV)',
    'Tap the TV Guide icon in the top bar (or Add Teleguide EPG from the + menu) to save global XMLTV guides, sync all feeds, or attach an EPG feed to a playlist.',
  ),
];

const List<_GuideStepData> _streamSteps = [
  _GuideStepData(
    'Choose Video Link',
    'From the (+) menu, tap Video Link to configure an individual live stream or VOD URL (HLS .m3u8, DASH .mpd, TS, MP4, MKV, RTMP, or RTSP).',
  ),
  _GuideStepData(
    'Configure DRM License',
    'Paste ClearKey keys (kid:key pairs, comma-separated multi-keys, JWK JSON, or license URL) or a Widevine / PlayReady license server URL.',
  ),
  _GuideStepData(
    'Select DRM Scheme & Manifest',
    'Pick ClearKey, Widevine, or PlayReady under DRM Scheme and optionally force HLS (M3U8), DASH (MPD), or Progressive MP4 if auto-detection needs help.',
  ),
  _GuideStepData(
    'Attach Request Headers',
    'Expand Optional HTTP Headers to specify custom User-Agent, Referer, Cookie, Origin, or extra JSON headers required by protected origins.',
  ),
];

class _GuideTabButton extends ConsumerWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GuideTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Material(
      color: selected ? accentColor.color : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? accentColor.onAccentColor : themeMode.onSurfaceMutedColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideStepTile extends ConsumerWidget {
  final int stepNumber;
  final String title;
  final String body;
  final Color? backgroundColor;

  const _GuideStepTile({
    required this.stepNumber,
    required this.title,
    required this.body,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ?? themeMode.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeMode.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accentColor.color.withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: accentColor.color.withAlpha(100)),
            ),
            alignment: Alignment.center,
            child: Text(
              '$stepNumber',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accentColor.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 12,
                    color: themeMode.onSurfaceMutedColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Manage TV Guide (EPG) sheet replicating the APK's `ManageEpgActivity`,
/// `menu_manage_epg`, and `dialog_add_epg` (`res/wa.xml`).
class IptvManageEpgSheet extends ConsumerStatefulWidget {
  const IptvManageEpgSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IptvManageEpgSheet(),
    );
  }

  /// Opens the APK-matching `Add EPG Link` modal (`res/wa.xml`).
  static Future<IptvEpgSource?> showAddEpgDialog(
    BuildContext context, {
    String? initialName,
    String? initialUrl,
  }) {
    return showDialog<IptvEpgSource?>(
      context: context,
      builder: (_) => _AddEpgLinkDialog(
        initialName: initialName,
        initialUrl: initialUrl,
      ),
    );
  }

  @override
  ConsumerState<IptvManageEpgSheet> createState() => _IptvManageEpgSheetState();
}

class _AddEpgLinkDialog extends ConsumerStatefulWidget {
  final String? initialName;
  final String? initialUrl;

  const _AddEpgLinkDialog({
    this.initialName,
    this.initialUrl,
  });

  @override
  ConsumerState<_AddEpgLinkDialog> createState() => _AddEpgLinkDialogState();
}

class _AddEpgLinkDialogState extends ConsumerState<_AddEpgLinkDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return AlertDialog(
      backgroundColor: themeMode.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: themeMode.dividerColor),
      ),
      title: Text(
        'Add EPG Link',
        style: TextStyle(
          fontFamily: GoPlayType.family,
          color: themeMode.onSurfaceColor,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Any name (e.g. Global TV Guide)',
                hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor),
                filled: true,
                fillColor: themeMode.cardColor,
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
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Enter EPG URL (.xml / .xml.gz)',
                hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor),
                filled: true,
                fillColor: themeMode.cardColor,
                suffixIcon: IconButton(
                  tooltip: 'Paste URL',
                  icon: Icon(
                    Icons.content_paste_rounded,
                    color: themeMode.onSurfaceMutedColor,
                    size: 18,
                  ),
                  onPressed: () async {
                    final clip = await Clipboard.getData('text/plain');
                    if (clip?.text != null && mounted) {
                      _urlCtrl.text = clip!.text!.trim();
                    }
                  },
                ),
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
            Text(
              'Supports standard XMLTV (.xml) and gzip-compressed (.xml.gz) guides.',
              style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 11.5),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(color: GoPlayTheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(null),
          child: Text('CANCEL', style: TextStyle(color: themeMode.onSurfaceMutedColor)),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final rawUrl = _urlCtrl.text.trim();
                  if (rawUrl.isEmpty ||
                      (!rawUrl.startsWith('http://') &&
                          !rawUrl.startsWith('https://'))) {
                    setState(
                      () => _errorText = 'Enter a valid http/https EPG URL',
                    );
                    return;
                  }
                  setState(() {
                    _saving = true;
                    _errorText = null;
                  });
                  final added = await ref
                      .read(iptvSavedEpgSourcesProvider.notifier)
                      .addOrUpdateSource(
                        name: _nameCtrl.text,
                        url: rawUrl,
                      );
                  if (context.mounted) {
                    Navigator.of(context).pop(added);
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor.color,
            foregroundColor: accentColor.onAccentColor,
          ),
          child: _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accentColor.onAccentColor,
                  ),
                )
              : const Text(
                  'SAVE',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }
}

class _IptvManageEpgSheetState extends ConsumerState<IptvManageEpgSheet> {
  final Set<String> _syncingIds = {};
  bool _syncingAll = false;

  Future<void> _assignEpgToPlaylist(String epgUrl) async {
    final themeMode = ref.read(activeThemeModeProvider);
    final playlists = ref.read(iptvPlaylistsProvider).value ?? const [];
    if (playlists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add a playlist first to link this TV Guide'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final target = await showDialog<IptvPlaylist?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeMode.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: themeMode.dividerColor),
        ),
        title: Text(
          'Attach EPG to Playlist',
          style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: playlists.length,
            itemBuilder: (_, index) {
              final p = playlists[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  p.name,
                  style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 14),
                ),
                subtitle: Text(
                  p.epgUrl != null && p.epgUrl!.isNotEmpty
                      ? 'Current EPG: ${p.epgUrl}'
                      : '${p.channelCount} channels',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 11.5),
                ),
                onTap: () => Navigator.of(ctx).pop(p),
              );
            },
          ),
        ),
      ),
    );

    if (target != null) {
      final updated = target.copyWith(epgUrl: epgUrl);
      await ref.read(iptvPlaylistsProvider.notifier).updatePlaylist(updated);
      await ref
          .read(iptvEpgProvider.notifier)
          .loadEpgForPlaylist(updated, forceRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Linked EPG to "${target.name}"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final sources = ref.watch(iptvSavedEpgSourcesProvider);
    final playlists = ref.watch(iptvPlaylistsProvider).value ?? const [];
    final attachedPlaylists = playlists
        .where((p) => p.epgUrl != null && p.epgUrl!.trim().isNotEmpty)
        .toList();
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 18 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header + Update All / Delete All actions (matching menu_manage_epg)
          Row(
            children: [
              Icon(Icons.dvr_rounded, color: accentColor.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Manage TV Guide',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
              ),
              if (sources.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Update All EPGs',
                  onPressed: _syncingAll
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _syncingAll = true);
                          final count = await ref
                              .read(iptvSavedEpgSourcesProvider.notifier)
                              .syncAllSources();
                          if (mounted) {
                            setState(() => _syncingAll = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Synced ${sources.length} EPG guide(s) ($count channel guides)',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                  icon: _syncingAll
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor.color,
                          ),
                        )
                      : Icon(
                          Icons.sync_rounded,
                          color: themeMode.onSurfaceMutedColor,
                          size: 20,
                        ),
                ),
                IconButton(
                  tooltip: 'Delete All EPGs',
                  onPressed: () async {
                    await ref
                        .read(iptvSavedEpgSourcesProvider.notifier)
                        .clearAllSources();
                  },
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: GoPlayTheme.error,
                    size: 20,
                  ),
                ),
              ],
              IconButton(
                tooltip: 'Add EPG Link',
                onPressed: () => IptvManageEpgSheet.showAddEpgDialog(context),
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: accentColor.color,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Flexible(
            child: (sources.isEmpty && attachedPlaylists.isEmpty)
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 42,
                          color: themeMode.onSurfaceMutedColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No XMLTV TV Guides Saved',
                          style: TextStyle(
                            color: themeMode.onSurfaceColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add an .xml or .xml.gz XMLTV guide URL to load programme schedules across playlists.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: themeMode.onSurfaceMutedColor,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () =>
                              IptvManageEpgSheet.showAddEpgDialog(context),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'ADD EPG LINK',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor.color,
                            foregroundColor: accentColor.onAccentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final src in sources)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: themeMode.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: themeMode.dividerColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      src.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      src.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceMutedColor,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      src.channelCount > 0
                                          ? '${src.channelCount} channel guide(s) loaded'
                                          : 'Tap sync to fetch programme listings',
                                      style: TextStyle(
                                        color: accentColor.color,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Attach to playlist',
                                icon: Icon(
                                  Icons.playlist_add_check_rounded,
                                  color: accentColor.color,
                                  size: 20,
                                ),
                                onPressed: () => _assignEpgToPlaylist(src.url),
                              ),
                              IconButton(
                                tooltip: 'Sync EPG',
                                icon: _syncingIds.contains(src.id)
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accentColor.color,
                                        ),
                                      )
                                    : Icon(
                                        Icons.refresh_rounded,
                                        color: themeMode.onSurfaceMutedColor,
                                        size: 19,
                                      ),
                                onPressed: () async {
                                  setState(() => _syncingIds.add(src.id));
                                  await ref
                                      .read(iptvSavedEpgSourcesProvider.notifier)
                                      .syncSource(src.id);
                                  if (mounted) {
                                    setState(() => _syncingIds.remove(src.id));
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete EPG',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: GoPlayTheme.error,
                                  size: 19,
                                ),
                                onPressed: () => ref
                                    .read(iptvSavedEpgSourcesProvider.notifier)
                                    .removeSource(src.id),
                              ),
                            ],
                          ),
                        ),
                      if (attachedPlaylists.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Text(
                            'Playlist-Attached TV Guides',
                            style: TextStyle(
                              color: themeMode.onSurfaceMutedColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final p in attachedPlaylists)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            tileColor: themeMode.cardColor,
                            leading: Icon(
                              Icons.tv_rounded,
                              color: accentColor.color,
                              size: 18,
                            ),
                            title: Text(
                              p.name,
                              style: TextStyle(
                                color: themeMode.onSurfaceColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              p.epgUrl ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: themeMode.onSurfaceMutedColor,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Refresh playlist EPG',
                              icon: Icon(
                                Icons.sync_rounded,
                                color: themeMode.onSurfaceMutedColor,
                                size: 18,
                              ),
                              onPressed: () => ref
                                  .read(iptvEpgProvider.notifier)
                                  .loadEpgForPlaylist(p, forceRefresh: true),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Playlist metadata & technical summary dialog opened from the card 3-dot menu.
class IptvPlaylistInfoDialog extends ConsumerWidget {
  final IptvPlaylist playlist;

  const IptvPlaylistInfoDialog({super.key, required this.playlist});

  static Future<void> show(BuildContext context, IptvPlaylist playlist) {
    return showDialog(
      context: context,
      builder: (_) => IptvPlaylistInfoDialog(playlist: playlist),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final added = playlist.addedAt.toLocal().toString().split('.').first;
    final synced = playlist.lastSync?.toLocal().toString().split('.').first ??
        'Not synced yet';

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: themeMode.onSurfaceMutedColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              value,
              style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: themeMode.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: themeMode.dividerColor),
      ),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: themeMode.onSurfaceColor,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Source Type', playlist.sourceType.label),
            row('Source URL', playlist.url),
            row('Channels', '${playlist.channelCount}'),
            row('Added At', added),
            row('Last Sync', synced),
            if (playlist.epgUrl != null && playlist.epgUrl!.isNotEmpty)
              row('EPG Guide URL', playlist.epgUrl!),
            if (playlist.drm != null)
              row('Default DRM Scheme', playlist.drm!.type.name.toUpperCase()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: playlist.url));
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Playlist URL copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Text('COPY URL', style: TextStyle(color: accentColor.color)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor.color,
            foregroundColor: accentColor.onAccentColor,
          ),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
