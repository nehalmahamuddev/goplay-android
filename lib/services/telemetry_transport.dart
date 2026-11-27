import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

/// Resolved static identity of the current device and build.
class DeviceIdentityInfo {
  final String deviceId;
  final String deviceName;
  final String osVersion;
  final String appVersion;
  final bool isTvDevice;

  const DeviceIdentityInfo({
    required this.deviceId,
    required this.deviceName,
    required this.osVersion,
    required this.appVersion,
    required this.isTvDevice,
  });
}

/// Seam isolating device identity lookup and persistence from telemetry logic.
abstract class DeviceIdentityAdapter {
  Future<DeviceIdentityInfo> resolveIdentity();
}

/// Production device identity adapter using `device_info_plus`, `package_info_plus`,
/// and Hive `settingsBox`.
class PlatformDeviceIdentityAdapter implements DeviceIdentityAdapter {
  const PlatformDeviceIdentityAdapter();

  @override
  Future<DeviceIdentityInfo> resolveIdentity() async {
    Box? box;
    try {
      if (Hive.isBoxOpen(AppConstants.settingsBox)) {
        box = Hive.box(AppConstants.settingsBox);
      }
    } catch (_) {}

    String? deviceId = box?.get('analytics_device_id') as String?;
    String? deviceName = box?.get('analytics_device_name') as String?;
    String? osVersion = box?.get('analytics_os_version') as String?;
    bool isTvDevice = box?.get('analytics_is_tv') as bool? ?? false;

    if (deviceId == null || deviceName == null || osVersion == null) {
      final deviceInfo = DeviceInfoPlugin();

      if (kIsWeb) {
        deviceId = _generateUuid();
        deviceName = 'Web Browser';
        osVersion = 'Web';
        isTvDevice = false;
      } else if (Platform.isAndroid) {
        try {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id.isNotEmpty ? androidInfo.id : _generateUuid();
          deviceName = '${androidInfo.brand} ${androidInfo.model}';
          osVersion = 'Android ${androidInfo.version.release}';
          isTvDevice = androidInfo.systemFeatures.contains('android.software.leanback');
        } catch (e) {
          debugPrint('Failed to get Android device info: $e');
          deviceId = _generateUuid();
          deviceName = 'Android TV Device';
          osVersion = 'Android TV';
          isTvDevice = true;
        }
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? _generateUuid();
        deviceName = iosInfo.name;
        osVersion = 'iOS ${iosInfo.systemVersion}';
        isTvDevice = false;
      } else {
        deviceId = _generateUuid();
        deviceName = Platform.operatingSystem;
        osVersion = Platform.operatingSystemVersion;
        isTvDevice = false;
      }

      if (box != null) {
        await box.put('analytics_device_id', deviceId);
        await box.put('analytics_device_name', deviceName);
        await box.put('analytics_os_version', osVersion);
        await box.put('analytics_is_tv', isTvDevice);
      }
    }

    String appVersion = AppConstants.appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
    } catch (_) {}

    return DeviceIdentityInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      osVersion: osVersion,
      appVersion: appVersion,
      isTvDevice: isTvDevice,
    );
  }

  static String _generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
      if (i == 3 || i == 5 || i == 7 || i == 9) {
        buffer.write('-');
      }
    }
    return buffer.toString();
  }
}

/// Seam isolating external analytics (Firebase GA4) and backend presence/trending
/// RPC calls from telemetry orchestration and timing logic.
abstract class TelemetryTransport {
  Future<void> setUserId(String userId);

  Future<void> setUserProperty(String name, String value);

  Future<void> logScreenView({
    required String screenName,
    required String screenClass,
  });

  Future<void> logEvent(String name, Map<String, Object> parameters);

  Future<void> logViewItem({
    required String itemId,
    required String itemName,
    required String itemCategory,
    required String itemBrand,
  });

  Future<void> logSearch({
    required String searchTerm,
    required int resultCount,
  });

  Future<void> upsertPresence(
    Map<String, dynamic> payload, {
    bool fireAndForget = false,
  });

  Future<void> recordVerifiedPlayback({
    required String channelId,
    required String deviceId,
    String? channelName,
    String? categoryId,
  });
}

/// Production telemetry adapter delegating to Firebase Analytics and Supabase.
class FirebaseSupabaseTelemetryTransport implements TelemetryTransport {
  const FirebaseSupabaseTelemetryTransport();

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  @override
  Future<void> setUserId(String userId) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.setUserId(id: userId);
    } catch (_) {}
  }

  @override
  Future<void> setUserProperty(String name, String value) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  @override
  Future<void> logScreenView({
    required String screenName,
    required String screenClass,
  }) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      );
    } catch (_) {}
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  @override
  Future<void> logViewItem({
    required String itemId,
    required String itemName,
    required String itemCategory,
    required String itemBrand,
  }) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.logViewItem(
        items: [
          AnalyticsEventItem(
            itemId: itemId,
            itemName: itemName,
            itemCategory: itemCategory,
            itemBrand: itemBrand,
          ),
        ],
      );
    } catch (_) {}
  }

  @override
  Future<void> logSearch({
    required String searchTerm,
    required int resultCount,
  }) async {
    if (!_firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.logSearch(
        searchTerm: searchTerm,
        parameters: {'result_count': resultCount},
      );
    } catch (_) {}
  }

  @override
  Future<void> upsertPresence(
    Map<String, dynamic> payload, {
    bool fireAndForget = false,
  }) async {
    try {
      final client = Supabase.instance.client;
      if (fireAndForget) {
        unawaited(
          client
              .from('user_presence')
              .upsert(payload, onConflict: 'device_id')
              .then((_) {})
              .catchError((_) {}),
        );
      } else {
        await client.from('user_presence').upsert(payload, onConflict: 'device_id');
      }
    } catch (e) {
      debugPrint('Failed to send presence heartbeat: $e');
    }
  }

  @override
  Future<void> recordVerifiedPlayback({
    required String channelId,
    required String deviceId,
    String? channelName,
    String? categoryId,
  }) async {
    try {
      final client = Supabase.instance.client;
      await client.rpc('record_channel_playback', params: {
        'p_channel_id': channelId,
        'p_device_id': deviceId,
        if (channelName != null && channelName.isNotEmpty) 'p_channel_name': channelName,
        if (categoryId != null && categoryId.isNotEmpty) 'p_category_id': categoryId,
      });
      debugPrint('Recorded verified playback for dynamic trending: $channelId');
    } catch (e) {
      debugPrint('Failed to record channel playback for trending: $e');
    }
  }
}
