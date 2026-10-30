import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../providers/app_providers.dart';
import '../../widgets/section_header.dart';

import 'widgets/home_sliver_app_bar.dart';
import 'widgets/home_hero_banner.dart';
import 'widgets/home_sport_category_filter_chips.dart';
import 'widgets/home_today_schedule.dart';
import 'widgets/home_trending_channels.dart';
import 'widgets/home_recently_watched.dart';
import 'widgets/home_announcements_section.dart';

/// Clean, modular, and reactive HomeScreen orchestrator.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Tight, balanced spacing (10dp) directly below search input to achieve visual symmetry
  static const double _firstSectionTopSpacing = 10.0;

  /// Standard inter-section spacing between subsequent content sections
  static const double _sectionSpacing = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsProvider);
    final cs = Theme.of(context).colorScheme;

    // Handle cold initial launch when local cache is completely empty
    return channelsAsync.when(
      data: (channels) => _buildMainContent(context, ref),
      loading: () => Material(
        color: cs.surface,
        child: const Center(
          child: CircularProgressIndicator(
            color: GoPlayTheme.primary,
          ),
        ),
      ),
      error: (error, stack) => Material(
        color: cs.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: GoPlayTheme.error,
                ),
                const SizedBox(height: 20),
                const Text(
                  'CONNECTION ERROR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: GoPlayType.lg,
                    fontWeight: FontWeight.w800,
                    color: GoPlayTheme.onSurface,
                    height: GoPlayType.leadingTitle,
                    letterSpacing: GoPlayType.trackingWide,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  error.toString().replaceAll('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: GoPlayType.body.copyWith(
                    color: GoPlayTheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(appSyncProvider);
                    ref.invalidate(channelsProvider);
                    ref.invalidate(eventsProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('RETRY CONNECTION'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GoPlayTheme.primary,
                    foregroundColor: const Color(0xFF003300),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _buildMainContent(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    // Adaptive bottom inset: adapts dynamically to TV/Desktop side rail vs mobile gesture bar
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final isTv = MediaQuery.navigationModeOf(context) == NavigationMode.directional ||
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final isDesktop = isLandscape || isTv;
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomSpacing = isDesktop ? 24.0 : (80.0 + bottomPadding);

    return Material(
      color: cs.surface,
      child: RefreshIndicator(
        color: GoPlayTheme.primary,
        backgroundColor: cs.surfaceContainerHigh,
        // Emerge smoothly from directly below the search input pill
        edgeOffset: statusBarHeight + HomeSliverAppBar.contentExpandedHeight,
        displacement: 32.0,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(eventsProvider);
          ref.invalidate(channelsProvider);
          ref.invalidate(heroBannersProvider);
          ref.invalidate(announcementsProvider);
          try {
            await ref.read(syncServiceProvider).sync();
          } catch (_) {}
          try {
            await ref.read(eventsProvider.future);
          } catch (_) {}
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          cacheExtent: 600.0,
          slivers: [
            // Collapsing Dark-Themed Edge-to-Edge App Bar (flush with search bar bottom)
            const HomeSliverAppBar(),

            // Modular dynamic sections with tight 10dp gap below search and 20dp inter-section spacing
            ..._buildModularSections(context, ref),

            // Adaptive bottom spacing
            SliverToBoxAdapter(child: SizedBox(height: bottomSpacing)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildModularSections(BuildContext context, WidgetRef ref) {
    final uiConfig = ref.watch(uiConfigProvider);
    final homeConfig = uiConfig.homeScreen;
    final order = homeConfig.sectionOrder;

    final widgets = <Widget>[];
    bool isFirstSection = true;

    for (final sectionKey in order) {
      if (sectionKey == 'hero' && homeConfig.showHeroBanner) {
        final topGap = isFirstSection ? _firstSectionTopSpacing : _sectionSpacing;
        isFirstSection = false;
        widgets.addAll([
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: HomeHeroBanner()),
          ),
        ]);
      } else if (sectionKey == 'trending' && homeConfig.showTrendingSection) {
        final topGap = isFirstSection ? _firstSectionTopSpacing : _sectionSpacing;
        isFirstSection = false;
        widgets.addAll([
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Trending Channels',
              actionLabel: 'See all',
              onAction: () {
                final isTrendingEnabled = ref.read(showTrendingTabProvider);
                ref.read(selectedCategoryProvider.notifier).select(
                  isTrendingEnabled ? 'trending' : 'all',
                );
                context.go('/channels');
              },
            ),
          ),
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: HomeTrendingChannels()),
          ),
        ]);
      } else if (sectionKey == 'matches' && homeConfig.showTodaysMatches) {
        final topGap = isFirstSection ? _firstSectionTopSpacing : _sectionSpacing;
        isFirstSection = false;
        widgets.addAll([
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: "Today's Matches",
              actionLabel: 'See all',
              onAction: () => context.go('/upcoming'),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: RepaintBoundary(child: HomeSportCategoryFilterChips()),
            ),
          ),
          const HomeTodaySchedule(),
        ]);
      } else if (sectionKey == 'recent' && homeConfig.showRecentlyWatched) {
        final topGap = isFirstSection ? _firstSectionTopSpacing : _sectionSpacing;
        isFirstSection = false;
        widgets.addAll([
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: HomeRecentlyWatched()),
          ),
        ]);
      } else if (sectionKey == 'announcements' && homeConfig.showAnnouncements) {
        final topGap = isFirstSection ? _firstSectionTopSpacing : _sectionSpacing;
        isFirstSection = false;
        widgets.addAll([
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: HomeAnnouncementsSection()),
          ),
        ]);
      }
    }

    // Safety fallback: if all sections turned off, show trending channels
    if (widgets.isEmpty) {
      widgets.addAll([
        const SliverToBoxAdapter(child: SizedBox(height: _firstSectionTopSpacing)),
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Trending Channels',
            actionLabel: 'See all',
            onAction: () {
              final isTrendingEnabled = ref.read(showTrendingTabProvider);
              ref.read(selectedCategoryProvider.notifier).select(
                isTrendingEnabled ? 'trending' : 'all',
              );
              context.go('/channels');
            },
          ),
        ),
        const SliverToBoxAdapter(
          child: RepaintBoundary(child: HomeTrendingChannels()),
        ),
      ]);
    }

    return widgets;
  }
}
