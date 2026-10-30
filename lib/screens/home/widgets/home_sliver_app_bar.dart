import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../../../widgets/app_overflow_menu.dart';

/// Collapsing Dark-Themed & Edge-to-Edge Adaptive App Bar for HomeScreen
class HomeSliverAppBar extends ConsumerWidget {
  const HomeSliverAppBar({super.key});

  /// Balanced header content height (excluding system status bar):
  /// 38dp wordmark row + 12dp breathing room + 48dp search pill = 98.0dp (flush with search pill bottom)
  static const double contentExpandedHeight = 98.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final brandWordmark = ref.watch(uiConfigProvider).navigationBranding.brandWordmark;

    // Flutter's SliverAppBar internally adds topPadding (statusBarHeight) to expandedHeight
    final double minHeight = kToolbarHeight + statusBarHeight;
    final double maxHeight = contentExpandedHeight + statusBarHeight;

    return SliverAppBar(
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

          return Container(
            color: cs.surface,
            child: Padding(
              padding: EdgeInsets.only(top: statusBarHeight),
              child: Stack(
                children: [
                  // Brand Wordmark (comfortable 12dp spacing from search pill when expanded, centered when pinned)
                  Positioned(
                    left: 16,
                    top: 0,
                    height: 38 + (18 * collapseRatio),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        brandWordmark,
                        style: GoPlayType.wordmark.copyWith(
                          color: GoPlayTheme.onSurface,
                          fontSize: GoPlayType.xl - ((GoPlayType.xl - GoPlayType.lg) * collapseRatio),
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),

                  // Collapsed Search Icon (appears smoothly when toolbar collapses past 50%)
                  if (collapseRatio >= 0.5)
                    Positioned(
                      right: 48,
                      top: 0,
                      height: kToolbarHeight,
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color: cs.onSurface,
                          ),
                          onPressed: () => context.push('/search'),
                        ),
                      ),
                    ),

                  // Overflow Menu (always accessible)
                  Positioned(
                    right: 8,
                    top: 0,
                    height: kToolbarHeight,
                    child: Center(
                      child: AppOverflowMenu(iconColor: cs.onSurface),
                    ),
                  ),

                  // Expanded Search Bar Pill (starts at y=50 for balanced 12dp top gap and 10dp bottom gap)
                  if (collapseRatio < 0.7)
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 50 - (collapseRatio * 50),
                      height: 48,
                      child: Opacity(
                        opacity: (1.0 - (collapseRatio / 0.6)).clamp(0.0, 1.0),
                        child: TvFocusable(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => context.push('/search'),
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF161616) : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Search channels, events...',
                                  style: TextStyle(
                                    fontFamily: GoPlayType.family,
                                    fontSize: 15,
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
            ),
          );
        },
      ),
    );
  }
}
