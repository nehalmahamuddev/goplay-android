import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../widgets/search_pill_card.dart';

const String _kProfileSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><title>profile</title><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12.16 10.87c-.1-.01-.22-.01-.33 0a4.42 4.42 0 0 1-4.27-4.43C7.56 3.99 9.54 2 12 2a4.435 4.435 0 0 1 .16 8.87m-5 3.69c-2.42 1.62-2.42 4.26 0 5.87c2.75 1.84 7.26 1.84 10.01 0c2.42-1.62 2.42-4.26 0-5.87c-2.74-1.83-7.25-1.83-10.01 0"/></svg>
''';

/// Collapsing Dark-Themed & Edge-to-Edge Adaptive App Bar for HomeScreen
class HomeSliverAppBar extends ConsumerWidget {
  const HomeSliverAppBar({super.key});

  /// Balanced header content height (excluding system status bar):
  /// 38dp wordmark row + 12dp breathing room + 40dp search pill = 90.0dp (flush with search pill bottom)
  static const double contentExpandedHeight = 90.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brandWordmark = ref.watch(uiConfigProvider).navigationBranding.brandWordmark;
    final themeSettings = ref.watch(themeSettingsProvider);
    final topPadding = MediaQuery.paddingOf(context).top;

    // Resolve header background color to match bottom nav bar surface color
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ??
        themeSettings.bottomNavColor;

    final double minHeight = kToolbarHeight + topPadding;
    final double maxHeight = contentExpandedHeight + topPadding;

    return SliverAppBar(
      primary: true,
      expandedHeight: contentExpandedHeight,
      floating: false,
      pinned: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final double appBarHeight = constraints.biggest.height;

          // Normalized collapse ratio: 0.0 (fully expanded) to 1.0 (fully collapsed)
          final double collapseRatio = ((maxHeight - appBarHeight) / (maxHeight - minHeight)).clamp(0.0, 1.0);

          // Smoothly interpolate background color from canvas surface to nav menu surface
          final effectiveBgColor = Color.lerp(cs.surface, headerBg, collapseRatio)!;

          return Container(
            color: effectiveBgColor,
            child: Stack(
              children: [
                // Brand Custom Title (custom vector wordmark with built-in play mark)
                Positioned(
                  left: 10,
                  top: topPadding,
                  height: 38 + (18 * collapseRatio),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SvgPicture.asset(
                      'assets/images/title.svg',
                      height: 20,
                      fit: BoxFit.contain,
                      semanticsLabel: brandWordmark,
                    ),
                  ),
                ),

                // Collapsed Search Icon (appears smoothly when toolbar collapses past 50%)
                if (collapseRatio >= 0.5)
                  Positioned(
                    right: 86,
                    top: topPadding,
                    height: kToolbarHeight,
                    child: Center(
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => context.push('/search'),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          child: SvgPicture.string(
                            kUpstreamSearchSvg,
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                              cs.onSurface,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Cast Button
                Positioned(
                  right: 46,
                  top: topPadding,
                  height: kToolbarHeight,
                  child: Center(
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'No Cast devices found',
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.cast_rounded,
                          color: cs.onSurface,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),

                // Profile / Settings Button
                Positioned(
                  right: 6,
                  top: topPadding,
                  height: kToolbarHeight,
                  child: Center(
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/settings');
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        child: SvgPicture.string(
                          _kProfileSvg,
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            cs.onSurface,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Expanded Search Bar Pill (starts at y=50 below topPadding for balanced 12dp top gap and 10dp bottom gap)
                if (collapseRatio < 0.7)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: topPadding + 50 - (collapseRatio * 50),
                    height: 40,
                    child: Opacity(
                      opacity: (1.0 - (collapseRatio / 0.6)).clamp(0.0, 1.0),
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => context.push('/search'),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF161616) : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              SvgPicture.string(
                                kUpstreamSearchSvg,
                                width: 24,
                                height: 24,
                                colorFilter: ColorFilter.mode(
                                  cs.onSurfaceVariant.withValues(alpha: 0.7),
                                  BlendMode.srcIn,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Search channels, events...',
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w400,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
