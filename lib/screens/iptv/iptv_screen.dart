import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../models/channel.dart';
import '../../models/iptv_playlist.dart';
import '../../providers/iptv_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/iptv_service.dart';
import 'widgets/iptv_add_menu_sheet.dart';
import 'widgets/iptv_category_sheets.dart';
import 'widgets/iptv_home_dialogs.dart';
import 'widgets/iptv_playlist_card.dart';
import 'widgets/iptv_svg_icon.dart';

/// Full IPTV Home Screen replicating the source APK's exact `fragment_playlist`
/// (`res/AT.xml`): compact header with 6 working APK tools, clickable Telegram
/// banner, multi-select mode with batch delete/export, cross-playlist channel
/// search, sort options, EPG TV guide hub, and squircle `+` FAB.
class IptvScreen extends ConsumerStatefulWidget {
  const IptvScreen({super.key});

  @override
  ConsumerState<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends ConsumerState<IptvScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String _filterQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openTelegramBanner(BuildContext context) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(AppConstants.telegramCommunityUrl);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      final themeMode = ref.read(activeThemeModeProvider);
      final accentColor = ref.read(activeAccentColorProvider);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: themeMode.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: themeMode.dividerColor),
          ),
          title: Text(
            'GoPlay Community',
            style: TextStyle(
              color: themeMode.onSurfaceColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          content: SelectableText(
            'Thank you for your support! Join our Telegram channel for updates, M3U/DRM tips, and new features:\n\n${AppConstants.telegramCommunityUrl}',
            style: TextStyle(color: themeMode.onSurfaceVariantColor, fontSize: 13, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: AppConstants.telegramCommunityUrl),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Telegram link copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: Text(
                'COPY LINK',
                style: TextStyle(color: accentColor.color),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.color,
                foregroundColor: accentColor.onAccentColor,
              ),
              child: const Text('CLOSE'),
            ),
          ],
        ),
      );
    }
  }

  void _toggleSelectionMode({List<IptvPlaylist>? allPlaylists}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_isSelectionMode) {
        _isSelectionMode = false;
        _selectedIds.clear();
      } else {
        _isSelectionMode = true;
        _selectedIds.clear();
      }
    });
  }

  void _toggleItemSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  Future<void> _deleteSelectedPlaylists(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
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
          'Delete $count Playlist${count == 1 ? '' : 's'}?',
          style: TextStyle(color: themeMode.onSurfaceColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to remove the $count selected playlist${count == 1 ? '' : 's'}? This action cannot be undone.',
          style: TextStyle(color: themeMode.onSurfaceVariantColor, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL', style: TextStyle(color: themeMode.onSurfaceMutedColor)),
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
      final idsToDelete = List<String>.from(_selectedIds);
      await ref.read(iptvPlaylistsProvider.notifier).deletePlaylists(idsToDelete);
      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _isSelectionMode = false;
        });
      }
    }
  }

  Future<void> _exportSelectedPlaylists(
    BuildContext context,
    List<IptvPlaylist> playlists,
  ) async {
    final selected = playlists.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.isEmpty) return;

    final m3uText = IptvService.buildM3uExportString(selected);
    await Clipboard.setData(ClipboardData(text: m3uText));
    final totalCh = selected.fold<int>(0, (sum, p) => sum + p.channelCount);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${selected.length} playlist(s) ($totalCh channels) to clipboard',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSortMenu(BuildContext context) {
    final themeMode = ref.read(activeThemeModeProvider);
    final accentColor = ref.read(activeAccentColorProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: themeMode.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final currentMode = sheetRef.watch(iptvHomeSortModeProvider);
          final bookmarkCount = sheetRef.watch(iptvBookmarksProvider).length;

          Widget sortTile({
            required String mode,
            required IconData icon,
            required String label,
          }) {
            final selected = currentMode == mode;
            return ListTile(
              dense: true,
              leading: Icon(
                icon,
                color: selected ? accentColor.color : themeMode.onSurfaceMutedColor,
              ),
              title: Text(
                label,
                style: TextStyle(
                  color: selected ? accentColor.color : themeMode.onSurfaceColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: accentColor.color)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(iptvHomeSortModeProvider.notifier).setSort(mode);
              },
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Sort by',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: themeMode.onSurfaceColor,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Tips: Long press and drag the dots icon to reorder items.',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12,
                        color: themeMode.onSurfaceMutedColor,
                      ),
                    ),
                  ),
                  sortTile(
                    mode: 'default',
                    icon: Icons.drag_indicator_rounded,
                    label: 'Sort by Custom Order',
                  ),
                  sortTile(
                    mode: 'newest',
                    icon: Icons.schedule_rounded,
                    label: 'Sort by Date (Newest first)',
                  ),
                  sortTile(
                    mode: 'oldest',
                    icon: Icons.history_rounded,
                    label: 'Sort by Date (Oldest first)',
                  ),
                  sortTile(
                    mode: 'asc',
                    icon: Icons.sort_by_alpha_rounded,
                    label: 'Sort by Name (A-Z)',
                  ),
                  sortTile(
                    mode: 'desc',
                    icon: Icons.sort_by_alpha_rounded,
                    label: 'Sort by Name (Z-A)',
                  ),
                  sortTile(
                    mode: 'count',
                    icon: Icons.format_list_numbered_rounded,
                    label: 'Sort by Channel Count (High-Low)',
                  ),
                  Divider(color: themeMode.dividerColor, height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.bookmark_outline_rounded,
                      color: accentColor.color,
                    ),
                    title: Text(
                      'Saved Channel Bookmarks ($bookmarkCount)',
                      style: TextStyle(
                        color: themeMode.onSurfaceColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: themeMode.onSurfaceMutedColor,
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<IptvPlaylist> _applySortAndFilter(
    List<IptvPlaylist> playlists,
    String sortMode,
  ) {
    final baseList = _filterQuery.isEmpty
        ? List<IptvPlaylist>.from(playlists)
        : playlists.where((p) {
            return p.name.toLowerCase().contains(_filterQuery) ||
                p.url.toLowerCase().contains(_filterQuery) ||
                p.sourceType.label.toLowerCase().contains(_filterQuery);
          }).toList();

    switch (sortMode) {
      case 'newest':
        baseList.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case 'oldest':
        baseList.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case 'asc':
        baseList.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'desc':
        baseList.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case 'count':
        baseList.sort((a, b) => b.channelCount.compareTo(a.channelCount));
        break;
    }
    return baseList;
  }

  Widget _buildHeaderIcon({
    String? svgIcon,
    IconData? icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color color = Colors.white,
    double size = 20,
  }) {
    return SizedBox(
      width: 34,
      height: 36,
      child: IconButton(
        tooltip: tooltip,
        icon: svgIcon != null
            ? IptvSvgIcon(svgIcon, color: color, size: size)
            : Icon(icon, color: color, size: size),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final playlistsAsync = ref.watch(iptvPlaylistsProvider);
    final playlists = playlistsAsync.value ?? const <IptvPlaylist>[];
    final sortMode = ref.watch(iptvHomeSortModeProvider);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: themeMode.surfaceColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          color: accentColor.color,
          backgroundColor: themeMode.surfaceContainerHigh,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            await ref.read(iptvPlaylistsProvider.notifier).syncAllPlaylists();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // Top Bar: Compact spacing so "IPTV." never squeezes into "IP..."
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isSelectionMode
                              ? '${_selectedIds.length} Selected'
                              : 'IPTV.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),

                      // 1. Search Icon
                      _buildHeaderIcon(
                        tooltip: _isSearching ? 'Close search' : 'Search playlists & channels',
                        svgIcon: _isSearching
                            ? IptvSvgIcons.close
                            : IptvSvgIcons.search,
                        onPressed: () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) {
                              _searchController.clear();
                              _filterQuery = '';
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 2),

                      // 2. Help / Onboarding Guide (?)
                      _buildHeaderIcon(
                        tooltip: 'IPTV Guide',
                        svgIcon: IptvSvgIcons.help,
                        onPressed: () => IptvGuideSheet.show(context),
                      ),
                      const SizedBox(width: 2),

                      // 3. Multi-Select Mode (APK selectModeImageViewPlaylist)
                      _buildHeaderIcon(
                        tooltip: _isSelectionMode
                            ? 'Exit multi-select'
                            : 'Select playlists',
                        svgIcon: _isSelectionMode
                            ? IptvSvgIcons.checkSquare
                            : IptvSvgIcons.microchip,
                        color: _isSelectionMode
                            ? accentColor.color
                            : Colors.white,
                        onPressed: () =>
                            _toggleSelectionMode(allPlaylists: playlists),
                      ),
                      const SizedBox(width: 2),

                      // 4. Sort / Filter (APK filterImageViewPlaylist)
                      _buildHeaderIcon(
                        tooltip: 'Sort & Filter',
                        svgIcon: IptvSvgIcons.sliders,
                        onPressed: () => _showSortMenu(context),
                      ),
                      const SizedBox(width: 2),

                      // 5. Manage TV Guide / EPG (APK epgImageViewPlaylist)
                      _buildHeaderIcon(
                        tooltip: 'Manage TV Guide',
                        svgIcon: IptvSvgIcons.tv,
                        onPressed: () => IptvManageEpgSheet.show(context),
                      ),
                      const SizedBox(width: 2),

                      // 6. Settings Gear (APK moreImageViewPlaylist)
                      _buildHeaderIcon(
                        tooltip: 'IPTV Settings',
                        svgIcon: IptvSvgIcons.settings,
                        onPressed: () => _showSettingsSheet(context),
                      ),
                    ],
                  ),
                ),
              ),

              // Expandable Search Bar (searches both playlists and channels across playlists)
              if (_isSearching)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (val) {
                        setState(() => _filterQuery = val.trim().toLowerCase());
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search playlists or channel names...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: IptvSvgIcon(
                            IptvSvgIcons.search,
                            size: 16,
                            color: themeMode.onSurfaceMutedColor,
                          ),
                        ),
                        suffixIcon: _filterQuery.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear filter',
                                icon: IptvSvgIcon(
                                  IptvSvgIcons.close,
                                  size: 16,
                                  color: themeMode.onSurfaceMutedColor,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _filterQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: themeMode.cardColor,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: themeMode.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: accentColor.color,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Clickable Telegram Support Announcement Banner (matching APK sideNoteCardViewPlaylist)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _openTelegramBanner(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: themeMode.cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2AABEE),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: IptvSvgIcon(
                                  IptvSvgIcons.telegram,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Thank you for your support! More innovative featu...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  fontSize: 12.5,
                                  color: themeMode.onSurfaceColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Multi-Select Controls Bar
              if (_isSelectionMode && playlists.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: themeMode.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: themeMode.dividerColor),
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                if (_selectedIds.length == playlists.length) {
                                  _selectedIds.clear();
                                } else {
                                  _selectedIds
                                    ..clear()
                                    ..addAll(playlists.map((p) => p.id));
                                }
                              });
                            },
                            icon: Icon(
                              _selectedIds.length == playlists.length
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                              size: 16,
                              color: accentColor.color,
                            ),
                            label: Text(
                              _selectedIds.length == playlists.length
                                  ? 'Clear All'
                                  : 'Select All',
                              style: TextStyle(
                                color: accentColor.color,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _toggleSelectionMode(),
                            child: Text(
                              'DONE',
                              style: TextStyle(
                                color: themeMode.onSurfaceColor,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Playlist Cards List + Cross-Playlist Channel Search Results
              playlistsAsync.when(
                data: (loadedPlaylists) {
                  if (loadedPlaylists.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(context),
                    );
                  }

                  final filtered =
                      _applySortAndFilter(loadedPlaylists, sortMode);
                  final channelHits = _filterQuery.isNotEmpty
                      ? searchChannelsAcrossPlaylists(
                          loadedPlaylists,
                          _filterQuery,
                        )
                      : const <({IptvPlaylist playlist, Channel channel})>[];

                  if (filtered.isEmpty && channelHits.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 40,
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.search_off_rounded,
                              color: Colors.white38,
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Not found: "$_filterQuery"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final allowReorder =
                      !_isSelectionMode && _filterQuery.isEmpty && sortMode == 'default';

                  if (allowReorder) {
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      sliver: SliverReorderableList(
                        itemCount: filtered.length,
                        onReorder: (oldIndex, newIndex) {
                          HapticFeedback.lightImpact();
                          ref
                              .read(iptvPlaylistsProvider.notifier)
                              .reorderPlaylists(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          return Padding(
                            key: ValueKey(p.id),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: IptvPlaylistCard(
                              playlist: p,
                              isGrid: false,
                              index: index,
                            ),
                          );
                        },
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildListDelegate([
                      if (filtered.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Column(
                            children: [
                              for (final p in filtered)
                                Padding(
                                  key: ValueKey(p.id),
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: IptvPlaylistCard(
                                    playlist: p,
                                    isGrid: false,
                                    selectionMode: _isSelectionMode,
                                    isSelected: _selectedIds.contains(p.id),
                                    onToggleSelect: () =>
                                        _toggleItemSelection(p.id),
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Cross-Playlist Channel Search Results (`MultiSearchActivity` parity)
                      if (channelHits.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Matching Channels (${channelHits.length})',
                                  style: const TextStyle(
                                    fontFamily: GoPlayType.family,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFA8C7FA),
                                  ),
                                ),
                              ),
                              for (final hit in channelHits)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: themeMode.cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: themeMode.dividerColor,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: themeMode.surfaceContainerHigh,
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        color: accentColor.color,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      hit.channel.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${hit.playlist.name}  •  ${hit.channel.category ?? "General"}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceMutedColor,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    onTap: () => launchIptvChannelPlayback(
                                      context,
                                      ref,
                                      channel: hit.channel,
                                      scopeChannels: hit.playlist.channels,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ]),
                  );
                },
                loading: () => SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: accentColor.color),
                  ),
                ),
                error: (err, _) => SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Error loading playlists: $err',
                      style: const TextStyle(color: GoPlayTheme.error),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SizedBox(height: 92 + bottomPadding),
              ),
            ],
          ),
        ),
      ),

      // Multi-select Delete/Export FABs or Normal (+) Squircle FAB
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 16 + bottomPadding),
        child: _isSelectionMode
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'iptv_export_selected',
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _exportSelectedPlaylists(context, playlists),
                    backgroundColor: themeMode.surfaceContainerHigh,
                    foregroundColor: accentColor.color,
                    icon: IptvSvgIcon(IptvSvgIcons.share, size: 19, color: accentColor.color),
                    label: Text(
                      'EXPORT (${_selectedIds.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'iptv_delete_selected',
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _deleteSelectedPlaylists(context),
                    backgroundColor: _selectedIds.isEmpty
                        ? themeMode.cardColor
                        : GoPlayTheme.error,
                    foregroundColor: Colors.white,
                    icon: const IptvSvgIcon(IptvSvgIcons.delete, size: 19, color: Colors.white),
                    label: Text(
                      'DELETE (${_selectedIds.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.color,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      IptvAddMenuSheet.show(context);
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: Center(
                      child: IptvSvgIcon(
                        IptvSvgIcons.plus,
                        color: accentColor.onAccentColor,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: themeMode.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: themeMode.dividerColor, width: 1.5),
            ),
            child: Center(
              child: IptvSvgIcon(
                IptvSvgIcons.tvPlay,
                color: accentColor.color,
                size: 36,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'IPTV DRM Stream Player',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: themeMode.onSurfaceColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'To get started, tap the (+) button and enter your video or playlist URL.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 12.5,
              color: themeMode.onSurfaceMutedColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Responsive Wrap avoids RenderFlex overflow on narrow screens (e.g. 320dp-360dp).
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(iptvPlaylistsProvider.notifier).importSamplePlaylist();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor.color,
                  side: BorderSide(color: themeMode.dividerColor),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('LOAD SAMPLE PLAYLIST'),
              ),
              ElevatedButton(
                onPressed: () => IptvAddMenuSheet.show(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor.color,
                  foregroundColor: accentColor.onAccentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'ADD NEW CONTENT',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showImportBackupDialog(BuildContext context) async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportBackupDialog(),
    );

    if (raw != null && raw.isNotEmpty && context.mounted) {
      final count =
          await ref.read(iptvPlaylistsProvider.notifier).importBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'Imported $count playlist(s) from backup'
                  : 'No valid playlists found in JSON backup',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showSettingsSheet(BuildContext context) {
    final themeMode = ref.read(activeThemeModeProvider);
    final accentColor = ref.read(activeAccentColorProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: themeMode.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final settings = sheetRef.watch(iptvSettingsProvider);
          final bookmarkCount = sheetRef.watch(iptvBookmarksProvider).length;
          final epgCount = sheetRef.watch(iptvSavedEpgSourcesProvider).length;

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(
                      'Sort Categories by Channel Count',
                      style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Orders group tabs largest-first after "All"',
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12),
                    ),
                    value: settings.sortCategoriesByCount,
                    activeThumbColor: accentColor.color,
                    onChanged: (val) => ref
                        .read(iptvSettingsProvider.notifier)
                        .toggleSortCategoriesByCount(val),
                  ),
                  SwitchListTile(
                    title: Text(
                      'Hide "All" Category Tab',
                      style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Jump straight to the first group inside playlists',
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12),
                    ),
                    value: settings.hideAllCategory,
                    activeThumbColor: accentColor.color,
                    onChanged: (val) => ref
                        .read(iptvSettingsProvider.notifier)
                        .toggleHideAllCategory(val),
                  ),
                  SwitchListTile(
                    title: Text(
                      '24-Hour Smart Playlist Cache',
                      style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Instant 0ms load when synced within the last 24h',
                      style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12),
                    ),
                    value: settings.cacheEnabled,
                    activeThumbColor: accentColor.color,
                    onChanged: (val) => ref
                        .read(iptvSettingsProvider.notifier)
                        .toggleCacheEnabled(val),
                  ),
                  Divider(color: themeMode.dividerColor, height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.bookmark_outline_rounded,
                      color: accentColor.color,
                    ),
                    title: Text(
                      'Saved Bookmarks ($bookmarkCount)',
                      style: TextStyle(color: themeMode.onSurfaceColor),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
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
                  ListTile(
                    leading: Icon(
                      Icons.dvr_rounded,
                      color: accentColor.color,
                    ),
                    title: Text(
                      'Manage TV Guides ($epgCount)',
                      style: TextStyle(color: themeMode.onSurfaceColor),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      IptvManageEpgSheet.show(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.cleaning_services_outlined,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Clear Cached EPG Guide Data',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref.read(iptvEpgProvider.notifier).clearAll();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cleared cached EPG programme data'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.upload_file_rounded,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Export Playlists Backup',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final jsonStr = ref
                          .read(iptvPlaylistsProvider.notifier)
                          .exportBackupJson();
                      await Clipboard.setData(ClipboardData(text: jsonStr));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backup JSON copied to clipboard!'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.download_for_offline_rounded,
                      color: Colors.white70,
                    ),
                    title: const Text(
                      'Import JSON Backup',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showImportBackupDialog(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFA8C7FA),
                    ),
                    title: const Text(
                      'Load Free Demo Streams',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(iptvPlaylistsProvider.notifier)
                          .importSamplePlaylist();
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_sweep_rounded,
                      color: GoPlayTheme.error,
                    ),
                    title: const Text(
                      'Clear All Playlists',
                      style: TextStyle(color: GoPlayTheme.error),
                    ),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await ref.read(iptvPlaylistsProvider.notifier).clearAll();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

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
    return AlertDialog(
      backgroundColor: const Color(0xFF16171B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF282B36)),
      ),
      title: const Text(
        'Import JSON Backup',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Paste exported IPTV backup JSON array...',
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF0C0D10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF282B36)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA8C7FA),
            foregroundColor: const Color(0xFF0A1C36),
          ),
          child: const Text('IMPORT'),
        ),
      ],
    );
  }
}
