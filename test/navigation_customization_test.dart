import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:goplay/core/constants.dart';
import 'package:goplay/models/nav_destination.dart';
import 'package:goplay/services/cache_service.dart';
import 'package:goplay/providers/app_providers.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_nav_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Navigation Destination Model Tests', () {
    test('All 7 destinations have valid IDs and branch mappings', () {
      expect(NavDestination.values.length, 7);
      expect(NavDestination.home.branchIndex, 0);
      expect(NavDestination.categories.branchIndex, 1);
      expect(NavDestination.channels.branchIndex, 2);
      expect(NavDestination.favorites.branchIndex, 2);
      expect(NavDestination.events.branchIndex, 3);
      expect(NavDestination.settings.branchIndex, 4);
      expect(NavDestination.iptv.branchIndex, 5);
      expect(NavDestination.settings.route, '/settings');
      expect(NavDestination.iptv.route, '/iptv');

      expect(NavDestination.fromId('favorites'), NavDestination.favorites);
      expect(NavDestination.fromId('iptv'), NavDestination.iptv);
      expect(NavDestination.fromId('unknown'), NavDestination.home);
    });

    test('Default tabs contains standard destinations including IPTV', () {
      expect(NavDestination.defaultTabs.length, 5);
      expect(NavDestination.defaultTabIds, ['home', 'categories', 'channels', 'events', 'iptv']);
    });
  });

  group('Navigation Persistence & Providers Tests', () {
    test('CacheService respects min 3 and max 5 bounds', () async {
      await Hive.openBox(AppConstants.settingsBox);
      final cacheService = CacheService();

      // Unset should return default tabs
      expect(cacheService.getCustomNavTabsUserPref(), NavDestination.defaultTabIds);

      // Setting 2 tabs (invalid) should fall back to default
      await cacheService.saveCustomNavTabsUserPref(['home', 'favorites']);
      expect(cacheService.getCustomNavTabsUserPref(), NavDestination.defaultTabIds);

      // Setting 4 tabs (valid) should persist
      final customFour = ['home', 'channels', 'favorites', 'settings'];
      await cacheService.saveCustomNavTabsUserPref(customFour);
      expect(cacheService.getCustomNavTabsUserPref(), customFour);

      // Setting 5 tabs (valid) should persist
      final customFive = ['home', 'categories', 'channels', 'favorites', 'settings'];
      await cacheService.saveCustomNavTabsUserPref(customFive);
      expect(cacheService.getCustomNavTabsUserPref(), customFive);

      // Setting 6 tabs (invalid) should fall back to default
      await cacheService.saveCustomNavTabsUserPref([
        'home',
        'categories',
        'channels',
        'favorites',
        'events',
        'settings',
      ]);
      expect(cacheService.getCustomNavTabsUserPref(), NavDestination.defaultTabIds);
    });

    test('Default launch page and last active tab persist properly', () async {
      await Hive.openBox(AppConstants.settingsBox);
      final cacheService = CacheService();

      expect(cacheService.getDefaultLaunchPageUserPref(), 'home');
      await cacheService.saveDefaultLaunchPageUserPref('favorites');
      expect(cacheService.getDefaultLaunchPageUserPref(), 'favorites');

      expect(cacheService.getLastActiveNavTabUserPref(), 'home');
      await cacheService.saveLastActiveNavTabUserPref('channels');
      expect(cacheService.getLastActiveNavTabUserPref(), 'channels');
    });

    test('Riverpod CustomNavTabsNotifier enforces bounds and updates state', () async {
      await Hive.openBox(AppConstants.settingsBox);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(customNavTabsProvider.notifier);
      expect(container.read(customNavTabsProvider), NavDestination.defaultTabs);

      // Reject < 3
      final rejected = await notifier.setTabs([NavDestination.home, NavDestination.favorites]);
      expect(rejected, isFalse);

      // Accept 4
      final accepted = await notifier.setTabs([
        NavDestination.home,
        NavDestination.channels,
        NavDestination.favorites,
        NavDestination.settings,
      ]);
      expect(accepted, isTrue);
      expect(container.read(customNavTabsProvider).length, 4);

      // Reset to default
      await notifier.resetToDefault();
      expect(container.read(customNavTabsProvider), NavDestination.defaultTabs);
    });
  });
}
