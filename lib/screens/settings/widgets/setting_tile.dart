import 'package:flutter/material.dart';
import '../../../core/typography.dart';
import '../../../widgets/tv_focus_wrapper.dart';

/// An Upstream-styled preference tile featuring an icon, title, optional
/// comma-separated/descriptive subtitle, and optional trailing widget (e.g. Switch, Badge, Chevron).
class SettingTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const SettingTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  }) : assert(icon != null || leading != null, 'Either icon or leading must be provided');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primaryAccent = cs.primary;

    final leadingWidget = leading ??
        Icon(
          icon,
          size: 24,
          color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4),
        );

    final content = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      splashColor: primaryAccent.withValues(alpha: 0.12),
      highlightColor: primaryAccent.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Center(child: leadingWidget),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: GoPlayType.base,
                      fontWeight: FontWeight.w600,
                      color: enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.4),
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: GoPlayType.sm,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurfaceVariant.withValues(alpha: enabled ? 0.8 : 0.4),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );

    return TvFocusable(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: content,
    );
  }
}

/// A specialized SettingTile with a built-in Cupertino/Material style toggle switch.
class SettingSwitchTile extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const SettingSwitchTile({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SettingTile(
      icon: icon,
      leading: leading,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: Colors.white,
        activeTrackColor: cs.primary,
        inactiveThumbColor: const Color(0xFFB0B0B0),
        inactiveTrackColor: const Color(0xFF2C2C2E),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

