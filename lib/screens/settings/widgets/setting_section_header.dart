import 'package:flutter/material.dart';
import '../../../core/typography.dart';

/// Section header for settings categories, matching Upstream's clean sub-group headers.
class SettingSectionHeader extends StatelessWidget {
  final String title;

  const SettingSectionHeader({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 6.0),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: GoPlayType.sm,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

