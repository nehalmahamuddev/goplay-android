import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../skeletons/home_skeletons.dart';

/// Minimal Sport Category Filter Chips for home screen fixture filtering
class HomeSportCategoryFilterChips extends ConsumerWidget {
  const HomeSportCategoryFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sportsAsync = ref.watch(sortedSportCategoriesProvider);
    final selectedSport = ref.watch(selectedSportFilterProvider);
    final uiConfig = ref.watch(uiConfigProvider);

    final cs = Theme.of(context).colorScheme;
    final hasOverride = uiConfig.componentStyles.categoryChips.useCustomOverride;
    final activeBg = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipActiveBg(isHome: true))
        : cs.primary;
    final inactiveBg = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipInactiveBg(isHome: true))
        : Theme.of(context).cardColor;
    final activeTextColor = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipActiveTextColor(isHome: true))
        : cs.onPrimary;
    final inactiveTextColor = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipInactiveTextColor(isHome: true))
        : cs.onSurface;
    final chipRadius = uiConfig.resolveCategoryChipRadius(isHome: true);

    return sportsAsync.when(
      data: (sportsList) {
        return SizedBox(
          height: 32,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            scrollDirection: Axis.horizontal,
            addRepaintBoundaries: false,
            addAutomaticKeepAlives: false,
            itemCount: sportsList.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final sport = sportsList[index];
              final isSelected = selectedSport.toLowerCase() == sport.toLowerCase();

              return TvFocusable(
                borderRadius: BorderRadius.circular(chipRadius),
                onTap: () {
                  ref.read(selectedSportFilterProvider.notifier).select(sport);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? activeBg : inactiveBg,
                    borderRadius: BorderRadius.circular(chipRadius),
                  ),
                  child: Center(
                    child: Text(
                      sport,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: GoPlayType.sm,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? activeTextColor : inactiveTextColor,
                        height: GoPlayType.leadingSnug,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const ChipsSkeleton(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

