import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/typography.dart';
import 'widgets/account_info_sheet.dart';
import 'widgets/setting_tile.dart';

/// Searchable item definition for deep preference search.
class _PreferenceSearchItem {
  final String title;
  final String category;
  final String route;
  final IconData icon;
  final List<String> keywords;

  const _PreferenceSearchItem({
    required this.title,
    required this.category,
    required this.route,
    required this.icon,
    required this.keywords,
  });

  bool matches(String query) {
    final lower = query.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (title.toLowerCase().contains(lower)) return true;
    if (category.toLowerCase().contains(lower)) return true;
    return keywords.any((k) => k.toLowerCase().contains(lower));
  }
}

/// Upstream Main Settings Screen Hub.
///
/// Implements the exact Upstream hierarchy:
/// - Profile / Account Header with 50dp circular avatar and interactive sheet.
/// - Pill-shaped deep preference search bar with real-time filtering.
/// - 6 Category Tiles (General, Player, Layout, Updates and Backup, Data & Cloud Sync, Accounts and Security).
/// - Exact Build Stamp Footer ("2.2.2 • commit-hash • build-date") with tap-to-copy.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();

  static const List<_PreferenceSearchItem> _searchIndex = [
    _PreferenceSearchItem(
      title: 'Primary color',
      category: 'Layout',
      route: '/settings/layout',
      icon: Icons.palette_outlined,
      keywords: ['accent', 'color', 'blue', 'lime', 'volt', 'theme', 'looks'],
    ),
    _PreferenceSearchItem(
      title: 'App theme',
      category: 'Layout',
      route: '/settings/layout',
      icon: Icons.dark_mode_outlined,
      keywords: ['dark', 'amoled', 'black', 'pure black', 'dracula', 'cyber lime', 'theme'],
    ),
    _PreferenceSearchItem(
      title: 'Show Trending Tab',
      category: 'Layout',
      route: '/settings/layout',
      icon: Icons.trending_up_rounded,
      keywords: ['trending', 'tabs', 'channels', 'filter'],
    ),
    _PreferenceSearchItem(
      title: 'Show Quality Badge',
      category: 'Layout',
      route: '/settings/layout',
      icon: Icons.high_quality_rounded,
      keywords: ['resolution', 'hd', 'fhd', '4k', 'badges', 'cards'],
    ),
    _PreferenceSearchItem(
      title: 'Hardware Acceleration',
      category: 'Player',
      route: '/settings/player',
      icon: Icons.memory_rounded,
      keywords: ['hw', 'gpu', 'video', 'decoding', 'performance', 'playback'],
    ),
    _PreferenceSearchItem(
      title: 'Auto-play Stream on Open',
      category: 'Player',
      route: '/settings/player',
      icon: Icons.play_circle_outline_rounded,
      keywords: ['autoplay', 'start', 'live', 'player'],
    ),
    _PreferenceSearchItem(
      title: 'Background Audio Playback',
      category: 'Player',
      route: '/settings/player',
      icon: Icons.headphones_outlined,
      keywords: ['audio', 'background', 'screen off', 'radio'],
    ),
    _PreferenceSearchItem(
      title: 'Buffer Profile',
      category: 'Player',
      route: '/settings/player',
      icon: Icons.speed_rounded,
      keywords: ['buffer', 'fast load', 'balanced', 'stability', 'latency'],
    ),
    _PreferenceSearchItem(
      title: 'Default Aspect Ratio',
      category: 'Player',
      route: '/settings/player',
      icon: Icons.aspect_ratio_rounded,
      keywords: ['aspect', '16:9', 'fit', 'stretch', 'zoom', 'scaling'],
    ),
    _PreferenceSearchItem(
      title: 'Check for Update',
      category: 'Updates and Backup',
      route: '/settings/updates',
      icon: Icons.system_update_alt_rounded,
      keywords: ['version', 'update', 'ota', 'download', 'release', 'new version'],
    ),
    _PreferenceSearchItem(
      title: 'Back up data',
      category: 'Updates and Backup',
      route: '/settings/updates',
      icon: Icons.archive_outlined,
      keywords: ['backup', 'export', 'favorites', 'bookmarks', 'save'],
    ),
    _PreferenceSearchItem(
      title: 'Restore data from backup',
      category: 'Updates and Backup',
      route: '/settings/updates',
      icon: Icons.restore_rounded,
      keywords: ['restore', 'import', 'load', 'favorites'],
    ),
    _PreferenceSearchItem(
      title: 'Force Sync Now',
      category: 'Data & Cloud Sync',
      route: '/settings/sync',
      icon: Icons.sync_rounded,
      keywords: ['sync', 'cloud', 'refresh', 'channels', 'events', 'categories'],
    ),
    _PreferenceSearchItem(
      title: 'Clear Cache',
      category: 'Data & Cloud Sync',
      route: '/settings/sync',
      icon: Icons.delete_outline_rounded,
      keywords: ['clear cache', 'storage', 'clean', 'images', 'logos'],
    ),
    _PreferenceSearchItem(
      title: 'Community Telegram & Discord',
      category: 'General',
      route: '/settings/general',
      icon: Icons.send_rounded,
      keywords: ['telegram', 'discord', 'chat', 'community', 'help', 'support'],
    ),
    _PreferenceSearchItem(
      title: 'Client Device ID',
      category: 'Accounts and Security',
      route: '/settings/account',
      icon: Icons.fingerprint_rounded,
      keywords: ['device', 'id', 'account', 'security', 'profile', 'token'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String _getFormattedBuildDate() {
    final now = DateTime.now();
    return DateFormat('MMMM d, y h:mm:ss a').format(now);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isSearching = _searchQuery.isNotEmpty;
    final searchResults = isSearching
        ? _searchIndex.where((item) => item.matches(_searchQuery)).toList()
        : const <_PreferenceSearchItem>[];

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),

                    // ─── 1. Profile / Account Header (Screenshot 1) ───
                  InkWell(
                    onTap: () => AccountInfoSheet.show(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          // Blue Swirl Avatar (matching Screenshot 1)
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [
                                  Color(0xFF00B4D8),
                                  Color(0xFF0077B6),
                                  Color(0xFF03045E),
                                ],
                                center: Alignment(-0.2, -0.2),
                                radius: 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0077B6).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.stream_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Default',
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Settings',
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ─── 2. Pill-Shaped Search Bar (Screenshot 1) ───
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.cardTheme.color ?? theme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _searchFocusNode.hasFocus
                            ? cs.primary.withValues(alpha: 0.6)
                            : (theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08)),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            cursorColor: cs.primary,
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              hintStyle: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 15,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: cs.onSurfaceVariant,
                              size: 18,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                            },
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ─── 3. Search Results or Main Category List ───
          if (isSearching)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (searchResults.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(
                        child: Text(
                          'No settings match "$_searchQuery"',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            color: cs.onSurfaceVariant,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }
                  final item = searchResults[index];
                  return SettingTile(
                    icon: item.icon,
                    title: item.title,
                    subtitle: item.category,
                    trailing: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    onTap: () {
                      context.push(item.route);
                    },
                  );
                },
                childCount: searchResults.isEmpty ? 1 : searchResults.length,
              ),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                // Tile 1: General
                SettingTile(
                  icon: Icons.build_rounded,
                  title: 'General',
                  subtitle: 'Language, Downloads, ISP Bypasses, Links',
                  onTap: () => context.push('/settings/general'),
                ),

                // Tile 2: Player
                SettingTile(
                  icon: Icons.play_arrow_rounded,
                  title: 'Player',
                  subtitle: 'Subtitles, Player features, Gestures, Layout, Cache',
                  onTap: () => context.push('/settings/player'),
                ),

                // Tile 3: Layout
                SettingTile(
                  icon: Icons.format_paint_rounded,
                  title: 'Layout',
                  subtitle: 'Looks, Features, Poster, Toggle UI elements on poster',
                  onTap: () => context.push('/settings/layout'),
                ),

                // Tile 4: Updates and Backup
                SettingTile(
                  icon: Icons.file_download_outlined,
                  title: 'Updates and Backup',
                  subtitle: 'App updates, Backup, Extensions, Actions',
                  onTap: () => context.push('/settings/updates'),
                ),

                // Tile 5: Data & Cloud Sync
                SettingTile(
                  icon: Icons.cloud_sync_rounded,
                  title: 'Data & Cloud Sync',
                  subtitle: 'Sync frequency, Force sync, Clear cache, Reset UI',
                  onTap: () => context.push('/settings/sync'),
                ),

                // Tile 6: Accounts and Security
                SettingTile(
                  icon: Icons.shield_outlined,
                  title: 'Accounts and Security',
                  subtitle: 'Accounts, Security',
                  onTap: () => context.push('/settings/account'),
                ),

                const SizedBox(height: 28),

                // ─── 4. Build Stamp Footer (Screenshot 1) ───
                InkWell(
                  onTap: () {
                    final stamp = '${AppConstants.appVersion}  •  e30f65d  •  ${_getFormattedBuildDate()}';
                    Clipboard.setData(ClipboardData(text: stamp));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Build info copied to clipboard!'),
                        backgroundColor: const Color(0xFF1E1E1E),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    child: Center(
                      child: Text(
                        '${AppConstants.appVersion}   •   e30f65d   •   ${_getFormattedBuildDate()}',
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
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
