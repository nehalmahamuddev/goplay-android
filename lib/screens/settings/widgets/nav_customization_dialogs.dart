import 'package:flutter/material.dart';
import '../../../core/typography.dart';

/// Choice dialog for selecting the default launch page on app startup.
class LaunchPageChoiceDialog extends StatelessWidget {
  final String currentPage;
  final ValueChanged<String> onSelect;

  const LaunchPageChoiceDialog({
    super.key,
    required this.currentPage,
    required this.onSelect,
  });

  static const List<(String, String, String, IconData)> options = [
    ('home', 'Home', 'Open directly to the home screen', Icons.home_rounded),
    ('channels', 'Channels', 'Browse all live streaming channels', Icons.live_tv_rounded),
    ('favorites', 'Favorites', 'Jump straight to your favorited channels', Icons.favorite_rounded),
    ('categories', 'Categories', 'Explore channels sorted by category', Icons.grid_view_rounded),
    ('events', 'Events', 'View upcoming sports and live event schedules', Icons.event_rounded),
    ('settings', 'Settings', 'Quick access to app preferences', Icons.settings_rounded),
    ('last_used', 'Last used screen', 'Resume right where you left off', Icons.history_rounded),
  ];

  static Future<void> show(
    BuildContext context, {
    required String currentPage,
    required ValueChanged<String> onSelect,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => LaunchPageChoiceDialog(
        currentPage: currentPage,
        onSelect: onSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      backgroundColor: const Color(0xFF161616),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Text(
        'Default Launch Screen',
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = opt.$1 == currentPage;
              return InkWell(
                onTap: () {
                  onSelect(opt.$1);
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary.withValues(alpha: 0.15)
                              : const Color(0xFF222222),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          opt.$4,
                          size: 20,
                          color: isSelected ? cs.primary : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              opt.$2,
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? cs.primary : cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              opt.$3,
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 12,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: cs.primary,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
