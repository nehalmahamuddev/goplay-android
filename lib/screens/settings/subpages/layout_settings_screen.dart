import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';
import '../widgets/theme_choice_dialog.dart';

/// Layout and Theme Settings Screen matching Upstream's 'Layout' subpage.
class LayoutSettingsScreen extends ConsumerWidget {
  const LayoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeState = ref.watch(themeSettingsProvider);
    final themeNotifier = ref.read(themeSettingsProvider.notifier);
    final themeMode = themeState.themeMode;
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final showTrending = ref.watch(showTrendingTabProvider);
    final uiConfig = ref.watch(uiConfigProvider);
    final tabConfig = uiConfig.channelsTab;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
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
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
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
                  ),
                ),
                title: 'Primary color',
                subtitle: themeState.accentColor.displayName,
                onTap: () => AccentColorChoiceDialog.show(
                  context,
                  currentAccent: themeState.accentColor,
                  onSelect: (accent) => themeNotifier.setAccentColor(accent),
                ),
              ),
              SettingTile(
                icon: Icons.palette_outlined,
                title: 'App theme',
                subtitle: themeMode.displayName,
                onTap: () => ThemeModeChoiceDialog.show(
                  context,
                  currentMode: themeMode,
                  onSelect: (mode) => themeNotifier.setThemeMode(mode),
                ),
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
                        SnackBar(
                          content: const Text('Theme reset to cloud default!'),
                          backgroundColor: const Color(0xFF1E1E1E),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
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
                icon: Icons.bookmark_outline_rounded,
                title: 'Show Favorite Tab Counts',
                subtitle: 'Display count badges on channel category tabs',
                value: tabConfig.showTabCounts,
                onChanged: (val) async {
                  final updated = uiConfig.copyWith(
                    channelsTab: tabConfig.copyWith(showTabCounts: val),
                  );
                  await ref.read(cacheServiceProvider).saveLocalUiConfig(updated);
                  ref.invalidate(uiConfigProvider);
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
                  await ref.read(cacheServiceProvider).saveLocalUiConfig(updated);
                  ref.invalidate(uiConfigProvider);
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
                  await ref.read(cacheServiceProvider).saveLocalUiConfig(updated);
                  ref.invalidate(uiConfigProvider);
                },
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

