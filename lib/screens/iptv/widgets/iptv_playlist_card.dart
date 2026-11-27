import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/iptv_service.dart';
import 'iptv_add_source_dialog.dart';
import 'iptv_channel_browser_sheet.dart';
import 'iptv_home_dialogs.dart';
import 'iptv_svg_icon.dart';

/// Card component representing an imported IPTV playlist (drag/select handle,
/// playlist title, date & channel count metadata, source URL, and options menu).
class IptvPlaylistCard extends ConsumerWidget {
  final IptvPlaylist playlist;
  final bool isGrid;
  final int? index;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  const IptvPlaylistCard({
    super.key,
    required this.playlist,
    this.isGrid = false,
    this.index,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  Color _getAvatarColor(String name) {
    const colors = [
      Color(0xFFE58344),
      Color(0xFFDE6251),
      Color(0xFF4A90E2),
      Color(0xFF5B9E77),
      Color(0xFF9B51E0),
      Color(0xFFE6A23C),
      Color(0xFF3AAFA9),
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
    return clean.substring(0, 1).toUpperCase();
  }

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
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
        final themeMode = ref.read(activeThemeModeProvider);
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: themeMode.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: themeMode.dividerColor),
            ),
            title: Text(
              'Delete Playlist?',
              style: TextStyle(
                color: themeMode.onSurfaceColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Are you sure you want to remove "${playlist.name}"? This action cannot be undone.',
              style: TextStyle(
                color: themeMode.onSurfaceVariantColor,
                fontSize: 13,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'CANCEL',
                  style: TextStyle(color: themeMode.onSurfaceMutedColor),
                ),
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
    final avatarColor = _getAvatarColor(playlist.name);
    final initials = _getInitials(playlist.name);
    final dateStr = _formatDate(playlist.lastSync ?? playlist.addedAt);

    final hasEpg = playlist.epgUrl != null && playlist.epgUrl!.trim().isNotEmpty;
    final hasUrl = playlist.url.trim().isNotEmpty;
    final selectedHighlight = selectionMode && isSelected;
    final cardBgColor = selectedHighlight
        ? accentColor.color.withValues(alpha: 0.14)
        : themeMode.cardColor;
    final borderColor = selectedHighlight
        ? accentColor.color
        : themeMode.dividerColor;
    const cardRadius = BorderRadius.all(Radius.circular(12));

    return Material(
      color: cardBgColor,
      shape: const RoundedRectangleBorder(borderRadius: cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          if (selectionMode) {
            onToggleSelect?.call();
          } else {
            IptvChannelBrowserSheet.show(context, playlist);
          }
        },
        onLongPress: selectionMode ? null : onLongPress,
        borderRadius: cardRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Selection checkbox in Multi-Select mode, otherwise 48dp touch-friendly drag handle
              if (selectionMode)
                SizedBox(
                  width: 44,
                  height: 48,
                  child: Center(
                    child: IptvSvgIcon(
                      isSelected
                          ? IptvSvgIcons.checkSquare
                          : IptvSvgIcons.dragHandle,
                      color: isSelected
                          ? accentColor.color
                          : themeMode.onSurfaceMutedColor,
                      size: 22,
                    ),
                  ),
                )
              else if (index != null)
                ReorderableDragStartListener(
                  index: index!,
                  child: Semantics(
                    label: 'Reorder ${playlist.name}',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: SizedBox(
                        width: 44,
                        height: 48,
                        child: ColoredBox(
                          color: Colors.transparent,
                          child: Center(
                            child: IptvSvgIcon(
                              IptvSvgIcons.dragHandle,
                              color: themeMode.onSurfaceMutedColor.withAlpha(140),
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 44,
                  height: 48,
                  child: Center(
                    child: IptvSvgIcon(
                      IptvSvgIcons.dragHandle,
                      color: themeMode.onSurfaceMutedColor.withAlpha(140),
                      size: 22,
                    ),
                  ),
                ),
              const SizedBox(width: 4),

              // Circle Avatar with Initials
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: GoPlayType.md,
                    fontWeight: FontWeight.w700,
                    height: GoPlayType.leadingFlat,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title, Date/Channel Count, and URL Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Playlist Name
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: GoPlayType.md,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: GoPlayType.leadingSnug,
                        color: themeMode.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Date & channel count (e.g. "24/11/2026 • 76 ch") + optional EPG tag
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$dateStr • ${playlist.channelCount} ch',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              fontSize: GoPlayType.sm,
                              fontWeight: FontWeight.w500,
                              height: GoPlayType.leadingFlat,
                              color: themeMode.onSurfaceMutedColor,
                            ),
                          ),
                        ),
                        if (hasEpg) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.color.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'EPG',
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: GoPlayType.xs,
                                fontWeight: FontWeight.w700,
                                letterSpacing: GoPlayType.trackingMeta,
                                height: GoPlayType.leadingFlat,
                                color: accentColor.color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasUrl) ...[
                      const SizedBox(height: 3),

                      // URL / Stream link
                      Text(
                        playlist.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: GoPlayType.xs,
                          fontWeight: FontWeight.w400,
                          height: GoPlayType.leadingSnug,
                          color: themeMode.onSurfaceMutedColor
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Right Action: 3-dots popup menu (48dp touch target)
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: themeMode.dividerColor,
                  splashColor: accentColor.color.withValues(alpha: 0.12),
                  highlightColor: accentColor.color.withValues(alpha: 0.08),
                ),
                child: PopupMenuButton<String>(
                  icon: IptvSvgIcon(
                    IptvSvgIcons.moreVertical,
                    color: themeMode.onSurfaceMutedColor,
                    size: 22,
                  ),
                  tooltip: 'Playlist Options',
                  color: themeMode.cardColor,
                  surfaceTintColor: Colors.transparent,
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  position: PopupMenuPosition.under,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  menuPadding: const EdgeInsets.symmetric(vertical: 6),
                  onSelected: (val) => _handleMenuAction(context, ref, val),
                  itemBuilder: (ctx) => [
                    _buildMenuItem(
                      value: 'refresh',
                      icon: IptvSvgIcons.refresh,
                      title: 'Re-sync Channels',
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
                      textColor: themeMode.onSurfaceColor,
                    ),
                    _buildMenuItem(
                      value: 'edit',
                      icon: IptvSvgIcons.sliders,
                      title: 'Edit Source',
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
                      textColor: themeMode.onSurfaceColor,
                    ),
                    _buildMenuItem(
                      value: 'rename',
                      icon: IptvSvgIcons.edit,
                      title: 'Rename Playlist',
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
                      textColor: themeMode.onSurfaceColor,
                    ),
                    _buildMenuItem(
                      value: 'copy_url',
                      icon: IptvSvgIcons.copy,
                      title: 'Copy Source URL',
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
                      textColor: themeMode.onSurfaceColor,
                    ),
                    _buildMenuItem(
                      value: 'export_m3u',
                      icon: IptvSvgIcons.download,
                      title: 'Export M3U Playlist',
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
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
                      iconColor: themeMode.onSurfaceColor.withValues(alpha: 0.85),
                      textColor: themeMode.onSurfaceColor,
                    ),
                    const PopupMenuDivider(height: 12),
                    _buildMenuItem(
                      value: 'delete',
                      icon: IptvSvgIcons.delete,
                      title: 'Delete Playlist',
                      iconColor: GoPlayTheme.error,
                      textColor: GoPlayTheme.error,
                    ),
                  ],
                ),
              ),
        ],
      ),
    ),
    ),
  ),
);
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required String icon,
    required String title,
    required Color iconColor,
    required Color textColor,
    double size = 18,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IptvSvgIcon(icon, color: iconColor, size: size),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontFamily: GoPlayType.family,
              color: textColor,
              fontSize: GoPlayType.base,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

