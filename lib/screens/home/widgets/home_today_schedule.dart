import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/event.dart';
import '../../../providers/app_providers.dart';
import '../../../services/event_stream_launcher.dart';
import '../../../widgets/cards/playz_event_card.dart';
import '../skeletons/home_skeletons.dart';

/// Today's schedule & live matches section on HomeScreen
class HomeTodaySchedule extends ConsumerStatefulWidget {
  const HomeTodaySchedule({super.key});

  @override
  ConsumerState<HomeTodaySchedule> createState() => _HomeTodayScheduleState();
}

class _HomeTodayScheduleState extends ConsumerState<HomeTodaySchedule> {
  bool _isLaunching = false;

  Future<void> _handleEventTap(BuildContext context, SportEvent event) async {
    if (_isLaunching) return;
    _isLaunching = true;
    try {
      await EventStreamLauncher.launch(context, event);
    } finally {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _isLaunching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSport = ref.watch(selectedSportFilterProvider);
    // Binds to filteredTodayEventsProvider so all of today's fixtures (live + upcoming today) are shown!
    final eventsAsync = ref.watch(filteredTodayEventsProvider(selectedSport));

    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          final emptyText = selectedSport.toLowerCase() == 'all'
              ? 'No matches scheduled for today'
              : 'No $selectedSport matches scheduled for today';
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: Text(
                emptyText,
                style: const TextStyle(color: GoPlayTheme.onSurfaceVariant),
              ),
            ),
          );
        }

        final size = MediaQuery.sizeOf(context);
        final isTv = MediaQuery.navigationModeOf(context) == NavigationMode.directional ||
            FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
        final isDesktopOrTv = size.width >= 800 || (size.width > size.height && size.width > 600) || isTv;

        if (isDesktopOrTv) {
          final crossAxisCount = size.width >= 1200 ? 4 : (size.width >= 800 ? 3 : 2);
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
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
                  onTap: () => _handleEventTap(context, event),
                );
              },
            ),
          );
        }

        return SliverFixedExtentList.builder(
          itemExtent: PlayZEventCard.tileExtent(context),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: PlayZEventCard(
                key: ValueKey(event.id),
                event: event,
                onTap: () => _handleEventTap(context, event),
              ),
            );
          },
        );
      },
      loading: () => const ScheduleSkeleton(),
      error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

