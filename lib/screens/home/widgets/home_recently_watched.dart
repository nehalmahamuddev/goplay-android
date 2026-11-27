import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../services/channel_stream_launcher.dart';
import '../../../widgets/section_header.dart';
import 'home_trending_channels.dart';

const TextStyle _historyNameStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.onSurface,
  fontSize: GoPlayType.xs,
  height: GoPlayType.leadingSnug,
);

/// Horizontal rail of recently watched channels
class HomeRecentlyWatched extends ConsumerWidget {
  const HomeRecentlyWatched({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(watchHistoryProvider);

    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recently Watched'),
        SizedBox(
          height: 88,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: history.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            itemBuilder: (context, index) {
              final ch = history[index];
              return HomeChannelItem(
                channel: ch,
                nameStyle: _historyNameStyle,
                showBorder: false,
                onTap: () => ChannelStreamLauncher.launch(context, ch, scope: history),
              );
            },
          ),
        ),
      ],
    );
  }
}
