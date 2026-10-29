import 'package:flutter/material.dart';

import '../core/typography.dart';

/// Defines the primary canvas and container surface palettes supported by GoPlay.
///
/// Each preset supplies semantic surface colors, border tokens, and text contrast
/// guarantees tailored for OLED, Android TV, and handheld displays.
enum AppThemeMode {
  /// Default Upstream normal dark theme: Charcoal canvas (#111111) with dark card containers (#161616).
  dark(
    id: 'dark',
    displayName: 'Upstream Dark (Default)',
    subtitle: 'Charcoal canvas (#111111) with #161616 card containers',
    surfaceColor: Color(0xFF111111),
    cardColor: Color(0xFF161616),
    surfaceContainerHigh: Color(0xFF1C1C20),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x1AFFFFFF),
    onSurfaceColor: Color(0xFFE9EAEE),
    onSurfaceVariantColor: Color(0xFF9BA0A4),
    onSurfaceMutedColor: Color(0xFF9BA0A6),
    isDark: true,
  ),

  /// Pure AMOLED blackout: 0% light emission on canvas with #121212 card containers for OLED battery savings.
  amoled(
    id: 'amoled',
    displayName: 'AMOLED Blackout',
    subtitle: 'Pure black (#000000) canvas with #121212 card containers',
    surfaceColor: Color(0xFF000000),
    cardColor: Color(0xFF121212),
    surfaceContainerHigh: Color(0xFF181818),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x20FFFFFF),
    onSurfaceColor: Color(0xFFFFFFFF),
    onSurfaceVariantColor: Color(0xFFAAAAAA),
    onSurfaceMutedColor: Color(0xFF6E6E6E),
    isDark: true,
  ),

  /// Studio Gray: Gentle charcoal near-black surface.
  gray(
    id: 'gray',
    displayName: 'Studio Gray',
    subtitle: 'Smooth charcoal near-black surface with refined card layers',
    surfaceColor: Color(0xFF0F0F0F),
    cardColor: Color(0xFF1B1B1B),
    surfaceContainerHigh: Color(0xFF242424),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x15FFFFFF),
    onSurfaceColor: Color(0xFFECECEC),
    onSurfaceVariantColor: Color(0xFFA0A0A0),
    onSurfaceMutedColor: Color(0xFF707070),
    isDark: true,
  ),

  /// Dracula: Midnight purple-violet palette inspired by classic code editor aesthetics.
  dracula(
    id: 'dracula',
    displayName: 'Dracula',
    subtitle: 'Vampire midnight violet palette with rich contrasting cards',
    surfaceColor: Color(0xFF282A36),
    cardColor: Color(0xFF343746),
    surfaceContainerHigh: Color(0xFF44475A),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x226272A4),
    onSurfaceColor: Color(0xFFF8F8F2),
    onSurfaceVariantColor: Color(0xFFBD93F9),
    onSurfaceMutedColor: Color(0xFF6272A4),
    isDark: true,
  ),

  /// Silent Blue: Deep oceanic midnight tones for a calming viewing experience.
  silentBlue(
    id: 'silent_blue',
    displayName: 'Silent Blue',
    subtitle: 'Deep oceanic midnight tone with elevated navy cards',
    surfaceColor: Color(0xFF0E1320),
    cardColor: Color(0xFF172033),
    surfaceContainerHigh: Color(0xFF202C45),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x1A5C7CFA),
    onSurfaceColor: Color(0xFFE5EDF7),
    onSurfaceVariantColor: Color(0xFF8FA7C9),
    onSurfaceMutedColor: Color(0xFF5A7196),
    isDark: true,
  ),

  /// Light Studio: Clean high-contrast daylight theme.
  light(
    id: 'light',
    displayName: 'Light Studio',
    subtitle: 'Clean bright daylight theme with soft elevation',
    surfaceColor: Color(0xFFF8F9FA),
    cardColor: Color(0xFFFFFFFF),
    surfaceContainerHigh: Color(0xFFECEFF1),
    cardBorderColor: Colors.transparent,
    dividerColor: Color(0x0F000000),
    onSurfaceColor: Color(0xFF111417),
    onSurfaceVariantColor: Color(0xFF4B4F58),
    onSurfaceMutedColor: Color(0xFF6B6F78),
    isDark: false,
  );

  /// Unique serialization ID persisted in local settings.
  final String id;

  /// User-facing title shown in the Settings theme picker.
  final String displayName;

  /// Subtitle explaining the visual identity of this theme.
  final String subtitle;

  /// Primary canvas and scaffold background color.
  final Color surfaceColor;

  /// Primary surface container color for cards, dialogs, and panels (#161616 on default).
  final Color cardColor;

  /// Slightly elevated container surface for hovering, floating chips, or active states.
  final Color surfaceContainerHigh;

  /// Hairline outline border color for cards and chips.
  final Color cardBorderColor;

  /// Divider and line separator color.
  final Color dividerColor;

  /// Primary on-surface typography color.
  final Color onSurfaceColor;

  /// Secondary typography color (metadata, subheadings).
  final Color onSurfaceVariantColor;

  /// Muted typography color (timestamps, hints, disabled labels).
  final Color onSurfaceMutedColor;

  /// Whether this is a dark or light palette.
  final bool isDark;

  const AppThemeMode({
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.surfaceColor,
    required this.cardColor,
    required this.surfaceContainerHigh,
    required this.cardBorderColor,
    required this.dividerColor,
    required this.onSurfaceColor,
    required this.onSurfaceVariantColor,
    required this.onSurfaceMutedColor,
    required this.isDark,
  });

  /// Resolves an [AppThemeMode] by [id], falling back to [AppThemeMode.dark].
  static AppThemeMode fromId(String? id) {
    if (id == null) return AppThemeMode.dark;
    return AppThemeMode.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppThemeMode.dark,
    );
  }

  /// Builds a complete Material 3 [ColorScheme] paired with an [AppAccentColor].
  ColorScheme toColorScheme(AppAccentColor accent) {
    final primary = accent.color;
    final onPrimary = accent.onAccentColor;

    return ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: 0.18),
      onPrimaryContainer: primary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surfaceColor,
      surfaceContainerLowest: surfaceColor,
      surfaceContainerLow: surfaceColor,
      surfaceContainer: cardColor,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHigh,
      onSurface: onSurfaceColor,
      onSurfaceVariant: onSurfaceVariantColor,
      error: const Color(0xFFFF453A),
      onError: Colors.white,
      outline: cardBorderColor,
      outlineVariant: dividerColor,
      inverseSurface: isDark ? const Color(0xFFF8F9FA) : const Color(0xFF121212),
      onInverseSurface: isDark ? const Color(0xFF111417) : const Color(0xFFE9EAEE),
    );
  }

  /// Builds a fully configured [ThemeData] ready for MaterialApp.
  ThemeData toThemeData(AppAccentColor accent) {
    final scheme = toColorScheme(accent);

    final textTheme = GoPlayType.textTheme().apply(
      fontFamily: GoPlayType.family,
      bodyColor: onSurfaceColor,
      displayColor: onSurfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaceColor,
      canvasColor: surfaceColor,
      cardColor: cardColor,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(color: onSurfaceVariantColor),
        bodySmall: textTheme.bodySmall?.copyWith(color: onSurfaceMutedColor),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: onSurfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoPlayType.title.copyWith(color: onSurfaceColor),
        iconTheme: IconThemeData(color: onSurfaceColor, size: 22),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: scheme.primary.withValues(alpha: 0.22),
        disabledColor: cardColor,
        labelStyle: GoPlayType.inter(
          fontSize: GoPlayType.sm,
          fontWeight: FontWeight.w500,
          color: onSurfaceColor,
        ),
        secondaryLabelStyle: GoPlayType.inter(
          fontSize: GoPlayType.sm,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        hintStyle: GoPlayType.inter(color: onSurfaceMutedColor),
        labelStyle: GoPlayType.inter(color: onSurfaceVariantColor),
        prefixIconColor: onSurfaceVariantColor,
        suffixIconColor: onSurfaceVariantColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoPlayType.inter(fontWeight: FontWeight.w700, fontSize: GoPlayType.base),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoPlayType.inter(fontWeight: FontWeight.w700, fontSize: GoPlayType.base),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: scheme.primary,
        unselectedItemColor: onSurfaceMutedColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoPlayType.labelSmall.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoPlayType.labelSmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: onSurfaceMutedColor,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// Defines the accent and brand highlight colors supported in GoPlay.
enum AppAccentColor {
  /// Openstream signature Electric Royal Blue (#3D50FA).
  royalBlue(
    id: 'royal_blue',
    displayName: 'Royal Blue (Default)',
    color: Color(0xFF3D50FA),
    onAccentColor: Colors.white,
  ),

  /// Cyber Lime / Volt high-visibility neon (#C8FF00).
  volt(
    id: 'volt',
    displayName: 'Cyber Lime / Volt',
    color: Color(0xFFC8FF00),
    onAccentColor: Color(0xFF0F0F0F),
  ),

  /// Electric Cyan (#00D2FF).
  cyan(
    id: 'cyan',
    displayName: 'Electric Cyan',
    color: Color(0xFF00D2FF),
    onAccentColor: Color(0xFF002233),
  ),

  /// Neon Purple (#9D4EDD).
  purple(
    id: 'purple',
    displayName: 'Neon Purple',
    color: Color(0xFF9D4EDD),
    onAccentColor: Colors.white,
  ),

  /// Emerald Green (#00E676).
  green(
    id: 'green',
    displayName: 'Emerald Green',
    color: Color(0xFF00E676),
    onAccentColor: Color(0xFF002914),
  ),

  /// Blaze Red (#FF3B30).
  red(
    id: 'red',
    displayName: 'Blaze Red',
    color: Color(0xFFFF3B30),
    onAccentColor: Colors.white,
  ),

  /// Sunset Orange (#FF9500).
  orange(
    id: 'orange',
    displayName: 'Sunset Orange',
    color: Color(0xFFFF9500),
    onAccentColor: Color(0xFF291400),
  ),

  /// Hot Pink (#FF2D55).
  pink(
    id: 'pink',
    displayName: 'Hot Pink',
    color: Color(0xFFFF2D55),
    onAccentColor: Colors.white,
  );

  /// Unique serialization ID.
  final String id;

  /// User-facing display name.
  final String displayName;

  /// The concrete primary accent [Color].
  final Color color;

  /// High-contrast foreground text color when rendered on top of [color].
  final Color onAccentColor;

  const AppAccentColor({
    required this.id,
    required this.displayName,
    required this.color,
    required this.onAccentColor,
  });

  /// Resolves an [AppAccentColor] by [id], falling back to [AppAccentColor.royalBlue].
  static AppAccentColor fromId(String? id) {
    if (id == null) return AppAccentColor.royalBlue;
    return AppAccentColor.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppAccentColor.royalBlue,
    );
  }
}
