import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/typography.dart';
import '../../../models/nav_destination.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../widgets/setting_section_header.dart';

/// Full-screen settings page for customizing bottom navigation tabs and order.
class NavigationTabsSettingsScreen extends ConsumerWidget {
  const NavigationTabsSettingsScreen({super.key});

  Widget _buildTabIcon(NavDestination dest, Color color, {double size = 24}) {
    if (dest.svgAsset != null) {
      return SvgPicture.asset(
        dest.svgAsset!,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(dest.icon ?? Icons.circle, size: size, color: color);
  }

  void _onReorder(
    BuildContext context,
    WidgetRef ref,
    List<NavDestination> currentTabs,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final updated = List<NavDestination>.from(currentTabs);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    ref.read(customNavTabsProvider.notifier).setTabs(updated);
  }

  void _removeTab(
    BuildContext context,
    WidgetRef ref,
    List<NavDestination> currentTabs,
    NavDestination destination,
  ) {
    if (currentTabs.length <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('At least 3 tabs must remain active in the navigation bar.'),
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final updated = List<NavDestination>.from(currentTabs)..remove(destination);
    ref.read(customNavTabsProvider.notifier).setTabs(updated);
  }

  void _addTab(
    BuildContext context,
    WidgetRef ref,
    List<NavDestination> currentTabs,
    NavDestination destination,
  ) {
    if (currentTabs.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('A maximum of 5 tabs can be placed in the navigation bar.'),
          backgroundColor: const Color(0xFF1E1E1E),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final updated = List<NavDestination>.from(currentTabs)..add(destination);
    ref.read(customNavTabsProvider.notifier).setTabs(updated);
  }

  void _resetToDefault(BuildContext context, WidgetRef ref) {
    ref.read(customNavTabsProvider.notifier).resetToDefault();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Navigation tabs restored to default.'),
        backgroundColor: const Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final activeTabs = ref.watch(customNavTabsProvider);
    final inactiveTabs = NavDestination.values.where((d) => !activeTabs.contains(d)).toList();

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
            // Pinned App Bar matching other Settings pages
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
                'Navigation Tabs',
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              actions: [
                // Clean action: Reset to default (no 5/5 badge)
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

                // ─── Active Tabs Section ───
                const SettingSectionHeader(title: 'Active Tabs'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                  child: Text(
                    'Hold and drag any card to reorder your navigation bar. Changes save automatically.',
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
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: Colors.transparent,
                        elevation: 4,
                        borderRadius: BorderRadius.zero,
                        child: child,
                      );
                    },
                    itemCount: activeTabs.length,
                    onReorder: (oldIndex, newIndex) => _onReorder(
                      context,
                      ref,
                      activeTabs,
                      oldIndex,
                      newIndex,
                    ),
                    itemBuilder: (context, index) {
                      final tab = activeTabs[index];
                      return Container(
                        key: ValueKey(tab.id),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF181818),
                          border: Border(
                            left: BorderSide(color: cs.primary, width: 3),
                            top: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
                            right: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
                            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: Center(
                                child: _buildTabIcon(tab, cs.primary, size: 24),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tab.label,
                                    style: TextStyle(
                                      fontFamily: GoPlayType.family,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        'Slot ${index + 1}',
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: cs.primary,
                                        ),
                                      ),
                                      Text(
                                        ' • ${tab.route}',
                                        style: TextStyle(
                                          fontFamily: GoPlayType.family,
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Remove button
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline_rounded,
                                color: activeTabs.length > 3
                                    ? Colors.redAccent.withValues(alpha: 0.85)
                                    : cs.onSurface.withValues(alpha: 0.2),
                                size: 22,
                              ),
                              tooltip: activeTabs.length > 3 ? 'Remove tab' : 'Minimum 3 tabs required',
                              onPressed: () => _removeTab(context, ref, activeTabs, tab),
                            ),
                            // Drag handle
                            ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // ─── Available Tabs Section ───
                if (inactiveTabs.isNotEmpty) ...[
                  const SettingSectionHeader(title: 'Available Tabs'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                    child: Text(
                      'Tap the plus button to add an item to your navigation bar.',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 13,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: inactiveTabs.map((tab) {
                        final canAdd = activeTabs.length < 5;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            border: Border(
                              left: BorderSide(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.25),
                                width: 3,
                              ),
                              top: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 1),
                              right: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 1),
                              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: Center(
                                  child: _buildTabIcon(
                                    tab,
                                    cs.onSurfaceVariant.withValues(alpha: 0.6),
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tab.label,
                                      style: TextStyle(
                                        fontFamily: GoPlayType.family,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurface.withValues(alpha: 0.8),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tab.route,
                                      style: TextStyle(
                                        fontFamily: GoPlayType.family,
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: canAdd ? cs.primary : cs.onSurface.withValues(alpha: 0.2),
                                  size: 22,
                                ),
                                tooltip: canAdd ? 'Add tab' : 'Maximum 5 tabs reached',
                                onPressed: () => _addTab(context, ref, activeTabs, tab),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
