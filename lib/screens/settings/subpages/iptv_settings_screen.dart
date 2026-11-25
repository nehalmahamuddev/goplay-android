import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../iptv/widgets/iptv_category_sheets.dart';
import '../../iptv/widgets/iptv_home_dialogs.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Dedicated IPTV Settings Screen matching GoPlay's settings architecture
/// and theme layout conventions.
class IptvSettingsScreen extends ConsumerWidget {
  const IptvSettingsScreen({super.key});

  Future<void> _showBackgroundPicker(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _BackgroundPickerSheet(),
    );
  }

  Future<void> _showImportBackupDialog(BuildContext context, WidgetRef ref) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.read(activeThemeModeProvider);

    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ImportBackupDialog(),
    );

    if (raw != null && raw.isNotEmpty && context.mounted) {
      final count = await ref
          .read(iptvPlaylistsProvider.notifier)
          .importBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: themeMode.surfaceContainerHigh,
            content: Text(
              count > 0
                  ? 'Imported $count playlist(s) from backup'
                  : 'No valid playlists found in JSON backup',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                color: cs.onSurface,
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.read(activeThemeModeProvider);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: themeMode.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: themeMode.dividerColor, width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: GoPlayTheme.error, size: 24),
            const SizedBox(width: 10),
            Text(
              'Clear All Playlists?',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          'This will permanently delete all imported IPTV playlists and cached channel indexes. This action cannot be undone.',
          style: TextStyle(
            fontFamily: GoPlayType.family,
            fontSize: 14,
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GoPlayTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'CLEAR ALL',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(iptvPlaylistsProvider.notifier).clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: themeMode.surfaceContainerHigh,
            content: Text(
              'All playlists cleared',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                color: cs.onSurface,
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg =
        theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final settings = ref.watch(iptvSettingsProvider);
    final bookmarkCount = ref.watch(iptvBookmarksProvider).length;
    final epgCount = ref.watch(iptvSavedEpgSourcesProvider).length;

    return Scaffold(
      backgroundColor: cs.surface,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/settings');
          }
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Pinned App Bar matching other subpages
            SliverAppBar(
              pinned: true,
              floating: false,
              backgroundColor: headerBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
                tooltip: 'Back',
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/settings');
                  }
                },
              ),
              title: Text(
                'IPTV',
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ),

            SliverList(
              delegate: SliverChildListDelegate([
                // ─── 1. Display & Navigation ───
                const SettingSectionHeader(title: 'Display & Navigation'),
                SettingSwitchTile(
                  icon: Icons.sort_rounded,
                  title: 'Sort Categories by Channel Count',
                  subtitle: 'Orders group tabs largest-first after "All"',
                  value: settings.sortCategoriesByCount,
                  onChanged: (val) => ref
                      .read(iptvSettingsProvider.notifier)
                      .toggleSortCategoriesByCount(val),
                ),
                SettingSwitchTile(
                  icon: Icons.tab_unselected_rounded,
                  title: 'Hide "All" Category Tab',
                  subtitle: 'Jump straight to the first group inside playlists',
                  value: settings.hideAllCategory,
                  onChanged: (val) => ref
                      .read(iptvSettingsProvider.notifier)
                      .toggleHideAllCategory(val),
                ),
                SettingSwitchTile(
                  icon: Icons.cached_rounded,
                  title: '24-Hour Smart Playlist Cache',
                  subtitle: 'Instant 0ms load when synced within the last 24h',
                  value: settings.cacheEnabled,
                  onChanged: (val) => ref
                      .read(iptvSettingsProvider.notifier)
                      .toggleCacheEnabled(val),
                ),

                SettingTile(
                  icon: Icons.wallpaper_rounded,
                  title: 'Page Background',
                  subtitle: _bgModeLabel(settings.backgroundMode),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BgModeChip(mode: settings.backgroundMode),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  onTap: () => _showBackgroundPicker(context, ref),
                ),

                const SizedBox(height: 12),

                // ─── 2. TV Guide & Bookmarks ───
                const SettingSectionHeader(title: 'TV Guide & Bookmarks'),
                SettingTile(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'Saved Bookmarks ($bookmarkCount)',
                  subtitle: 'Quick access to bookmarked IPTV channels',
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  onTap: () {
                    IptvBookmarksSheet.show(
                      context,
                      onPlayChannel: (ch, scope) => launchIptvChannelPlayback(
                        context,
                        ref,
                        channel: ch,
                        scopeChannels: scope,
                      ),
                    );
                  },
                ),
                SettingTile(
                  icon: Icons.dvr_rounded,
                  title: 'Manage TV Guides ($epgCount)',
                  subtitle: 'Add, update or remove external XMLTV EPG sources',
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  onTap: () {
                    IptvManageEpgSheet.show(context);
                  },
                ),
                SettingTile(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear Cached EPG Guide Data',
                  subtitle: 'Remove cached electronic programme schedule data',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(iptvEpgProvider.notifier).clearAll();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: themeMode.surfaceContainerHigh,
                        content: Text(
                          'Cleared cached EPG programme data',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            color: cs.onSurface,
                          ),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 12),

                // ─── 3. Backup & Data Management ───
                const SettingSectionHeader(title: 'Backup & Data Management'),
                SettingTile(
                  icon: Icons.upload_file_rounded,
                  title: 'Export Playlists Backup',
                  subtitle: 'Copy playlist configuration JSON to clipboard',
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final jsonStr = ref
                        .read(iptvPlaylistsProvider.notifier)
                        .exportBackupJson();
                    await Clipboard.setData(ClipboardData(text: jsonStr));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: themeMode.surfaceContainerHigh,
                          content: Text(
                            'Backup JSON copied to clipboard!',
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              color: cs.onSurface,
                            ),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                SettingTile(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Import JSON Backup',
                  subtitle: 'Restore playlists from an exported JSON backup',
                  onTap: () => _showImportBackupDialog(context, ref),
                ),
                SettingTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Load Free Demo Streams',
                  subtitle: 'Import tested public live streams and test channels',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref
                        .read(iptvPlaylistsProvider.notifier)
                        .importSamplePlaylist();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: themeMode.surfaceContainerHigh,
                        content: Text(
                          'Demo streams loaded successfully!',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            color: cs.onSurface,
                          ),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                SettingTile(
                  icon: Icons.delete_sweep_rounded,
                  title: 'Clear All Playlists',
                  subtitle: 'Remove all imported IPTV playlists and channel indexes',
                  titleColor: GoPlayTheme.error,
                  subtitleColor: GoPlayTheme.error.withValues(alpha: 0.8),
                  leading: Icon(
                    Icons.delete_sweep_rounded,
                    color: GoPlayTheme.error,
                    size: 24,
                  ),
                  onTap: () => _confirmClearAll(context, ref),
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Background mode helpers ───────────────────────────────────────────────

String _bgModeLabel(IptvBackgroundMode mode) {
  switch (mode) {
    case IptvBackgroundMode.animated:
      return 'Animated gradient mesh';
    case IptvBackgroundMode.customImage:
      return 'Custom image from gallery';
    case IptvBackgroundMode.defaultTheme:
      return 'App default (theme background)';
  }
}

class _BgModeChip extends StatelessWidget {
  final IptvBackgroundMode mode;
  const _BgModeChip({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (mode) {
      IptvBackgroundMode.defaultTheme => ('Default', const Color(0xFF6E6E6E)),
      IptvBackgroundMode.animated => ('Animated', const Color(0xFF6B11A8)),
      IptvBackgroundMode.customImage => ('Custom', const Color(0xFF007799)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── Background Picker Bottom Sheet ────────────────────────────────────────

class _BackgroundPickerSheet extends ConsumerStatefulWidget {
  const _BackgroundPickerSheet();

  @override
  ConsumerState<_BackgroundPickerSheet> createState() =>
      _BackgroundPickerSheetState();
}

class _BackgroundPickerSheetState
    extends ConsumerState<_BackgroundPickerSheet> {
  bool _picking = false;

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null && mounted) {
        await ref
            .read(iptvSettingsProvider.notifier)
            .setBackgroundMode(IptvBackgroundMode.customImage, imagePath: file.path);
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final cs = Theme.of(context).colorScheme;
    final current = ref.watch(iptvSettingsProvider).backgroundMode;

    Widget optionTile({
      required IptvBackgroundMode mode,
      required IconData icon,
      required String title,
      required String subtitle,
      VoidCallback? onSelect,
    }) {
      final selected = current == mode;
      return InkWell(
        onTap: onSelect ??
            () async {
              await ref
                  .read(iptvSettingsProvider.notifier)
                  .setBackgroundMode(mode);
              if (context.mounted) Navigator.of(context).pop();
            },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.1)
                : themeMode.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? cs.primary.withValues(alpha: 0.5)
                  : themeMode.dividerColor,
              width: selected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.15)
                      : themeMode.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? cs.primary : themeMode.onSurfaceMutedColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? cs.primary : themeMode.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12,
                        color: themeMode.onSurfaceMutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Page Background',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: themeMode.onSurfaceColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Choose how the IPTV screen background looks',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 12.5,
                color: themeMode.onSurfaceMutedColor,
              ),
            ),
          ),
          optionTile(
            mode: IptvBackgroundMode.defaultTheme,
            icon: Icons.contrast_rounded,
            title: 'Default Theme',
            subtitle: 'Solid dark or light background from your app theme',
          ),
          optionTile(
            mode: IptvBackgroundMode.animated,
            icon: Icons.auto_awesome_rounded,
            title: 'Animated Gradient',
            subtitle: 'Fluid purple/cyan shader mesh animation',
          ),
          optionTile(
            mode: IptvBackgroundMode.customImage,
            icon: Icons.image_rounded,
            title: 'Custom Image',
            subtitle: 'Pick a photo from your gallery',
            onSelect: _picking ? null : _pickImage,
          ),
          if (_picking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
        ],
      ),
    );
  }
}

// ─── Import Backup Dialog ───────────────────────────────────────────────────

class _ImportBackupDialog extends StatefulWidget {
  const _ImportBackupDialog();

  @override
  State<_ImportBackupDialog> createState() => _ImportBackupDialogState();
}

class _ImportBackupDialogState extends State<_ImportBackupDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      backgroundColor: const Color(0xFF161616),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        'Import JSON Backup',
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          color: cs.onSurface,
          fontSize: 13,
        ),
        decoration: InputDecoration(
          hintText: 'Paste exported IPTV backup JSON array...',
          hintStyle: TextStyle(
            fontFamily: GoPlayType.family,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            fontSize: 13,
          ),
          filled: true,
          fillColor: const Color(0xFF0F0F0F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            'CANCEL',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          child: const Text(
            'IMPORT',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
