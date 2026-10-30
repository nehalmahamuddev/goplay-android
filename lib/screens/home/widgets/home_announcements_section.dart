import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../models/announcement.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/tv_focus_wrapper.dart';

const _kAnnouncementTitleStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.onSurface,
  fontSize: GoPlayType.sm,
  fontWeight: FontWeight.w600,
  height: GoPlayType.leadingSnug,
);

const _kAnnouncementBodyStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.onSurfaceVariant,
  fontSize: GoPlayType.xs,
  height: GoPlayType.leadingBody,
);

/// Announcements section with D-Pad focusable tiles
class HomeAnnouncementsSection extends ConsumerWidget {
  const HomeAnnouncementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(announcementsProvider);

    return announcementsAsync.when(
      data: (announcements) {
        if (announcements.isEmpty) return const SizedBox.shrink();

        return Column(
          children: [
            const SectionHeader(title: 'Announcements'),
            for (final a in announcements) _AnnouncementTile(announcement: a),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  final Announcement announcement;

  const _AnnouncementTile({required this.announcement});

  @override
  Widget build(BuildContext context) {
    final bool isWarning = announcement.type == 'warning';
    final theme = Theme.of(context);
    final iconColor = isWarning ? const Color(0xFFFFB020) : GoPlayTheme.primary;
    final iconBgColor = isWarning
        ? const Color(0xFFFFB020).withValues(alpha: 0.12)
        : GoPlayTheme.primary.withValues(alpha: 0.12);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(12),
        onTap: () {},
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isWarning
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    color: iconColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(announcement.title, style: _kAnnouncementTitleStyle),
                      const SizedBox(height: 3),
                      Text(announcement.body, style: _kAnnouncementBodyStyle),
                    ],
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
