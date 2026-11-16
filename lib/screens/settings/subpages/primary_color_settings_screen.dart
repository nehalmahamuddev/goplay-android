import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';

/// Full-screen settings page for selecting the app's Primary Accent Color.
class PrimaryColorSettingsScreen extends ConsumerWidget {
  const PrimaryColorSettingsScreen({super.key});

  void _resetToDefault(BuildContext context, WidgetRef ref) {
    ref.read(themeSettingsProvider.notifier).setAccentColor(AppAccentColor.white);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Primary accent color reset to default.'),
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

    final currentAccent = ref.watch(activeAccentColorProvider);

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
                'Primary Accent Color',
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
                const SettingSectionHeader(title: 'Color Presets'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                  child: Text(
                    'Choose a highlight color for buttons, active navigation indicators, and accents.',
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
                    children: AppAccentColor.values.map((accent) {
                      final isSelected = accent == currentAccent;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF181818) : const Color(0xFF141414),
                          border: Border(
                            left: BorderSide(
                              color: isSelected ? accent.color : Colors.transparent,
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
                              ref.read(themeSettingsProvider.notifier).setAccentColor(accent);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Color Swatch
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: accent.color,
                                      border: accent == AppAccentColor.white
                                          ? Border.all(color: Colors.white38, width: 1.5)
                                          : null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.color.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      accent.displayName,
                                      style: TextStyle(
                                        fontFamily: GoPlayType.family,
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected ? accent.color : cs.onSurface,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: isSelected
                                        ? accent.color
                                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
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
