import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/tv_provider.dart';
import '../../../services/tv_service.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Layout and Theme Settings Screen matching Upstream's 'Layout' subpage.
class LayoutSettingsScreen extends ConsumerWidget {
  const LayoutSettingsScreen({super.key});

  String _tvModeLabel(String override) {
    switch (override) {
      case 'on':
        return 'Always On (Force TV Layout & D-Pad Focus)';
      case 'off':
        return 'Always Off (Mobile / Touch Mode)';
      case 'auto':
      default:
        return TvDeviceInfo.instance.nativeIsTv
            ? 'Auto (Detected: Android TV)'
            : 'Auto (Detected: Mobile / Tablet)';
    }
  }

  void _showTvModeDialog(BuildContext context, WidgetRef ref, String current) {
    final cs = Theme.of(context).colorScheme;
    const options = [
      (value: 'auto', label: 'Auto (Recommended)', desc: 'Detects Android TV, Leanback & remotes automatically'),
      (value: 'on', label: 'Always On', desc: 'Forces TV Rail, D-Pad focus rings & overscan on any box'),
      (value: 'off', label: 'Always Off', desc: 'Uses standard touch/tablet behavior'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
        title: Text(
          'Android TV Mode',
          style: TextStyle(
            fontFamily: GoPlayType.family,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final selected = opt.value == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TvFocusable(
                autoFocus: selected,
                excludeChildFocus: true,
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  ref.read(tvModeOverrideProvider.notifier).setOverride(opt.value);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.label,
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 14.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? cs.primary : cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              opt.desc,
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_rounded, color: cs.primary, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final themeMode = themeState.themeMode;
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final showTrending = ref.watch(showTrendingTabProvider);
    final showLiveTabCounter = ref.watch(showLiveTabCounterProvider);
    final showSportCategoryIcons = ref.watch(showSportCategoryIconsProvider);
    final uiConfig = ref.watch(uiConfigProvider);
    final tabConfig = uiConfig.channelsTab;
    final customTabs = ref.watch(customNavTabsProvider);
    final defaultLaunchPage = ref.watch(defaultLaunchPageProvider);
    final tvModeOverride = ref.watch(tvModeOverrideProvider);
    final tvOverscanEnabled = ref.watch(tvOverscanEnabledProvider);

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
            // Pinned Upstream-styled App Bar
            SliverAppBar(
              pinned: true,
              floating: false,
              backgroundColor: headerBg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              leading: TvFocusable(
                isCircle: true,
                excludeChildFocus: true,
                semanticLabel: 'Back',
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/settings');
                  }
                },
                child: Center(
                  child: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
                ),
              ),
              title: Text(
                'Layout',
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
              // ─── Looks Section ───
              const SettingSectionHeader(title: 'Looks'),
              SettingTile(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: themeState.accentColor.color,
                    border: themeState.accentColor == AppAccentColor.white
                        ? Border.all(color: Colors.white38, width: 1.5)
                        : null,
                  ),
                ),
                title: 'Primary color',
                subtitle: themeState.accentColor.displayName,
                onTap: () => context.go('/settings/layout/primary-color'),
              ),
              SettingTile(
                icon: Icons.palette_outlined,
                title: 'App theme',
                subtitle: themeMode.displayName,
                onTap: () => context.go('/settings/layout/app-theme'),
              ),
              if (themeState.isUsingCustomTheme)
                SettingTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset theme to cloud default',
                  subtitle: 'Restore appearance configured in the dashboard',
                  onTap: () async {
                    await themeNotifier.resetToCloudDefault();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Theme reset to cloud default!'),
                          backgroundColor: Color(0xFF1E1E1E),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                      );
                    }
                  },
                ),

              const SizedBox(height: 12),

              // ─── Navigation & Startup Section ───
              const SettingSectionHeader(title: 'Navigation & Startup'),
              SettingTile(
                icon: Icons.launch_rounded,
                title: 'Default launch screen',
                subtitle: _getLaunchPageLabel(defaultLaunchPage),
                onTap: () => context.go('/settings/layout/launch-screen'),
              ),
              SettingTile(
                icon: Icons.view_column_rounded,
                title: 'Customize navigation tabs',
                subtitle: '${customTabs.length} tabs enabled (3-5 allowed)',
                onTap: () => context.go('/settings/layout/navigation'),
              ),

              const SizedBox(height: 12),

              // ─── Android TV & Display Section ───
              const SettingSectionHeader(title: 'Android TV & Display'),
              SettingTile(
                icon: Icons.tv_rounded,
                title: 'Android TV Mode',
                subtitle: _tvModeLabel(tvModeOverride),
                onTap: () => _showTvModeDialog(context, ref, tvModeOverride),
              ),
              SettingSwitchTile(
                icon: Icons.fit_screen_rounded,
                title: 'TV Overscan Safe Margin',
                subtitle: 'Adds edge padding on TVs to prevent cropping near bezels',
                value: tvOverscanEnabled,
                onChanged: (val) {
                  ref.read(tvOverscanEnabledProvider.notifier).setEnabled(val);
                },
              ),

              const SizedBox(height: 12),

              // ─── Features Section ───
              const SettingSectionHeader(title: 'Features'),
              SettingSwitchTile(
                icon: Icons.trending_up_rounded,
                title: 'Show Trending Tab',
                subtitle: 'Display real-time dynamic trending streams tab in Channels',
                value: showTrending,
                onChanged: (val) {
                  ref.read(showTrendingTabProvider.notifier).toggle(val);
                },
              ),
              SettingSwitchTile(
                icon: Icons.numbers_rounded,
                title: 'Show Live Tab Counter',
                subtitle: 'Display active match count on the Live tab in Events',
                value: showLiveTabCounter,
                onChanged: (val) {
                  ref.read(showLiveTabCounterProvider.notifier).toggle(val);
                },
              ),
              SettingSwitchTile(
                icon: Icons.sports_rounded,
                title: 'Sport Category Icons',
                subtitle: 'Display sport icons inside category filter pills in Events',
                value: showSportCategoryIcons,
                onChanged: (val) {
                  ref.read(showSportCategoryIconsProvider.notifier).toggle(val);
                },
              ),
              SettingSwitchTile(
                icon: Icons.bookmark_outline_rounded,
                title: 'Show Favorite Tab Counts',
                subtitle: 'Display count badges on channel category tabs',
                value: tabConfig.showTabCounts,
                onChanged: (val) async {
                  final updated = uiConfig.copyWith(
                    channelsTab: tabConfig.copyWith(showTabCounts: val),
                  );
                  await ref.read(catalogRepositoryProvider).saveUiConfig(updated);
                },
              ),
              SettingSwitchTile(
                icon: Icons.category_outlined,
                title: 'Category Tab Icons',
                subtitle: 'Display category logos inside channel filter tabs',
                value: tabConfig.showTabIcons,
                onChanged: (val) async {
                  final updated = uiConfig.copyWith(
                    channelsTab: tabConfig.copyWith(showTabIcons: val),
                  );
                  await ref.read(catalogRepositoryProvider).saveUiConfig(updated);
                },
              ),
              SettingSwitchTile(
                icon: Icons.high_quality_rounded,
                title: 'Show Quality Badge',
                subtitle: 'Display stream resolution badges (HD, FHD, 4K) on cards',
                value: tabConfig.showQualityBadge,
                onChanged: (val) async {
                  final updated = uiConfig.copyWith(
                    channelsTab: tabConfig.copyWith(showQualityBadge: val),
                  );
                  await ref.read(catalogRepositoryProvider).saveUiConfig(updated);
                },
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    ),
  );
  }

  String _getLaunchPageLabel(String page) {
    switch (page) {
      case 'channels':
        return 'Channels';
      case 'favorites':
        return 'Favorites';
      case 'categories':
        return 'Categories';
      case 'events':
      case 'upcoming':
        return 'Events';
      case 'settings':
        return 'Settings';
      case 'last_used':
        return 'Last used screen';
      case 'home':
      default:
        return 'Home';
    }
  }
}

