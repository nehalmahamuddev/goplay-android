import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:dio/dio.dart';
import 'package:goplay/core/constants.dart';
import 'package:goplay/models/update_info.dart';
import 'package:goplay/providers/update_notifier.dart';
import 'package:goplay/repositories/update_repository.dart';
import 'package:goplay/services/update_service.dart';

class MockUpdateService extends UpdateService {
  int fetchCallCount = 0;
  UpdateInfo? stubInfo;

  MockUpdateService() : super(Dio());

  @override
  Future<String> getCurrentVersion() async => '2.3.0';

  @override
  Future<UpdateInfo> fetchLatestRelease() async {
    fetchCallCount++;
    return stubInfo ??
        UpdateInfo(
          latestVersion: '2.4.0',
          minimumVersion: '1.0.0',
          forceUpdate: false,
          apkUrl: 'https://example.com/goplay-2.4.0.apk',
          releaseNotes: ['New features'],
          publishedAt: DateTime.now(),
        );
  }
}

void main() {
  late Directory tempDir;
  late Box settingsBox;
  late MockUpdateService mockService;
  late UpdateRepository repository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_update_test_');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox(AppConstants.settingsBox);
    mockService = MockUpdateService();
    repository = UpdateRepository(mockService);
  });

  tearDown(() async {
    await settingsBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UpdateRepository - shouldCheckForUpdate', () {
    test('returns true on cold start when no timestamp exists', () {
      expect(repository.shouldCheckForUpdate(), isTrue);
    });

    test('returns false when auto_check_updates is disabled in settings', () async {
      await settingsBox.put('auto_check_updates', false);
      expect(repository.shouldCheckForUpdate(), isFalse);
    });

    test('returns false when checked less than 5 minutes ago (safety cooldown)', () async {
      final twoMinutesAgo = DateTime.now().subtract(const Duration(minutes: 2));
      await settingsBox.put('last_update_check_time', twoMinutesAgo.toIso8601String());

      expect(repository.shouldCheckForUpdate(), isFalse);
    });

    test('returns true when checked 6 minutes ago (exceeds 5-minute cooldown)', () async {
      final sixMinutesAgo = DateTime.now().subtract(const Duration(minutes: 6));
      await settingsBox.put('last_update_check_time', sixMinutesAgo.toIso8601String());

      expect(repository.shouldCheckForUpdate(), isTrue);
    });
  });

  group('UpdateRepository - checkForUpdates', () {
    test('fetches from network when cooldown has elapsed', () async {
      final result = await repository.checkForUpdates(forceCheck: false);

      expect(mockService.fetchCallCount, equals(1));
      expect(result.isUpdateAvailable, isTrue);
      expect(result.updateInfo?.latestVersion, equals('2.4.0'));
      expect(repository.getLastCheckTimestamp(), isNotNull);
    });

    test('forceCheck bypasses 5-minute safety cooldown and auto_check_updates toggle', () async {
      await settingsBox.put('auto_check_updates', false);
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
      await settingsBox.put('last_update_check_time', oneMinuteAgo.toIso8601String());

      // Should skip when not forced
      final silentResult = await repository.checkForUpdates(forceCheck: false);
      expect(mockService.fetchCallCount, equals(0));
      expect(silentResult.isUpdateAvailable, isFalse);

      // Should execute when forced (manual check from Settings)
      final forcedResult = await repository.checkForUpdates(forceCheck: true);
      expect(mockService.fetchCallCount, equals(1));
      expect(forcedResult.isUpdateAvailable, isTrue);
    });

    test('isStartup bypasses cooldown on fresh app launch', () async {
      final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
      await settingsBox.put('last_update_check_time', oneMinuteAgo.toIso8601String());

      // Normal background check would be skipped by cooldown
      final regularResult = await repository.checkForUpdates(forceCheck: false, isStartup: false);
      expect(mockService.fetchCallCount, equals(0));
      expect(regularResult.isUpdateAvailable, isFalse);

      // isStartup triggers immediate check
      final startupResult = await repository.checkForUpdates(forceCheck: false, isStartup: true);
      expect(mockService.fetchCallCount, equals(1));
      expect(startupResult.isUpdateAvailable, isTrue);
    });
  });

  group('UpdateInfo - Direct GitHub Release parsing', () {
    test('parses GitHub API response and detects [MANDATORY] flag', () {
      final json = {
        'tag_name': 'v2.3.3',
        'body': '• Critical security update\n• [MANDATORY] Please update immediately\n• Fix stream buffering',
        'assets': [
          {
            'name': 'goplay.apk',
            'content_type': 'application/vnd.android.package-archive',
            'browser_download_url': 'https://github.com/nehalmahamuddev/goplay-android/releases/download/v2.3.3/goplay.apk',
          }
        ],
        'published_at': '2026-10-31T00:00:00Z',
      };

      final info = UpdateInfo.fromGithubRelease(json);
      expect(info.latestVersion, equals('2.3.3'));
      expect(info.forceUpdate, isTrue);
      expect(info.apkUrl, equals('https://github.com/nehalmahamuddev/goplay-android/releases/download/v2.3.3/goplay.apk'));
      expect(info.releaseNotes, contains('Critical security update'));
      expect(info.releaseNotes, contains('Fix stream buffering'));
    });

    test('fromTag constructs direct GitHub release download URL', () {
      final info = UpdateInfo.fromTag(tag: 'v2.3.4');
      expect(info.latestVersion, equals('2.3.4'));
      expect(info.forceUpdate, isFalse);
      expect(
        info.apkUrl,
        equals('https://github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/download/v2.3.4/goplay.apk'),
      );
    });
  });

  group('UpdateState - isManualCheck tracking', () {
    test('defaults isManualCheck to false', () {
      const state = UpdateState();
      expect(state.isManualCheck, isFalse);
    });

    test('copyWith preserves or updates isManualCheck', () {
      const state = UpdateState();
      final manualState = state.copyWith(isManualCheck: true);
      expect(manualState.isManualCheck, isTrue);
    });
  });
}

