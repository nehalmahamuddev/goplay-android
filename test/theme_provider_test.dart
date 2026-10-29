import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/app_theme_options.dart';
import 'package:goplay/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final b = a.copyWith(themeMode: AppThemeMode.amoled, isUsingCustomTheme: true);

      expect(a == b, isFalse);
      expect(b.themeMode, AppThemeMode.amoled);
      expect(b.isAmoled, isTrue);
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

      // Update themeMode
      await notifier.setThemeMode(AppThemeMode.amoled);
      expect(container.read(activeThemeModeProvider), AppThemeMode.amoled);
      expect(container.read(isCustomThemeProvider), isTrue);

      // Update accentColor
      await notifier.setAccentColor(AppAccentColor.volt);
      expect(container.read(activeAccentColorProvider), AppAccentColor.volt);

      // Reset to cloud defaults
      await notifier.resetToCloudDefault();
      expect(container.read(themeSettingsProvider), ThemeSettingsState.defaults);
      expect(container.read(isCustomThemeProvider), isFalse);
    });
  });
}
