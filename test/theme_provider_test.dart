import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/app_theme_options.dart';
import 'package:goplay/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppThemeMode & AppAccentColor Options', () {
    test('cyberLime mode has exact configured color tokens', () {
      const mode = AppThemeMode.cyberLime;
      expect(mode.id, 'cyber_lime');
      expect(mode.displayName, 'Cyber Lime');
      expect(mode.surfaceColor, const Color(0xFF141216));
      expect(mode.cardColor, const Color(0xFF1A1A1A));
      expect(mode.onSurfaceVariantColor, const Color(0xFFD4ED41));
      expect(mode.dividerColor, const Color(0x1AD4ED41));
      expect(mode.isDark, isTrue);

      expect(AppThemeMode.fromId('cyber_lime'), AppThemeMode.cyberLime);
      expect(AppThemeMode.fromId('lime'), AppThemeMode.cyberLime);
      expect(AppThemeMode.fromId('neon_lime'), AppThemeMode.cyberLime);
    });

    test('lime accent color has exact configured tokens', () {
      const accent = AppAccentColor.lime;
      expect(accent.id, 'lime');
      expect(accent.displayName, 'Electric Lime');
      expect(accent.color, const Color(0xFFD4ED41));
      expect(accent.onAccentColor, const Color(0xFF141216));

      expect(AppAccentColor.fromId('lime'), AppAccentColor.lime);
      expect(AppAccentColor.fromId('electric_lime'), AppAccentColor.lime);
    });
  });

  group('ThemeSettingsState', () {
    test('defaults have expected initial values', () {
      const state = ThemeSettingsState.defaults;
      expect(state.themeMode, AppThemeMode.dark);
      expect(state.accentColor, AppAccentColor.royalBlue);
      expect(state.isUsingCustomTheme, isFalse);
      expect(state.isDark, isTrue);
      expect(state.isAmoled, isFalse);
      expect(state.surfaceColor, const Color(0xFF000000));
      expect(state.cardColor, const Color(0xFF161616));
      expect(state.bottomNavColor, const Color(0xFF161616));
      expect(state.activeAccentColor, const Color(0xFF3D50FA));
    });

    test('value equality and copyWith work as expected', () {
      const a = ThemeSettingsState.defaults;
      final b = a.copyWith(themeMode: AppThemeMode.cyberLime, isUsingCustomTheme: true);

      expect(a == b, isFalse);
      expect(b.themeMode, AppThemeMode.cyberLime);
      expect(b.surfaceColor, const Color(0xFF141216));
      expect(b.cardColor, const Color(0xFF1A1A1A));
      expect(b.isUsingCustomTheme, isTrue);

      final c = b.copyWith();
      expect(b == c, isTrue);
      expect(b.hashCode == c.hashCode, isTrue);
    });
  });

  group('ThemeSettingsNotifier & Riverpod Providers', () {
    test('builds initial state and updates themeMode / accentColor reactively', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial state
      expect(container.read(themeSettingsProvider), ThemeSettingsState.defaults);
      expect(container.read(activeThemeModeProvider), AppThemeMode.dark);
      expect(container.read(activeAccentColorProvider), AppAccentColor.royalBlue);
      expect(container.read(isCustomThemeProvider), isFalse);

      final notifier = container.read(themeSettingsProvider.notifier);

      // Update themeMode to cyberLime
      await notifier.setThemeMode(AppThemeMode.cyberLime);
      expect(container.read(activeThemeModeProvider), AppThemeMode.cyberLime);
      expect(container.read(isCustomThemeProvider), isTrue);

      // Update accentColor to lime
      await notifier.setAccentColor(AppAccentColor.lime);
      expect(container.read(activeAccentColorProvider), AppAccentColor.lime);

      // Reset to cloud defaults
      await notifier.resetToCloudDefault();
      expect(container.read(themeSettingsProvider), ThemeSettingsState.defaults);
      expect(container.read(isCustomThemeProvider), isFalse);
    });
  });
}
