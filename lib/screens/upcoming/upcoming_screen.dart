import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../providers/app_providers.dart';
import '../../providers/theme_provider.dart';
import '../../models/event.dart';
import '../../services/event_stream_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/cards/playz_event_card.dart';
import '../../widgets/tv_focus_wrapper.dart';
import '../../widgets/search_pill_card.dart';

enum EventSortOption { defaultTime, teamNameAsc, leagueSport }

/// Live Events Hub for GoPlay
///
/// Implements the complete Live Events Client Architecture:
/// - Section 2.1: Sport Category Filter Chips (All, Cricket, Football, etc.)
/// - Section 5.2: 5 Pinned Status Tabs (Live, Today, Tomorrow, Upcoming, Ended)
/// - Section 6: Smart JIT on-demand stream resolution & decryption with instant playback
/// - Section 5.1: Strict UTC/GMT lifecycle evaluation
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  Timer? _realtimeRefreshTimer;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'EventsSearch');
  final _searchQueryNotifier = ValueNotifier<String>('');
  final _eventSortNotifier =
      ValueNotifier<EventSortOption>(EventSortOption.defaultTime);
  Timer? _debounceTimer;

  static const _tabs = [
    'Live',
    'Today',
    'Tomorrow',
    'Upcoming',
    'Ended',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: _tabs.length, vsync: this);

    // Initial background refresh of direct live events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleRefresh();
    });

    // 30-second polling interval matching backend real-time live events updates
    _realtimeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _handleRefresh();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeRefreshTimer?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    _eventSortNotifier.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 150),
      () => _searchQueryNotifier.value = value,
    );
  }

  void _onSearchClearPressed() {
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchQueryNotifier.value = '';
  }

  void _showEventsFilterSheet(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasActiveFilters =
                _eventSortNotifier.value != EventSortOption.defaultTime;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters & Sorting',
                          style: (Theme.of(context).textTheme.titleMedium ??
                                  GoPlayType.title)
                              .copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasActiveFilters)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: GoPlayTheme.primary,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              _eventSortNotifier.value =
                                  EventSortOption.defaultTime;
                              setSheetState(() {});
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Sort Options
                    Text(
                      'SORT BY',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF202020)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSortTile(
                            context: context,
                            title: 'Match Time (Default)',
                            icon: Icons.schedule_rounded,
                            isSelected: _eventSortNotifier.value ==
                                EventSortOption.defaultTime,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _eventSortNotifier.value =
                                  EventSortOption.defaultTime;
                              setSheetState(() {});
                            },
                          ),
                          Divider(
                            height: 1,
                            color: cs.onSurface.withValues(alpha: 0.06),
                            indent: 48,
                          ),
                          _buildSortTile(
                            context: context,
                            title: 'Team Names (A to Z)',
                            icon: Icons.sort_by_alpha_rounded,
                            isSelected: _eventSortNotifier.value ==
                                EventSortOption.teamNameAsc,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _eventSortNotifier.value =
                                  EventSortOption.teamNameAsc;
                              setSheetState(() {});
                            },
                          ),
                          Divider(
                            height: 1,
                            color: cs.onSurface.withValues(alpha: 0.06),
                            indent: 48,
                          ),
                          _buildSortTile(
                            context: context,
                            title: 'League / Sport Name',
                            icon: Icons.emoji_events_outlined,
                            isSelected: _eventSortNotifier.value ==
                                EventSortOption.leagueSport,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _eventSortNotifier.value =
                                  EventSortOption.leagueSport;
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Actions
                    Text(
                      'QUICK ACTIONS',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.refresh_rounded,
                            label: 'Refresh',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              HapticFeedback.mediumImpact();
                              _handleRefresh();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              context.push('/settings');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? GoPlayTheme.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? GoPlayTheme.primary : cs.onSurface,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                size: 20,
                color: GoPlayTheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? const Color(0xFF202020)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ref.invalidate(eventsProvider);
        ref.invalidate(eventCategoriesProvider);
      } catch (_) {}
    });
  }

  Future<void> _handleEventTap(SportEvent event) async {
    await EventStreamLauncher.launch(context, event);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;
    final sportsAsync = ref.watch(sortedSportCategoriesProvider);
    final selectedSport = ref.watch(selectedSportFilterProvider);
    final liveEventsCount = ref.watch(liveEventsProvider).value?.length ?? 0;
    final uiConfig = ref.watch(uiConfigProvider);

    final hasOverride = uiConfig.componentStyles.categoryChips.useCustomOverride;
    final activeBg = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipActiveBg(isHome: false))
        : cs.primary;
    final inactiveBg = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipInactiveBg(isHome: false))
        : theme.cardColor;
    final activeTextColor = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipActiveTextColor(isHome: false))
        : cs.onPrimary;
    final inactiveTextColor = hasOverride
        ? GoPlayTheme.parseHex(uiConfig.resolveCategoryChipInactiveTextColor(isHome: false))
        : cs.onSurface;
    final chipRadius = uiConfig.resolveCategoryChipRadius(isHome: false);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: ListenableBuilder(
      listenable: Listenable.merge([_searchController, _eventSortNotifier]),
      builder: (context, _) {
        final canPop = _searchController.text.isEmpty &&
            _eventSortNotifier.value == EventSortOption.defaultTime;

        return PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              if (_searchController.text.isNotEmpty) {
                _onSearchClearPressed();
              } else if (_eventSortNotifier.value !=
                  EventSortOption.defaultTime) {
                _eventSortNotifier.value = EventSortOption.defaultTime;
              }
            }
          },
          child: Material(
            color: cs.surface,
            child: NestedScrollView(
              physics: const BouncingScrollPhysics(),
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _UpcomingHeaderDelegate(
                      statusBarHeight: statusBarHeight,
                      searchPill: ValueListenableBuilder<EventSortOption>(
                        valueListenable: _eventSortNotifier,
                        builder: (context, currentSort, _) {
                          return SearchPillCard(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            hintText: 'Search events, teams, leagues...',
                            isFilterActive: currentSort !=
                                EventSortOption.defaultTime,
                            onChanged: _onSearchChanged,
                            onClear: _onSearchClearPressed,
                            onFilterTap: () =>
                                _showEventsFilterSheet(context),
                          );
                        },
                      ),
                      sportChips: sportsAsync.when(
                        data: (sports) => SizedBox(
                          height: 44,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            scrollDirection: Axis.horizontal,
                            itemCount: sports.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final sport = sports[index];
                              final isSelected = sport.toLowerCase() ==
                                  selectedSport.toLowerCase();
                              return TvFocusable(
                                borderRadius: BorderRadius.circular(chipRadius),
                                onTap: () {
                                  ref
                                      .read(selectedSportFilterProvider.notifier)
                                      .select(sport);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? activeBg : inactiveBg,
                                    borderRadius:
                                        BorderRadius.circular(chipRadius),
                                  ),
                                  child: Text(
                                    sport,
                                    style: TextStyle(
                                      fontFamily: GoPlayType.family,
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? activeTextColor
                                          : inactiveTextColor,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        loading: () => const SizedBox(height: 44),
                        error: (err, stack) => const SizedBox.shrink(),
                      ),
                      tabBar: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        physics: const BouncingScrollPhysics(),
                        tabAlignment: TabAlignment.start,
                        padding: const EdgeInsets.only(left: 4),
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        indicator: const UnderlineTabIndicator(
                          borderSide: BorderSide(
                              color: GoPlayTheme.primary, width: 3.0),
                          borderRadius:
                              BorderRadius.all(Radius.circular(1.5)),
                        ),
                        indicatorSize: TabBarIndicatorSize.label,
                        indicatorPadding: const EdgeInsets.only(bottom: 2),
                        dividerColor: Colors.transparent,
                        dividerHeight: 0,
                        labelColor: GoPlayTheme.primary,
                        unselectedLabelColor: GoPlayTheme.onSurfaceVariant,
                        labelStyle: GoPlayType.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: GoPlayType.label.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        tabs: [
                          Tab(
                            text:
                                'Live${liveEventsCount > 0 ? ' ($liveEventsCount)' : ''}',
                          ),
                          const Tab(text: 'Today'),
                          const Tab(text: 'Tomorrow'),
                          const Tab(text: 'Upcoming'),
                          const Tab(text: 'Ended'),
                        ],
                      ),
                      backgroundColor: headerBg,
                    ),
                  ),
                ];
              },
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 0: Live Events
            _EventsListView(
              eventsAsync: ref.watch(filteredLiveEventsProvider(selectedSport)),
              searchQueryNotifier: _searchQueryNotifier,
              sortNotifier: _eventSortNotifier,
              onClearSearch: _onSearchClearPressed,
              onRefresh: _handleRefresh,
              onEventTap: _handleEventTap,
              emptyMessage: 'No live matches right now.',
            ),

            // Tab 1: Today Events
            _EventsListView(
              eventsAsync: ref.watch(filteredTodayEventsProvider(selectedSport)),
              searchQueryNotifier: _searchQueryNotifier,
              sortNotifier: _eventSortNotifier,
              onClearSearch: _onSearchClearPressed,
              onRefresh: _handleRefresh,
              onEventTap: _handleEventTap,
              emptyMessage: 'No matches scheduled for today.',
            ),

            // Tab 2: Tomorrow Events
            _EventsListView(
              eventsAsync: ref.watch(filteredTomorrowEventsProvider),
              searchQueryNotifier: _searchQueryNotifier,
              sortNotifier: _eventSortNotifier,
              onClearSearch: _onSearchClearPressed,
              onRefresh: _handleRefresh,
              onEventTap: _handleEventTap,
              emptyMessage: 'No matches scheduled for tomorrow.',
            ),

            // Tab 3: Upcoming Events (Grouped by date)
            _GroupedUpcomingListView(
              eventsAsync: ref.watch(filteredUpcomingEventsProvider),
              searchQueryNotifier: _searchQueryNotifier,
              sortNotifier: _eventSortNotifier,
              onClearSearch: _onSearchClearPressed,
              onRefresh: _handleRefresh,
              onEventTap: _handleEventTap,
            ),

            // Tab 4: Ended Events
            _EventsListView(
              eventsAsync: ref.watch(filteredEndedEventsProvider),
              searchQueryNotifier: _searchQueryNotifier,
              sortNotifier: _eventSortNotifier,
              onClearSearch: _onSearchClearPressed,
              onRefresh: _handleRefresh,
              onEventTap: _handleEventTap,
              emptyMessage: 'No completed matches recorded.',
            ),
          ],
        ),
      ),
    ),
  );
        },
      ),
    );
  }
}

List<SportEvent> _filterAndSortEvents(
  List<SportEvent> events,
  String query,
  EventSortOption sort,
) {
  var list = events;
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    list = list.where((e) {
      return e.homeTeam.name.toLowerCase().contains(q) ||
          e.awayTeam.name.toLowerCase().contains(q) ||
          e.league.toLowerCase().contains(q) ||
          e.sport.toLowerCase().contains(q);
    }).toList();
  } else {
    list = List.of(events);
  }

  if (sort == EventSortOption.teamNameAsc) {
    list.sort((a, b) => a.homeTeam.name
        .toLowerCase()
        .compareTo(b.homeTeam.name.toLowerCase()));
  } else if (sort == EventSortOption.leagueSport) {
    list.sort((a, b) {
      final leagueCompare =
          a.league.toLowerCase().compareTo(b.league.toLowerCase());
      if (leagueCompare != 0) return leagueCompare;
      return a.sport.toLowerCase().compareTo(b.sport.toLowerCase());
    });
  }
  return list;
}

// ─── Single List Tab View ───────────────────────────────────────────────────
class _EventsListView extends StatelessWidget {
  final AsyncValue<List<SportEvent>> eventsAsync;
  final ValueNotifier<String> searchQueryNotifier;
  final ValueNotifier<EventSortOption> sortNotifier;
  final VoidCallback onClearSearch;
  final Future<void> Function() onRefresh;
  final void Function(SportEvent) onEventTap;
  final String emptyMessage;

  const _EventsListView({
    required this.eventsAsync,
    required this.searchQueryNotifier,
    required this.sortNotifier,
    required this.onClearSearch,
    required this.onRefresh,
    required this.onEventTap,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktopOrTv = MediaQuery.of(context).size.width >= 800;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: GoPlayTheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      child: ListenableBuilder(
        listenable: Listenable.merge([searchQueryNotifier, sortNotifier]),
        builder: (context, _) {
          return eventsAsync.when(
            data: (rawEvents) {
              final query = searchQueryNotifier.value.trim();
              final sort = sortNotifier.value;
              final events = _filterAndSortEvents(rawEvents, query, sort);

              if (events.isEmpty) {
                if (query.isNotEmpty) {
                  return _EmptyTabState(
                    message: 'No matches found for "$query"',
                    isSearch: true,
                    onClearSearch: onClearSearch,
                  );
                }
                return _EmptyTabState(message: emptyMessage);
              }

              if (isDesktopOrTv) {
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: PlayZEventCard.tileExtent(context),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 0,
                  ),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return PlayZEventCard(
                      key: ValueKey(event.id),
                      event: event,
                      onTap: () => onEventTap(event),
                    );
                  },
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
                itemExtent: PlayZEventCard.tileExtent(context),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return PlayZEventCard(
                    key: ValueKey(event.id),
                    event: event,
                    onTap: () => onEventTap(event),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: GoPlayTheme.primary),
            ),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: const TextStyle(color: GoPlayTheme.error),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Grouped Upcoming Tab View ──────────────────────────────────────────────
class _GroupedUpcomingListView extends StatelessWidget {
  final AsyncValue<List<SportEvent>> eventsAsync;
  final ValueNotifier<String> searchQueryNotifier;
  final ValueNotifier<EventSortOption> sortNotifier;
  final VoidCallback onClearSearch;
  final Future<void> Function() onRefresh;
  final void Function(SportEvent) onEventTap;

  const _GroupedUpcomingListView({
    required this.eventsAsync,
    required this.searchQueryNotifier,
    required this.sortNotifier,
    required this.onClearSearch,
    required this.onRefresh,
    required this.onEventTap,
  });

  static Map<String, List<SportEvent>> _groupByDate(List<SportEvent> events) {
    final Map<String, List<SportEvent>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    for (final event in events) {
      final localStart = event.startTime.toLocal();
      final eventDate = DateTime(
        localStart.year,
        localStart.month,
        localStart.day,
      );

      final String label;
      if (eventDate == today) {
        label = 'Today';
      } else if (eventDate == tomorrow) {
        label = 'Tomorrow';
      } else if (eventDate.isBefore(nextWeek)) {
        label = DateFormat('EEEE, MMM d').format(localStart);
      } else {
        label = DateFormat('MMM d, yyyy').format(localStart);
      }

      grouped.putIfAbsent(label, () => []).add(event);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopOrTv = MediaQuery.of(context).size.width >= 800;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: GoPlayTheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      child: ListenableBuilder(
        listenable: Listenable.merge([searchQueryNotifier, sortNotifier]),
        builder: (context, _) {
          return eventsAsync.when(
            data: (rawEvents) {
              final query = searchQueryNotifier.value.trim();
              final sort = sortNotifier.value;
              final events = _filterAndSortEvents(rawEvents, query, sort);
              final grouped = _groupByDate(events);

              if (grouped.isEmpty) {
                if (query.isNotEmpty) {
                  return _EmptyTabState(
                    message: 'No matches found for "$query"',
                    isSearch: true,
                    onClearSearch: onClearSearch,
                  );
                }
                return const _EmptyTabState(
                    message: 'No upcoming fixtures scheduled.');
              }

              final keys = grouped.keys.toList(growable: false);

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  final key = keys[index];
                  final dayEvents = grouped[key]!;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 15,
                          color: GoPlayTheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          key,
                          style: GoPlayType.label.copyWith(
                            color: GoPlayTheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isDesktopOrTv)
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisExtent: PlayZEventCard.tileExtent(context),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 0,
                        ),
                        itemCount: dayEvents.length,
                        itemBuilder: (context, idx) {
                          final event = dayEvents[idx];
                          return PlayZEventCard(
                            key: ValueKey(event.id),
                            event: event,
                            onTap: () => onEventTap(event),
                          );
                        },
                      )
                    else
                      ...dayEvents.map(
                        (event) => PlayZEventCard(
                          key: ValueKey(event.id),
                          event: event,
                          onTap: () => onEventTap(event),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: GoPlayTheme.primary),
        ),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: GoPlayTheme.error)),
        ),
      );
        },
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────
class _EmptyTabState extends StatelessWidget {
  final String message;
  final bool isSearch;
  final VoidCallback? onClearSearch;

  const _EmptyTabState({
    required this.message,
    this.isSearch = false,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearch ? Icons.search_off_rounded : Icons.sports_rounded,
              size: 48,
              color: GoPlayTheme.onSurfaceMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoPlayType.body.copyWith(
                color: GoPlayTheme.onSurfaceVariant,
              ),
            ),
            if (isSearch && onClearSearch != null) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Clear search'),
                style: TextButton.styleFrom(
                  foregroundColor: GoPlayTheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Pinned Upcoming Header Delegate ─────────────────────────────────────────
class _UpcomingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double statusBarHeight;
  final Widget searchPill;
  final Widget sportChips;
  final TabBar tabBar;
  final Color backgroundColor;

  static const double _searchHeight = 54.0;
  static const double _chipsHeight = 44.0;
  static const double _collapsibleHeight = _searchHeight + _chipsHeight; // 98.0

  _UpcomingHeaderDelegate({
    required this.statusBarHeight,
    required this.searchPill,
    required this.sportChips,
    required this.tabBar,
    required this.backgroundColor,
  });

  double get _tabHeight => tabBar.preferredSize.height;

  @override
  double get minExtent => statusBarHeight + _tabHeight;

  @override
  double get maxExtent => statusBarHeight + _collapsibleHeight + _tabHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scrollOffset = shrinkOffset.clamp(0.0, _collapsibleHeight);
    final collapseRatio = (scrollOffset / _collapsibleHeight).clamp(0.0, 1.0);

    return Container(
      color: backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Collapsible portion: Search Pill + Sport Chips
          // Bounded strictly between statusBarHeight and the bottom TabBar
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            bottom: _tabHeight,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    top: -scrollOffset,
                    left: 0,
                    right: 0,
                    height: _collapsibleHeight,
                    child: IgnorePointer(
                      ignoring: collapseRatio > 0.5,
                      child: Opacity(
                        opacity: (1.0 - (collapseRatio / 0.85)).clamp(0.0, 1.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: _searchHeight, child: searchPill),
                            SizedBox(height: _chipsHeight, child: sportChips),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pinned TabBar: Always stays at the bottom of the header,
          // which when fully collapsed aligns exactly below statusBarHeight.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _tabHeight,
            child: tabBar,
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_UpcomingHeaderDelegate oldDelegate) {
    return oldDelegate.statusBarHeight != statusBarHeight ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.tabBar != tabBar ||
        oldDelegate.searchPill != searchPill ||
        oldDelegate.sportChips != sportChips;
  }
}
