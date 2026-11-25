import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/iptv_service.dart';
import '../../../widgets/cards/clean_card.dart';
import 'iptv_add_source_dialog.dart';
import 'iptv_channel_browser_sheet.dart';
import 'iptv_home_dialogs.dart';
import 'iptv_svg_icon.dart';

/// Clean Liquid Glass card component representing an imported IPTV playlist,
/// designed from scratch using Kyant's Backdrop library specifications
/// (https://kyant.gitbook.io/backdrop).
///
/// Features:
/// 1. Progressive Gaussian backdrop blur (`BackdropFilter`).
/// 2. Multi-stop translucent glass substrate wash gradient.
/// 3. Physical optics:
///    - Diagonal specular outer rim stroke (Inside alignment).
///    - SDF lens refraction caustic bevel (simulating physical glass thickness).
///    - Top-left directional specular glint (`dot(grad, normal)^falloff`).
///    - Chromatic dispersion fringe along edges.
/// 4. Radiant glass emblem with category/accent glow.
/// 5. Rich, modern metadata chips (Channel count, EPG active, Source type, Host).
/// 6. Streamlined interactive controls ("Browse" glass action, Quick copy, 3-dots menu).
/// 7. Responsive support for both List and Grid layouts.
class IptvPlaylistCard extends ConsumerWidget {
  final IptvPlaylist playlist;
  final bool isGrid;
  final int? index;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;

  const IptvPlaylistCard({
    super.key,
    required this.playlist,
    this.isGrid = false,
    this.index,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
  });

  Color _getEmblemColor(String name) {
    const colors = [
      Color(0xFFE58344), // Warm amber-orange
      Color(0xFFDE6251), // Coral red
      Color(0xFF3B82F6), // Royal Cerulean Blue
      Color(0xFF10B981), // Emerald Green
      Color(0xFF8B5CF6), // Purple Iris
      Color(0xFFF59E0B), // Solar Amber
      Color(0xFF06B6D4), // Cyan Teal
      Color(0xFFEC4899), // Neon Pink
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _getInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'P';
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _getSourceLabel(IptvSourceType type) {
    switch (type) {
      case IptvSourceType.m3uUrl:
        return 'M3U LINK';
      case IptvSourceType.m3uFile:
        return 'LOCAL FILE';
      case IptvSourceType.xtream:
        return 'XTREAM API';
      case IptvSourceType.stalker:
        return 'STALKER MAC';
      case IptvSourceType.directStream:
        return 'STREAM LINK';
    }
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  String _getHostDomain(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
    } catch (_) {}
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final clean = url.replaceFirst(RegExp(r'https?:\/\/'), '');
      final slash = clean.indexOf('/');
      return slash != -1 ? clean.substring(0, slash) : clean;
    }
    return 'Direct Stream';
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'edit':
        await IptvAddSourceDialog.show(context, existingPlaylist: playlist);
        break;

      case 'refresh':
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Syncing "${playlist.name}"...'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await ref
            .read(iptvPlaylistsProvider.notifier)
            .refreshPlaylist(playlist.id);
        break;

      case 'rename':
        final controller = TextEditingController(text: playlist.name);
        final themeMode = ref.read(activeThemeModeProvider);
        final accentColor = ref.read(activeAccentColorProvider);
        final newName = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: themeMode.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: themeMode.dividerColor),
            ),
            title: Text(
              'Rename Playlist',
              style: TextStyle(color: themeMode.onSurfaceColor, fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: themeMode.onSurfaceColor),
              decoration: InputDecoration(
                filled: true,
                fillColor: themeMode.cardColor,
                hintText: 'Enter new playlist name',
                hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: themeMode.dividerColor),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text('CANCEL', style: TextStyle(color: themeMode.onSurfaceMutedColor)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor.color,
                  foregroundColor: accentColor.onAccentColor,
                ),
                child: const Text('SAVE'),
              ),
            ],
          ),
        );

        if (newName != null && newName.isNotEmpty && newName != playlist.name) {
          final updated = playlist.copyWith(name: newName);
          await ref.read(iptvPlaylistsProvider.notifier).updatePlaylist(updated);
        }
        break;

      case 'copy_url':
        HapticFeedback.selectionClick();
        await Clipboard.setData(ClipboardData(text: playlist.url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Playlist URL copied to clipboard'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;

      case 'export_m3u':
        HapticFeedback.selectionClick();
        final m3uText = IptvService.buildM3uExportString([playlist]);
        await Clipboard.setData(ClipboardData(text: m3uText));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('M3U playlist copied (${playlist.channels.length} items)'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        break;

      case 'info':
        await IptvPlaylistInfoDialog.show(context, playlist);
        break;

      case 'epg':
        await IptvManageEpgSheet.show(context);
        break;

      case 'delete':
        HapticFeedback.heavyImpact();
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1B1C20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0x1FFFFFFF)),
            ),
            title: const Text(
              'Delete Playlist?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to remove "${playlist.name}"? This action cannot be undone.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GoPlayTheme.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('DELETE'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await ref
              .read(iptvPlaylistsProvider.notifier)
              .deletePlaylist(playlist.id);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final isDark = themeMode.isDark;

    final emblemColor = _getEmblemColor(playlist.name);
    final initials = _getInitials(playlist.name);
    final dateStr = _formatDate(playlist.lastSync ?? playlist.addedAt);
    final hasEpg = playlist.epgUrl != null && playlist.epgUrl!.trim().isNotEmpty;
    final sourceLabel = _getSourceLabel(playlist.sourceType);
    final domain = _getHostDomain(playlist.url);

    void onOpenPlaylist() {
      HapticFeedback.selectionClick();
      if (selectionMode) {
        onToggleSelect?.call();
      } else {
        IptvChannelBrowserSheet.show(context, playlist);
      }
    }

    if (isGrid) {
      return _buildGridCard(
        context: context,
        ref: ref,
        isDark: isDark,
        emblemColor: emblemColor,
        initials: initials,
        dateStr: dateStr,
        hasEpg: hasEpg,
        sourceLabel: sourceLabel,
        domain: domain,
        accentColor: accentColor,
        themeMode: themeMode,
        onOpen: onOpenPlaylist,
      );
    }

    return _buildListCard(
      context: context,
      ref: ref,
      isDark: isDark,
      emblemColor: emblemColor,
      initials: initials,
      dateStr: dateStr,
      hasEpg: hasEpg,
      sourceLabel: sourceLabel,
      domain: domain,
      accentColor: accentColor,
      themeMode: themeMode,
      onOpen: onOpenPlaylist,
    );
  }

  /// ─── Modern List Card (Horizontal Layout) ────────────────────────────────
  Widget _buildListCard({
    required BuildContext context,
    required WidgetRef ref,
    required bool isDark,
    required Color emblemColor,
    required String initials,
    required String dateStr,
    required bool hasEpg,
    required String sourceLabel,
    required String domain,
    required AppAccentColor accentColor,
    required AppThemeMode themeMode,
    required VoidCallback onOpen,
  }) {
    return CleanCard(
      borderRadius: 22.0,
      blurSigma: 20.0,
      elevation: isSelected ? 12.0 : 8.0,
      isSelected: selectionMode && isSelected,
      selectedBorderColor: accentColor.color,
      glowColor: selectionMode && isSelected ? accentColor.color : emblemColor.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Reorder Drag Handle or Multi-Select Checkbox ──
          if (selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _buildSelectionCheckbox(accentColor),
            )
          else if (index != null)
            ReorderableDragStartListener(
              index: index!,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IptvSvgIcon(
                  IptvSvgIcons.dragHandle,
                  color: isDark ? Colors.white38 : Colors.black38,
                  size: 18,
                ),
              ),
            ),

          // ── Radiant Liquid Glass Avatar Emblem ──
          _buildEmblem(emblemColor, initials, isDark),
          const SizedBox(width: 14),

          // ── Playlist Info & Metadata ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: Source Tag + EPG Tag
                Wrap(
                  spacing: 5,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Source Type Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        sourceLabel,
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 9.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    if (hasEpg)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accentColor.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: accentColor.color.withValues(alpha: 0.35),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: accentColor.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 3.5),
                            Text(
                              'EPG',
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 9.0,
                                fontWeight: FontWeight.w800,
                                color: accentColor.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),

                // Playlist Title
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),

                // Bottom Meta: Date, Channel Count, Domain
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$dateStr  •  ${playlist.channelCount} ch${domain.isNotEmpty && domain != 'Direct Stream' ? '  •  $domain' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── Right Action Hub ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick Copy Link Button
              _buildIconButton(
                icon: IptvSvgIcons.link,
                tooltip: 'Copy URL',
                isDark: isDark,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await Clipboard.setData(ClipboardData(text: playlist.url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Playlist URL copied to clipboard'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),

              // 3-dots Menu
              _buildPopupMenu(context, ref, themeMode, accentColor, isDark),
            ],
          ),
        ],
      ),
    );
  }

  /// ─── Modern Grid Card (Vertical Layout) ──────────────────────────────────
  Widget _buildGridCard({
    required BuildContext context,
    required WidgetRef ref,
    required bool isDark,
    required Color emblemColor,
    required String initials,
    required String dateStr,
    required bool hasEpg,
    required String sourceLabel,
    required String domain,
    required AppAccentColor accentColor,
    required AppThemeMode themeMode,
    required VoidCallback onOpen,
  }) {
    return CleanCard(
      borderRadius: 22.0,
      blurSigma: 20.0,
      elevation: isSelected ? 12.0 : 8.0,
      isSelected: selectionMode && isSelected,
      selectedBorderColor: accentColor.color,
      glowColor: emblemColor.withValues(alpha: 0.18),
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildEmblem(emblemColor, initials, isDark, size: 44),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasEpg)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: accentColor.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'EPG',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: accentColor.color,
                        ),
                      ),
                    ),
                  _buildPopupMenu(context, ref, themeMode, accentColor, isDark),
                ],
              ),
            ],
          ),
          const Spacer(),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${playlist.channelCount} Channels • $domain',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _buildBrowseButton(onOpen, accentColor, isDark, isExpanded: true),
          ),
        ],
      ),
    );
  }

  /// Radiant Liquid Glass Avatar Emblem
  Widget _buildEmblem(Color emblemColor, String initials, bool isDark, {double size = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.35),
        gradient: LinearGradient(
          begin: const Alignment(-0.8, -0.8),
          end: const Alignment(0.8, 0.8),
          colors: [
            emblemColor.withValues(alpha: 0.95),
            Color.lerp(emblemColor, Colors.black, isDark ? 0.35 : 0.15)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: emblemColor.withValues(alpha: 0.40),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Liquid Glass "Browse" Action Pill
  Widget _buildBrowseButton(
    VoidCallback onOpen,
    AppAccentColor accentColor,
    bool isDark, {
    bool isExpanded = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isExpanded ? 16 : 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IptvSvgIcon(
                IptvSvgIcons.playlistPlay,
                size: 14,
                color: accentColor.color,
              ),
              const SizedBox(width: 5),
              Text(
                'Browse',
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required String icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: IptvSvgIcon(
          icon,
          color: isDark ? Colors.white60 : Colors.black54,
          size: 16,
        ),
      ),
    );
  }

  Widget _buildSelectionCheckbox(AppAccentColor accentColor) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isSelected ? accentColor.color : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isSelected ? accentColor.color : Colors.white38,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 15,
            )
          : null,
    );
  }

  Widget _buildPopupMenu(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode themeMode,
    AppAccentColor accentColor,
    bool isDark,
  ) {
    return PopupMenuButton<String>(
      icon: IptvSvgIcon(
        IptvSvgIcons.moreVertical,
        color: isDark ? Colors.white60 : Colors.black54,
        size: 18,
      ),
      tooltip: 'Playlist Options',
      color: themeMode.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withAlpha(160),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      onSelected: (val) => _handleMenuAction(context, ref, val),
      itemBuilder: (ctx) => [
        _buildMenuItem(
          value: 'refresh',
          icon: IptvSvgIcons.refresh,
          title: 'Re-sync Channels',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'edit',
          icon: IptvSvgIcons.sliders,
          title: 'Edit Source',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'rename',
          icon: IptvSvgIcons.edit,
          title: 'Rename Playlist',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'copy_url',
          icon: IptvSvgIcons.copy,
          title: 'Copy Source URL',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'export_m3u',
          icon: IptvSvgIcons.download,
          title: 'Export M3U Playlist',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'epg',
          icon: IptvSvgIcons.epg,
          title: 'TV Guide / EPG',
          iconColor: accentColor.color,
          textColor: themeMode.onSurfaceColor,
        ),
        _buildMenuItem(
          value: 'info',
          icon: IptvSvgIcons.info,
          title: 'Playlist Info',
          iconColor: themeMode.onSurfaceColor.withAlpha(220),
          textColor: themeMode.onSurfaceColor,
        ),
        const PopupMenuDivider(height: 10),
        _buildMenuItem(
          value: 'delete',
          icon: IptvSvgIcons.delete,
          title: 'Delete Playlist',
          iconColor: GoPlayTheme.error,
          textColor: GoPlayTheme.error,
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required String icon,
    required String title,
    required Color iconColor,
    required Color textColor,
    double size = 16.5,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          IptvSvgIcon(icon, color: iconColor, size: size),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Backwards compatibility alias for `CleanLiquidGlassPainter`.
typedef IptvLiquidGlassPainter = CleanLiquidGlassPainter;
typedef IptvGlassBorderPainter = CleanLiquidGlassPainter;
