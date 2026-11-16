import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/typography.dart';
import '../providers/app_providers.dart';
import 'tv_focus_wrapper.dart';

/// Reusable main bottom navigation bar used in ShellScreen and mobile PlayerScreen.
class MainBottomNavBar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FocusNode>? focusNodes;

  const MainBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.focusNodes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final navBarBg = theme.bottomNavigationBarTheme.backgroundColor ?? cs.surfaceContainerHighest;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final enabledTabs = ref.watch(uiConfigProvider).navigationBranding.enabledTabs;

    return RepaintBoundary(
      child: Container(
        height: 64 + bottomPadding,
        decoration: BoxDecoration(
          color: navBarBg,
        ),
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Row(
          children: [
            MainNavItem(
              focusNode: (focusNodes != null && focusNodes!.isNotEmpty) ? focusNodes![0] : null,
              svgAsset: 'assets/images/home.svg',
              selectedSvgAsset: 'assets/images/home_filled.svg',
              label: 'Home',
              isSelected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
            if (enabledTabs.contains('categories'))
              MainNavItem(
                focusNode: (focusNodes != null && focusNodes!.length > 1) ? focusNodes![1] : null,
                icon: Icons.grid_view_outlined,
                selectedIcon: Icons.grid_view_rounded,
                label: 'Categories',
                isSelected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
            if (enabledTabs.contains('channels'))
              MainNavItem(
                focusNode: (focusNodes != null && focusNodes!.length > 2) ? focusNodes![2] : null,
                svgAsset: 'assets/images/channels.svg',
                selectedSvgAsset: 'assets/images/channels_filled.svg',
                label: 'Channels',
                isSelected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
            if (enabledTabs.contains('upcoming') || enabledTabs.contains('events'))
              MainNavItem(
                focusNode: (focusNodes != null && focusNodes!.length > 3) ? focusNodes![3] : null,
                svgAsset: 'assets/images/events.svg',
                selectedSvgAsset: 'assets/images/events_filled.svg',
                label: 'Events',
                isSelected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
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
