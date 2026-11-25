import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/theme_provider.dart';
import 'iptv_add_source_dialog.dart';
import 'iptv_home_dialogs.dart';
import 'iptv_svg_icon.dart';

/// "Add New Content" modal bottom sheet matching the decompiled APK (`BottomSheetProjectOption2`).
class IptvAddMenuSheet extends ConsumerWidget {
  const IptvAddMenuSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const IptvAddMenuSheet(),
    );
  }

  void _openSourceDialog(BuildContext context, IptvSourceType type) {
    Navigator.of(context).pop();
    IptvAddSourceDialog.show(context, initialType: type);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title: "Add New Content"
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              'Add New Content',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: themeMode.onSurfaceColor,
              ),
            ),
          ),

          // Menu Container with 6 APK options (including Add Teleguide EPG)
          Container(
            decoration: BoxDecoration(
              color: themeMode.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: themeMode.dividerColor, width: 1),
            ),
            child: Column(
              children: [
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.videoLink,
                  title: 'Video Link',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () => _openSourceDialog(context, IptvSourceType.directStream),
                  isFirst: true,
                ),
                _buildDivider(themeMode.dividerColor),
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.playlistPlay,
                  title: 'Playlist Link (M3U/JSON)',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () => _openSourceDialog(context, IptvSourceType.m3uUrl),
                ),
                _buildDivider(themeMode.dividerColor),
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.folderOpen,
                  title: 'Local Playlist (M3U/JSON)',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () => _openSourceDialog(context, IptvSourceType.m3uFile),
                ),
                _buildDivider(themeMode.dividerColor),
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.monitor,
                  title: 'Xtream Codes',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () => _openSourceDialog(context, IptvSourceType.xtream),
                ),
                _buildDivider(themeMode.dividerColor),
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.laptop,
                  title: 'STB / Stalker / MAC Portal',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () => _openSourceDialog(context, IptvSourceType.stalker),
                ),
                _buildDivider(themeMode.dividerColor),
                _buildMenuItem(
                  context,
                  svgIcon: IptvSvgIcons.epg,
                  title: 'Add Teleguide EPG (XML)',
                  iconColor: accentColor.color,
                  textColor: themeMode.onSurfaceColor,
                  chevronColor: themeMode.onSurfaceMutedColor,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final hostContext = navigator.context;
                    navigator.pop();
                    final added =
                        await IptvManageEpgSheet.showAddEpgDialog(hostContext);
                    if (added != null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            added.channelCount > 0
                                ? 'Saved EPG "${added.name}" (${added.channelCount} channels)'
                                : 'Saved EPG "${added.name}"',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    String? svgIcon,
    IconData? icon,
    required String title,
    required Color iconColor,
    required Color textColor,
    required Color chevronColor,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(14) : Radius.zero,
        bottom: isLast ? const Radius.circular(14) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (svgIcon != null)
              IptvSvgIcon(svgIcon, color: iconColor, size: 20)
            else if (icon != null)
              Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            IptvSvgIcon(
              IptvSvgIcons.chevronRight,
              color: chevronColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(Color color) {
    return Divider(
      height: 1,
      thickness: 1,
      color: color,
    );
  }
}
