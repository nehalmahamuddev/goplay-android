import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/typography.dart';
import '../models/nav_destination.dart';
import '../providers/app_providers.dart';
import 'tv_focus_wrapper.dart';

/// Reusable main bottom navigation bar used in ShellScreen and mobile PlayerScreen.
class MainBottomNavBar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final ValueChanged<NavDestination>? onDestinationTap;
  final List<FocusNode>? focusNodes;

  const MainBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onDestinationTap,
    this.focusNodes,
  });

  bool _isDestinationSelected(
    NavDestination destination,
    int currentIndex,
    String selectedCategory,
    bool hasFavoritesTab,
  ) {
    if (destination == NavDestination.favorites) {
      return currentIndex == 2 && selectedCategory == 'favorite';
    }
    if (destination == NavDestination.channels) {
      if (hasFavoritesTab) {
        return currentIndex == 2 && selectedCategory != 'favorite';
      }
      return currentIndex == 2;
    }
    return currentIndex == destination.branchIndex;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final navBarBg = theme.bottomNavigationBarTheme.backgroundColor ?? cs.surfaceContainerHighest;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final tabs = ref.watch(customNavTabsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final hasFavoritesTab = tabs.any((t) => t == NavDestination.favorites);

    return RepaintBoundary(
      child: Container(
        height: 64 + bottomPadding,
        decoration: BoxDecoration(
          color: navBarBg,
        ),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              MainNavItem(
                focusNode: (focusNodes != null && i < focusNodes!.length) ? focusNodes![i] : null,
                svgAsset: tabs[i].svgAsset,
                selectedSvgAsset: tabs[i].selectedSvgAsset,
                icon: tabs[i].icon,
                selectedIcon: tabs[i].selectedIcon,
                label: tabs[i].label,
                isSelected: _isDestinationSelected(
                  tabs[i],
                  currentIndex,
                  selectedCategory,
                  hasFavoritesTab,
                ),
                onTap: () {
                  if (tabs[i] == NavDestination.favorites) {
                    ref.read(selectedCategoryProvider.notifier).select('favorite');
                  } else if (tabs[i] == NavDestination.channels) {
                    if (ref.read(selectedCategoryProvider) == 'favorite') {
                      ref.read(selectedCategoryProvider.notifier).select('all');
                    }
                  }
                  ref.read(lastActiveNavTabProvider.notifier).setActiveTab(tabs[i].id);

                  if (onDestinationTap != null) {
                    onDestinationTap!(tabs[i]);
                  } else {
                    onTap(tabs[i].branchIndex);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MainNavItem extends StatelessWidget {
  final IconData? icon;
  final IconData? selectedIcon;
  final String? svgAsset;
  final String? selectedSvgAsset;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const MainNavItem({
    super.key,
    this.icon,
    this.selectedIcon,
    this.svgAsset,
    this.selectedSvgAsset,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.focusNode,
  }) : assert(icon != null || svgAsset != null, 'Either icon or svgAsset must be provided');

  static final _borderRadius = BorderRadius.circular(10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    const defaultColor = Colors.white;
    final itemColor = isSelected ? activeColor : defaultColor;
    final currentSvg = isSelected ? (selectedSvgAsset ?? svgAsset) : svgAsset;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: TvFocusable(
          focusNode: focusNode,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: _borderRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (currentSvg != null)
                  SvgPicture.asset(
                    currentSvg,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      itemColor,
                      BlendMode.srcIn,
                    ),
                  )
                else
                  Icon(
                    isSelected ? (selectedIcon ?? icon) : icon,
                    color: itemColor,
                    size: 22,
                  ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: GoPlayType.inter(
                        color: itemColor,
                        fontSize: GoPlayType.xs,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        height: GoPlayType.leadingFlat,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
