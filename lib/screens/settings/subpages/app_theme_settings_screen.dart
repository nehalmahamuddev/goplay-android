import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../providers/theme_provider.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../widgets/setting_section_header.dart';

/// Full-screen settings page for selecting the app's theme palette.
class AppThemeSettingsScreen extends ConsumerWidget {
  const AppThemeSettingsScreen({super.key});

  void _resetToDefault(BuildContext context, WidgetRef ref) {
    ref.read(themeSettingsProvider.notifier).setThemeMode(AppThemeMode.dark);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App theme reset to Upstream Dark.'),
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
    final currentMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? currentMode.bottomNavColor;

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
              leading: TvFocusable(
                isCircle: true,
                excludeChildFocus: true,
                semanticLabel: 'Back',
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/settings/layout');
                  }
                },
                child: Center(
                  child: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
                ),
              ),
              title: Text(
                'App Theme',
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
                const SettingSectionHeader(title: 'Theme Palettes'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                  child: Text(
                    'Select a visual style tailored for OLED black levels, contrast, and eye comfort.',
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
                    children: AppThemeMode.values.map((mode) {
                      final isSelected = mode == currentMode;
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
                        child: TvFocusable(
                          excludeChildFocus: true,
                          borderRadius: BorderRadius.zero,
                          onTap: () {
                            ref.read(themeSettingsProvider.notifier).setThemeMode(mode);
                          },
                          child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Theme Swatch Preview
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: mode.surfaceColor,
                                      border: Border.all(
                                        color: mode.cardColor,
                                        width: 3.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          mode.displayName,
                                          style: TextStyle(
                                            fontFamily: GoPlayType.family,
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? cs.primary : cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          mode.subtitle,
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
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
                                    size: 22,
                                  ),
                                ],
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
