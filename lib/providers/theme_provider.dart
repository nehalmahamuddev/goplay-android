import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/app_theme_options.dart';
import 'app_providers.dart';

// ─── Theme Persistence Contract & Keys ───────────────────────────────────────

abstract final class _ThemeStorageKeys {
  static const String themeMode = 'user_theme_mode';
  static const String accentColor = 'user_accent_color';
  static const String isCustomTheme = 'user_is_custom_theme';
}

/// Dedicated, fail-safe storage service encapsulating Hive persistence
/// for user theme configurations.
@immutable
final class ThemePersistenceService {
  const ThemePersistenceService();

  Box? _getSettingsBox() {
    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        return Hive.box(AppConstants.settingsBox);
      }
    } catch (e) {
      debugPrint('[ThemePersistenceService] Box access warning: $e');
    }
    return null;
  }

  /// Loads saved theme state synchronously from the local Hive settings box.
  ThemeSettingsState loadInitialState() {
    final box = _getSettingsBox();
    if (box != null) {
      try {
        final savedThemeId = box.get(_ThemeStorageKeys.themeMode) as String?;
        final savedAccentId = box.get(_ThemeStorageKeys.accentColor) as String?;
        final isCustom = box.get(_ThemeStorageKeys.isCustomTheme, defaultValue: false) as bool;

        return ThemeSettingsState(
          themeMode: AppThemeMode.fromId(savedThemeId),
          accentColor: AppAccentColor.fromId(savedAccentId),
          isUsingCustomTheme: isCustom,
        );
      } catch (e) {
        debugPrint('[ThemePersistenceService] Failed to parse cached theme state: $e');
      }
    }
    return ThemeSettingsState.defaults;
  }

  /// Asynchronously persists the user theme state to disk.
  Future<void> persist(ThemeSettingsState state) async {
    final box = _getSettingsBox();
    if (box == null) return;

    try {
      await Future.wait([
        box.put(_ThemeStorageKeys.themeMode, state.themeMode.id),
        box.put(_ThemeStorageKeys.accentColor, state.accentColor.id),
        box.put(_ThemeStorageKeys.isCustomTheme, state.isUsingCustomTheme),
      ]);
    } catch (e) {
      debugPrint('[ThemePersistenceService] Failed to persist theme state: $e');
    }
  }

  /// Clears user theme overrides and resets persistence to cloud defaults.
  Future<void> clearCustomPreferences() async {
    final box = _getSettingsBox();
    if (box == null) return;

    try {
      await Future.wait([
        box.delete(_ThemeStorageKeys.themeMode),
        box.delete(_ThemeStorageKeys.accentColor),
        box.put(_ThemeStorageKeys.isCustomTheme, false),
      ]);
    } catch (e) {
      debugPrint('[ThemePersistenceService] Failed to reset custom theme keys: $e');
    }
  }
}

// ─── Theme Settings State ───────────────────────────────────────────────────

/// Immutable state holding user-customized theme preferences.
///
/// Features strict value equality to prevent unnecessary Riverpod widget rebuilds.
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

  /// Factory baseline default state (Upstream Dark + Royal Blue).
  static const ThemeSettingsState defaults = ThemeSettingsState(
    themeMode: AppThemeMode.dark,
    accentColor: AppAccentColor.royalBlue,
    isUsingCustomTheme: false,
  );

  /// Convenience getters for UI components
  bool get isDark => themeMode.isDark;
  bool get isAmoled => themeMode == AppThemeMode.amoled;
  Color get surfaceColor => themeMode.surfaceColor;
  Color get cardColor => themeMode.cardColor;
  Color get bottomNavColor => themeMode.bottomNavColor;
  Color get activeAccentColor => accentColor.color;

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeSettingsState &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          accentColor == other.accentColor &&
          isUsingCustomTheme == other.isUsingCustomTheme;

  @override
  int get hashCode => Object.hash(themeMode, accentColor, isUsingCustomTheme);

  @override
  String toString() =>
      'ThemeSettingsState(mode: ${themeMode.id}, accent: ${accentColor.id}, isCustom: $isUsingCustomTheme)';
}

// ─── Theme Settings Notifier ────────────────────────────────────────────────

/// Manages user theme customizations with zero-lag UI feedback and background persistence.
class ThemeSettingsNotifier extends Notifier<ThemeSettingsState> {
  final ThemePersistenceService _persistence = const ThemePersistenceService();

  @override
  ThemeSettingsState build() {
    return _persistence.loadInitialState();
  }

  /// Sets the active background theme mode (e.g. Upstream Dark, AMOLED, Dracula)
  Future<void> setThemeMode(AppThemeMode mode) async {
    if (state.themeMode == mode && state.isUsingCustomTheme) return;

    state = state.copyWith(themeMode: mode, isUsingCustomTheme: true);
    await _persistence.persist(state);
  }

  /// Sets the active brand accent color (e.g. Royal Blue, Cyber Lime, Neon Crimson)
  Future<void> setAccentColor(AppAccentColor accent) async {
    if (state.accentColor == accent && state.isUsingCustomTheme) return;

    state = state.copyWith(accentColor: accent, isUsingCustomTheme: true);
    await _persistence.persist(state);
  }

  /// Resets user custom overrides and returns to cloud-synchronized theme defaults.
  Future<void> resetToCloudDefault() async {
    state = ThemeSettingsState.defaults;
    await _persistence.clearCustomPreferences();
  }
}

// ─── Riverpod Providers ─────────────────────────────────────────────────────

/// Primary notifier provider for user theme preferences.
final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettingsState>(
  ThemeSettingsNotifier.new,
);

/// Scoped selector provider for the active [AppThemeMode].
/// Subscribing to this provider prevents rebuilds when accent color changes.
final activeThemeModeProvider = Provider<AppThemeMode>((ref) {
  return ref.watch(themeSettingsProvider.select((s) => s.themeMode));
});

/// Scoped selector provider for the active [AppAccentColor].
/// Subscribing to this provider prevents rebuilds when background theme mode changes.
final activeAccentColorProvider = Provider<AppAccentColor>((ref) {
  return ref.watch(themeSettingsProvider.select((s) => s.accentColor));
});

/// Scoped selector provider checking if user has local custom overrides.
final isCustomThemeProvider = Provider<bool>((ref) {
  return ref.watch(themeSettingsProvider.select((s) => s.isUsingCustomTheme));
});

/// Computes the effective active Material 3 [ThemeData]:
/// - Returns user-chosen theme when [isUsingCustomTheme] is true.
/// - Otherwise falls back to cloud-synchronized [ThemeConfig] from Supabase.
final activeAppThemeProvider = Provider<ThemeData>((ref) {
  final userTheme = ref.watch(themeSettingsProvider);

  if (userTheme.isUsingCustomTheme) {
    return GoPlayTheme.buildCustomUserTheme(
      userTheme.themeMode,
      userTheme.accentColor,
    );
  }

  // Cloud synced theme fallback
  final uiConfig = ref.watch(uiConfigProvider);
  return GoPlayTheme.buildDynamicTheme(uiConfig.theme);
});
