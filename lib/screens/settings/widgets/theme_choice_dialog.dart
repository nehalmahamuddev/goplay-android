import 'package:flutter/material.dart';
import '../../../core/typography.dart';
import '../../../models/app_theme_options.dart';

/// Upstream-styled Theme Mode selection modal dialog with preview swatches.
class ThemeModeChoiceDialog extends StatelessWidget {
  final AppThemeMode currentMode;
  final ValueChanged<AppThemeMode> onSelect;

  const ThemeModeChoiceDialog({
    super.key,
    required this.currentMode,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required AppThemeMode currentMode,
    required ValueChanged<AppThemeMode> onSelect,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ThemeModeChoiceDialog(
        currentMode: currentMode,
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
        'App Theme',
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
          child: RadioGroup<AppThemeMode>(
            groupValue: currentMode,
            onChanged: (val) {
              if (val != null) {
                onSelect(val);
                Navigator.of(context).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppThemeMode.values.map((mode) {
                final isSelected = mode == currentMode;
                return InkWell(
                  onTap: () {
                    onSelect(mode);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        // Swatch Preview
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: mode.surfaceColor,
                            border: Border.all(
                              color: mode.cardColor,
                              width: 3.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode.displayName,
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? cs.primary : cs.onSurface,
                                ),
                              ),
                              if (mode.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mode.subtitle,
                                  style: TextStyle(
                                    fontFamily: GoPlayType.family,
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Radio<AppThemeMode>(
                          value: mode,
                          activeColor: cs.primary,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Upstream-styled Accent Color selection modal dialog with preview swatches.
class AccentColorChoiceDialog extends StatelessWidget {
  final AppAccentColor currentAccent;
  final ValueChanged<AppAccentColor> onSelect;

  const AccentColorChoiceDialog({
    super.key,
    required this.currentAccent,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required AppAccentColor currentAccent,
    required ValueChanged<AppAccentColor> onSelect,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AccentColorChoiceDialog(
        currentAccent: currentAccent,
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
        'Primary Accent Color',
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
          child: RadioGroup<AppAccentColor>(
            groupValue: currentAccent,
            onChanged: (val) {
              if (val != null) {
                onSelect(val);
                Navigator.of(context).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppAccentColor.values.map((accent) {
                final isSelected = accent == currentAccent;
                return InkWell(
                  onTap: () {
                    onSelect(accent);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.color,
                            boxShadow: [
                              BoxShadow(
                                color: accent.color.withValues(alpha: 0.35),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            accent.displayName,
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? accent.color : cs.onSurface,
                            ),
                          ),
                        ),
                        Radio<AppAccentColor>(
                          value: accent,
                          activeColor: accent.color,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
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
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

