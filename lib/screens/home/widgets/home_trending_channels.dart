import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/channel.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/channel_avatar.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../skeletons/home_skeletons.dart';

const _kTrendingNameStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.onSurface,
  fontSize: GoPlayType.xs,
  fontWeight: FontWeight.w500,
  height: GoPlayType.leadingSnug,
);

/// Horizontal rail of trending channels on HomeScreen
class HomeTrendingChannels extends ConsumerWidget {
  const HomeTrendingChannels({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingChannelsProvider);

    return trendingAsync.when(
      data: (channels) {
        if (channels.isEmpty) return const SizedBox.shrink();

        final railIds = channels.map((c) => c.id).toList(growable: false);

        return SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: channels.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            itemBuilder: (context, index) {
              final ch = channels[index];
              return HomeChannelItem(
                channel: ch,
                nameStyle: _kTrendingNameStyle,
                showBorder: true,
                onTap: () => context.push(
                  '/player/${ch.id}',
                  extra: {'eventChannels': railIds},
                ),
              );
            },
          ),
        );
      },
      loading: () => const TrendingChannelsSkeleton(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

/// Common Channel Item widget for horizontal rails
class HomeChannelItem extends StatelessWidget {
  final Channel channel;
  final TextStyle nameStyle;
  final bool showBorder;
  final VoidCallback onTap;

  const HomeChannelItem({
    super.key,
    required this.channel,
    required this.nameStyle,
    required this.showBorder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: SizedBox(
            width: 72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChannelAvatar(channel: channel, showBorder: showBorder),
                const SizedBox(height: 4),
                Text(
                  channel.displayName,
                  style: nameStyle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

