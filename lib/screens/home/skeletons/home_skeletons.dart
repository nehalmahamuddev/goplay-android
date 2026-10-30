import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../widgets/cards/playz_event_card.dart';

/// Skeleton for the Hero Banner carousel
class HeroBannerSkeleton extends StatelessWidget {
  const HeroBannerSkeleton({super.key});

  static const _decoration = BoxDecoration(
    color: GoPlayTheme.surfaceContainer,
    borderRadius: BorderRadius.all(Radius.circular(20)),
  );

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: SizedBox(
        height: 200,
        child: DecoratedBox(
          decoration: _decoration,
          child: Center(
            child: CircularProgressIndicator(color: GoPlayTheme.primary),
          ),
        ),
      ),
    );
  }
}

/// Placeholder row of 5 grey circles matching channel avatar size.
class TrendingChannelsSkeleton extends StatelessWidget {
  const TrendingChannelsSkeleton({super.key});

  static const _circleDecoration = BoxDecoration(
    color: GoPlayTheme.surfaceContainerHigh,
    shape: BoxShape.circle,
  );

  static const _barDecoration = BoxDecoration(
    color: GoPlayTheme.surfaceContainerHigh,
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        itemBuilder: (context, index) {
          return const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Padding(
              padding: EdgeInsets.all(4),
              child: SizedBox(
                width: 72,
                child: Column(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: DecoratedBox(decoration: _circleDecoration),
                    ),
                    SizedBox(height: 6),
                    SizedBox(
                      width: 48,
                      height: 10,
                      child: DecoratedBox(decoration: _barDecoration),
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

/// Placeholder row of 4 grey pill-shaped chips.
class ChipsSkeleton extends StatelessWidget {
  const ChipsSkeleton({super.key});

  static const _chipDecoration = BoxDecoration(
    color: GoPlayTheme.surfaceContainerHigh,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          const SizedBox(width: 16),
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(
              width: i == 0 ? 42 : 70,
              height: 32,
              child: const DecoratedBox(decoration: _chipDecoration),
            ),
          ],
        ],
      ),
    );
  }
}

/// 3 grey placeholder cards matching the measured event card extent.
class ScheduleSkeleton extends StatelessWidget {
  const ScheduleSkeleton({super.key});

  static const _cardDecoration = BoxDecoration(
    color: GoPlayTheme.surfaceContainerHigh,
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    return SliverFixedExtentList.builder(
      itemExtent: PlayZEventCard.tileExtent(context),
      itemCount: 3,
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: DecoratedBox(decoration: _cardDecoration),
          ),
        );
      },
    );
  }
}

