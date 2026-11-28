import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants.dart';
import '../services/tv_service.dart';

T _readSetting<T>(String key, T fallback) {
  try {
    if (Hive.isBoxOpen(AppConstants.settingsBox)) {
      final val = Hive.box(AppConstants.settingsBox).get(key);
      if (val is T) return val;
    }
  } catch (_) {}
  return fallback;
}

Future<void> _writeSetting(String key, Object? value) async {
  try {
    if (Hive.isBoxOpen(AppConstants.settingsBox)) {
      await Hive.box(AppConstants.settingsBox).put(key, value);
    }
  } catch (_) {}
}

class TvModeOverrideNotifier extends Notifier<String> {
  @override
  String build() => _readSetting<String>(AppConstants.tvModeOverrideKey, 'auto');

  Future<void> setOverride(String value) async {
    state = value;
    await _writeSetting(AppConstants.tvModeOverrideKey, value);
  }
}

final tvModeOverrideProvider =
    NotifierProvider<TvModeOverrideNotifier, String>(TvModeOverrideNotifier.new);

class TvOverscanNotifier extends Notifier<bool> {
  @override
  bool build() => _readSetting<bool>(AppConstants.tvOverscanPaddingKey, true);

  Future<void> setEnabled(bool value) async {
    state = value;
    await _writeSetting(AppConstants.tvOverscanPaddingKey, value);
  }
}

final tvOverscanEnabledProvider =
    NotifierProvider<TvOverscanNotifier, bool>(TvOverscanNotifier.new);

class HwAccelerationNotifier extends Notifier<bool> {
  @override
  bool build() => _readSetting<bool>(AppConstants.hwAccelerationKey, true);

  Future<void> setEnabled(bool value) async {
    state = value;
    await _writeSetting(AppConstants.hwAccelerationKey, value);
  }
}

final hwAccelerationProvider =
    NotifierProvider<HwAccelerationNotifier, bool>(HwAccelerationNotifier.new);

class UseSurfaceViewNotifier extends Notifier<bool> {
  @override
  bool build() => _readSetting<bool>(AppConstants.useSurfaceViewKey, false);

  Future<void> setEnabled(bool value) async {
    state = value;
    await _writeSetting(AppConstants.useSurfaceViewKey, value);
  }
}

final useSurfaceViewProvider =
    NotifierProvider<UseSurfaceViewNotifier, bool>(UseSurfaceViewNotifier.new);

class BackgroundAudioNotifier extends Notifier<bool> {
  @override
  bool build() => _readSetting<bool>(AppConstants.backgroundAudioKey, false);

  Future<void> setEnabled(bool value) async {
    state = value;
    await _writeSetting(AppConstants.backgroundAudioKey, value);
  }
}

final backgroundAudioProvider =
    NotifierProvider<BackgroundAudioNotifier, bool>(BackgroundAudioNotifier.new);

class AutoPlayOnOpenNotifier extends Notifier<bool> {
  @override
  bool build() => _readSetting<bool>(AppConstants.autoPlayOnOpenKey, true);

  Future<void> setEnabled(bool value) async {
    state = value;
    await _writeSetting(AppConstants.autoPlayOnOpenKey, value);
  }
}

final autoPlayOnOpenProvider =
    NotifierProvider<AutoPlayOnOpenNotifier, bool>(AutoPlayOnOpenNotifier.new);

/// Resolved TV mode based on native detection + user override.
/// Widget trees can also listen to [TvScope.isTvOf(context)] which additionally
/// reacts to [MediaQuery.navigationModeOf] and [FocusHighlightMode].
final isTvModeProvider = Provider<bool>((ref) {
  final override = ref.watch(tvModeOverrideProvider);
  return TvDeviceInfo.instance.resolveIsTv(null, override: override);
});

/// Helper to read TV mode inside a [BuildContext] using both [TvScope] and native info.
bool isTvContext(BuildContext context, {String override = 'auto'}) {
  final scope = TvScope.maybeOf(context);
  if (scope != null && override == 'auto') {
    return scope.isTv;
  }
  return TvDeviceInfo.instance.resolveIsTv(context, override: override);
}
