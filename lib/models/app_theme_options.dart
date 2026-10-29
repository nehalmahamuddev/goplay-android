import 'package:flutter/material.dart';

/// Supported background canvas & card theme modes in GoPlay.
enum AppThemeMode {
  dark(
    id: 'dark',
    displayName: 'Default Dark',
    subtitle: 'Classic sleek near-black canvas',
    surfaceColor: Color(0xFF0F0F0F),
    cardColor: Color(0xFF272727),
    isDark: true,
  ),
  amoled(
    id: 'amoled',
    displayName: 'AMOLED Pure Black',
    subtitle: 'Deep true black for OLED displays & TV screens',
    surfaceColor: Color(0xFF000000),
    cardColor: Color(0xFF161616),
    isDark: true,
  ),
  dracula(
    id: 'dracula',
    displayName: 'Dracula',
    subtitle: 'Vampire midnight violet palette',
    surfaceColor: Color(0xFF282A36),
    cardColor: Color(0xFF373844),
    isDark: true,
  ),
  silentBlue(
    id: 'silent_blue',
    displayName: 'Silent Blue',
    subtitle: 'Deep oceanic midnight tone',
    surfaceColor: Color(0xFF151A30),
    cardColor: Color(0xFF282F49),
    isDark: true,
  ),
  light(
    id: 'light',
    displayName: 'Light Studio',
    subtitle: 'Clean bright daylight theme',
    surfaceColor: Color(0xFFF8F9FA),
    cardColor: Color(0xFFFFFFFF),
    isDark: false,
  );

  final String id;
  final String displayName;
  final String subtitle;
  final Color surfaceColor;
  final Color cardColor;
  final bool isDark;

  const AppThemeMode({
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.surfaceColor,
    required this.cardColor,
    required this.isDark,
  });

  static AppThemeMode fromId(String? id) {
    if (id == null) return AppThemeMode.dark;
    return AppThemeMode.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppThemeMode.dark,
    );
  }
}

/// Supported accent / primary color overlays in GoPlay.
enum AppAccentColor {
  volt(
    id: 'volt',
    displayName: 'Cyber Lime (Default)',
    color: Color(0xFFC8FF00),
  ),
  cyan(
    id: 'cyan',
    displayName: 'Electric Cyan',
    color: Color(0xFF00D2FF),
  ),
  purple(
    id: 'purple',
    displayName: 'Neon Purple',
    color: Color(0xFF9D4EDD),
  ),
  green(
    id: 'green',
    displayName: 'Emerald Green',
    color: Color(0xFF00E676),
  ),
  red(
    id: 'red',
    displayName: 'Blaze Red',
    color: Color(0xFFFF3B30),
  ),
  orange(
    id: 'orange',
    displayName: 'Sunset Orange',
    color: Color(0xFFFF9500),
  ),
  pink(
    id: 'pink',
    displayName: 'Hot Pink',
    color: Color(0xFFFF2D55),
  );

  final String id;
  final String displayName;
  final Color color;

  const AppAccentColor({
    required this.id,
    required this.displayName,
    required this.color,
  });

  static AppAccentColor fromId(String? id) {
    if (id == null) return AppAccentColor.volt;
    return AppAccentColor.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppAccentColor.volt,
    );
  }
}
