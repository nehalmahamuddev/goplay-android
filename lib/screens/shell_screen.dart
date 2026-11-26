import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../models/nav_destination.dart';
import '../core/theme.dart';
import '../core/typography.dart';
import '../widgets/tv_focus_wrapper.dart';
import '../widgets/main_bottom_nav_bar.dart';
import '../widgets/category_m3u_auto_sync_observer.dart';

/// Main shell screen with bottom navigation bar.
///
/// Performance notes:
/// - MediaQuery accessed once, results passed down (avoids multiple rebuild subscriptions).
/// - Bottom nav wrapped in RepaintBoundary (isolated from page scroll repaints).
/// - Mobile nav items use lightweight InkWell with splash + haptic (no TvFocusable overhead).
/// - TV rail items keep TvFocusable for D-Pad focus visuals.
class ShellScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ShellScreen({super.key, required this.navigationShell});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  late final List<FocusNode> _navFocusNodes;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _navFocusNodes = List.generate(
      6,
      (i) => FocusNode(debugLabel: 'NavMenu_$i'),
    );
  }

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _handleDestinationTap(NavDestination dest) {
    if (dest == NavDestination.favorites) {
      ref.read(selectedCategoryProvider.notifier).select('favorite');
    } else if (dest == NavDestination.channels) {
      if (ref.read(selectedCategoryProvider) == 'favorite') {
        ref.read(selectedCategoryProvider.notifier).select('all');
      }
    }
    ref.read(lastActiveNavTabProvider.notifier).setActiveTab(dest.id);
    _goBranch(dest.branchIndex);
  }

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final navBarBg = theme.bottomNavigationBarTheme.backgroundColor ?? cs.surfaceContainerHighest;
    final index = widget.navigationShell.currentIndex;

    final tabs = ref.watch(customNavTabsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final hasFavoritesTab = tabs.any((t) => t == NavDestination.favorites);

    // Scoped MediaQuery reads. `MediaQuery.of(context)` subscribes to every
    // field — including `viewInsets` — so it rebuilt the whole shell (and every
    // nav item) each time the keyboard opened.
    final size = MediaQuery.sizeOf(context);
    // TV & Landscape detection: TV devices, TV boxes, tablets, or any landscape screen (width > height)
    // use the Left Side Navigation Rail.
    // Mobile phones in portrait mode (width <= height) use the Bottom Navigation Bar.
    final isLandscape = size.width > size.height;
    final isTv = MediaQuery.navigationModeOf(context) == NavigationMode.directional ||
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final isDesktop = isLandscape || isTv;

    Widget content;

    if (isDesktop) {
      content = Scaffold(
        backgroundColor: cs.surface,
        body: Row(
          children: [
            // Side Navigation Rail — D-Pad friendly
            RepaintBoundary(
              child: Container(
                width: 72,
                decoration: BoxDecoration(
                  color: navBarBg,
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < tabs.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _RailNavItem(
                          focusNode: (i < _navFocusNodes.length) ? _navFocusNodes[i] : null,
                          svgAsset: tabs[i].svgAsset,
                          selectedSvgAsset: tabs[i].selectedSvgAsset,
                          icon: tabs[i].icon,
                          selectedIcon: tabs[i].selectedIcon,
                          label: tabs[i].label,
                          isSelected: _isDestinationSelected(
                            tabs[i],
                            index,
                            selectedCategory,
                            hasFavoritesTab,
                          ),
                          onTap: () => _handleDestinationTap(tabs[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Main Content Area
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    } else {
      content = Scaffold(
        backgroundColor: cs.surface,
        extendBody: false,
        body: widget.navigationShell,
        bottomNavigationBar: MainBottomNavBar(
          currentIndex: index,
          onTap: _goBranch,
          onDestinationTap: _handleDestinationTap,
          focusNodes: _navFocusNodes,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (index != 0) {
          // Any non-home tab (Categories, Channels, Upcoming) smoothly backs to Home tab
          _goBranch(0);
        } else {
          // Home tab requires double-back to exit within 2 seconds
          final now = DateTime.now();
          if (_lastBackPressTime == null ||
              now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
            _lastBackPressTime = now;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.exit_to_app_rounded,
                      color: GoPlayTheme.primary,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Press back again to exit',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 1400),
                behavior: SnackBarBehavior.floating,
                width: 230,
                backgroundColor: const Color(0xF21E1E22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
              ),
            );
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.digit1 ||
              key == LogicalKeyboardKey.numpad1) {
            _goBranch(0);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit2 ||
                     key == LogicalKeyboardKey.numpad2) {
            _goBranch(1);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit3 ||
                     key == LogicalKeyboardKey.numpad3) {
            _goBranch(2);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit4 ||
                     key == LogicalKeyboardKey.numpad4) {
            _goBranch(3);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit5 ||
                     key == LogicalKeyboardKey.numpad5) {
            _goBranch(5);
            return KeyEventResult.handled;
          }

          // TV Remote D-Pad LEFT: Move left on page first.
          // ONLY jump to Navigation Menu when at the left-most edge of the page!
          if (key == LogicalKeyboardKey.arrowLeft) {
            final primary = FocusManager.instance.primaryFocus;
            if (primary != null && !_navFocusNodes.contains(primary)) {
              if (primary.context != null) {
                final moved = FocusTraversalGroup.of(primary.context!).inDirection(
                  primary,
                  TraversalDirection.left,
                );
                if (moved) {
                  return KeyEventResult.handled;
                }
              }
              _navFocusNodes[widget.navigationShell.currentIndex].requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
        child: CategoryM3uAutoSyncObserver(child: content),
      ),
    );
  }
}


// ─── TV Side Rail Nav Item ────────────────────────────────────────
// Keeps TvFocusable for D-Pad focus ring on TV/desktop.

class _RailNavItem extends StatelessWidget {
  final IconData? icon;
  final IconData? selectedIcon;
  final String? svgAsset;
  final String? selectedSvgAsset;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _RailNavItem({
    this.icon,
    this.selectedIcon,
    this.svgAsset,
    this.selectedSvgAsset,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.focusNode,
  }) : assert(icon != null || svgAsset != null, 'Either icon or svgAsset must be provided');

  static final _borderRadius = BorderRadius.circular(12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final defaultColor = Colors.white;
    final itemColor = isSelected ? activeColor : defaultColor;
    final currentSvg = isSelected ? (selectedSvgAsset ?? svgAsset) : svgAsset;

    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: _borderRadius,
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: _borderRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentSvg != null)
              SvgPicture.asset(
                currentSvg,
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  itemColor,
                  BlendMode.srcIn,
                ),
              )
            else
              Icon(
                isSelected ? (selectedIcon ?? icon) : icon,
                color: itemColor,
                size: 24,
              ),
            const SizedBox(height: 4),
            FittedBox(
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
          ],
        ),
      ),
    );
  }
}
