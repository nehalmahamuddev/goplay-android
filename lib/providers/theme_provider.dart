import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/app_theme_options.dart';
import 'app_providers.dart';

/// State holding user-customized theme preferences.
@immutable
class ThemeSettingsState {
  final AppThemeMode themeMode;
  final AppAccentColor accentColor;
  final bool isUsingCustomTheme;

  const ThemeSettingsState({
    required this.themeMode,
    required this.accentColor,
    required this.isUsingCustomTheme,
  });

  ThemeSettingsState copyWith({
    AppThemeMode? themeMode,
    AppAccentColor? accentColor,
    bool? isUsingCustomTheme,
  }) {
    return ThemeSettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      isUsingCustomTheme: isUsingCustomTheme ?? this.isUsingCustomTheme,
    );
  }
}

/// Notifier that manages user theme customizations with Hive persistence.
class ThemeSettingsNotifier extends Notifier<ThemeSettingsState> {
  @override
  ThemeSettingsState build() {
    try {
      final box = Hive.isBoxOpen(AppConstants.settingsBox)
          ? Hive.box(AppConstants.settingsBox)
          : null;

      if (box != null) {
        final savedThemeMode = box.get('user_theme_mode') as String?;
        final savedAccentColor = box.get('user_accent_color') as String?;
        final isCustom = box.get('user_is_custom_theme', defaultValue: false) as bool;

        return ThemeSettingsState(
          themeMode: AppThemeMode.fromId(savedThemeMode),
          accentColor: AppAccentColor.fromId(savedAccentColor),
          isUsingCustomTheme: isCustom,
        );
      }
    } catch (_) {}

    return const ThemeSettingsState(
      themeMode: AppThemeMode.dark,
      accentColor: AppAccentColor.volt,
      isUsingCustomTheme: false,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode, isUsingCustomTheme: true);
    await _persist();
  }

  Future<void> setAccentColor(AppAccentColor accent) async {
    state = state.copyWith(accentColor: accent, isUsingCustomTheme: true);
    await _persist();
  }

  Future<void> resetToCloudDefault() async {
    state = const ThemeSettingsState(
      themeMode: AppThemeMode.dark,
      accentColor: AppAccentColor.volt,
      isUsingCustomTheme: false,
    );

    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        final box = Hive.box(AppConstants.settingsBox);
        await box.delete('user_theme_mode');
        await box.delete('user_accent_color');
        await box.put('user_is_custom_theme', false);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        final box = Hive.box(AppConstants.settingsBox);
        await box.put('user_theme_mode', state.themeMode.id);
        await box.put('user_accent_color', state.accentColor.id);
        await box.put('user_is_custom_theme', true);
      }
    } catch (_) {}
  }
}

/// Provider for user theme settings state.
final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettingsState>(
  ThemeSettingsNotifier.new,
);

/// Computes the effective active ThemeData:
/// Returns custom user theme if user customized it, otherwise falls back to remote cloud UI theme.
final activeAppThemeProvider = Provider<ThemeData>((ref) {
  final userTheme = ref.watch(themeSettingsProvider);
  if (userTheme.isUsingCustomTheme) {
    return GoPlayTheme.buildCustomUserTheme(userTheme.themeMode, userTheme.accentColor);
  }
  // Otherwise use the default / Supabase synced cloud theme
  final uiConfig = ref.watch(uiConfigProvider);
  return GoPlayTheme.buildDynamicTheme(uiConfig.theme);
});
