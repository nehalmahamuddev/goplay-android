import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cached native Android TV & hardware capability info queried from MainActivity.
class TvDeviceInfo {
  TvDeviceInfo._();
  static final TvDeviceInfo instance = TvDeviceInfo._();

  static const MethodChannel _deviceChannel = MethodChannel('com.goplay/device');

  bool _initialized = false;
  bool _nativeIsTv = false;
  bool _isLowRam = false;
  int _sdkInt = 0;
  bool _supportsPiP = false;
  bool _canOpenDocument = true;

  bool get initialized => _initialized;
  bool get nativeIsTv => _nativeIsTv;
  bool get isLowRam => _isLowRam;
  int get sdkInt => _sdkInt;
  bool get supportsPiP => _supportsPiP;
  bool get canOpenDocument => _canOpenDocument;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;
    try {
      final info = await _deviceChannel
          .invokeMapMethod<String, dynamic>('getDeviceInfo')
          .timeout(const Duration(milliseconds: 500));
      if (info != null) {
        _nativeIsTv = info['isTv'] == true;
        _isLowRam = info['isLowRam'] == true;
        _sdkInt = (info['sdkInt'] as num?)?.toInt() ?? 0;
        _supportsPiP = info['supportsPiP'] == true;
        _canOpenDocument = info['canOpenDocument'] != false;
      }
    } catch (_) {
      // Non-Android platforms or unit tests without native channel.
    }
  }

  /// Resolves whether TV mode is active given an explicit override ('auto'|'on'|'off')
  /// and optional [BuildContext] directional navigation signals.
  bool resolveIsTv(BuildContext? context, {String override = 'auto'}) {
    if (override == 'on') return true;
    if (override == 'off') return false;
    if (_nativeIsTv) return true;
    if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      return true;
    }
    if (context != null) {
      return MediaQuery.navigationModeOf(context) == NavigationMode.directional;
    }
    return false;
  }
}

/// InheritedWidget providing TV mode and overscan configuration to the widget
/// tree without requiring Riverpod in low-level reusable widgets like [TvFocusable].
class TvScope extends InheritedWidget {
  final bool isTv;
  final bool overscanEnabled;

  const TvScope({
    super.key,
    required this.isTv,
    required this.overscanEnabled,
    required super.child,
  });

  static TvScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvScope>();
  }

  static bool isTvOf(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope.isTv;
    return TvDeviceInfo.instance.resolveIsTv(context);
  }

  static bool overscanEnabledOf(BuildContext context) {
    final scope = maybeOf(context);
    return scope != null && scope.isTv && scope.overscanEnabled;
  }

  /// Standard TV overscan safe inset padding (horizontal 24dp, vertical 16dp)
  /// when running in TV mode with overscan protection enabled.
  static EdgeInsets overscanPaddingOf(BuildContext context) {
    if (!overscanEnabledOf(context)) return EdgeInsets.zero;
    return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
  }

  @override
  bool updateShouldNotify(TvScope oldWidget) {
    return isTv != oldWidget.isTv || overscanEnabled != oldWidget.overscanEnabled;
  }
}
