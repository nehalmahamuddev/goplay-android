import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';

/// Full-screen settings page for selecting the default startup screen.
class LaunchScreenSettingsScreen extends ConsumerWidget {
  const LaunchScreenSettingsScreen({super.key});

  static const List<(String, String, String, IconData)> options = [
    ('home', 'Home', 'Open directly to the home screen', Icons.home_rounded),
    ('channels', 'Channels', 'Browse all live streaming channels', Icons.live_tv_rounded),
    ('favorites', 'Favorites', 'Jump straight to your favorited channels', Icons.favorite_rounded),
    ('categories', 'Categories', 'Explore channels sorted by category', Icons.grid_view_rounded),
    ('events', 'Events', 'View upcoming sports and live event schedules', Icons.event_rounded),
    ('settings', 'Settings', 'Quick access to app preferences', Icons.settings_rounded),
    ('last_used', 'Last used screen', 'Resume right where you left off', Icons.history_rounded),
  ];

  void _resetToDefault(BuildContext context, WidgetRef ref) {
    ref.read(defaultLaunchPageProvider.notifier).setLaunchPage('home');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Default launch screen reset to Home.'),
        backgroundColor: Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final currentLaunchPage = ref.watch(defaultLaunchPageProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/settings/layout');
          }
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Pinned App Bar
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
                    context.go('/settings/layout');
                  }
                },
              ),
              title: Text(
                'Default Launch Screen',
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => _resetToDefault(context, ref),
                  icon: Icon(Icons.restart_alt_rounded, size: 18, color: cs.primary),
                  label: Text(
                    'Reset',
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),

            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 12),
                const SettingSectionHeader(title: 'Startup Destination'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                  child: Text(
                    'Choose which screen opens automatically whenever the app is launched.',
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: options.map((opt) {
                      final isSelected = opt.$1 == currentLaunchPage;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF181818) : const Color(0xFF141414),
                          border: Border(
                            left: BorderSide(
                              color: isSelected ? cs.primary : Colors.transparent,
                              width: 3,
                            ),
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: isSelected ? 0.05 : 0.03),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Colors.white.withValues(alpha: isSelected ? 0.05 : 0.03),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: isSelected ? 0.05 : 0.03),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.zero,
                            onTap: () {
                              ref.read(defaultLaunchPageProvider.notifier).setLaunchPage(opt.$1);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Leading Icon
                                  SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Center(
                                      child: Icon(
                                        opt.$4,
                                        size: 24,
                                        color: isSelected
                                            ? cs.primary
                                            : cs.onSurfaceVariant.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          opt.$2,
                                          style: TextStyle(
                                            fontFamily: GoPlayType.family,
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? cs.primary : cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          opt.$3,
                                          style: TextStyle(
                                            fontFamily: GoPlayType.family,
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant.withValues(alpha: 0.35),
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
