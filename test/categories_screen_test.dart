import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/category.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/providers/app_providers.dart';
import 'package:goplay/providers/playz_providers.dart';
import 'package:goplay/screens/categories/categories_screen.dart';
import 'package:goplay/services/cache_service.dart';

class _FakeCache extends CacheService {
  _FakeCache({required this.channels, required this.categories});

  final List<Channel> channels;
  final List<Category> categories;

  @override
  List<Channel> getLocalChannels() => channels;

  @override
  List<Category> getLocalCategories() => categories;

  @override
  Set<String> getFavoriteChannelIds() => <String>{};

  @override
  Future<void> saveFavoriteChannelIds(Set<String> ids) async {}
}

Category makeCategory(String id, String name, int sortOrder, {bool active = true}) =>
    Category(id: id, name: name, sortOrder: sortOrder, active: active);

Channel makeChannel(String id, String name, String category) => Channel(
      id: id,
      name: name,
      category: category,
      streamUrl: 'https://example.test/$id.m3u8',
    );

void main() {
  group('CategoriesScreen inactive filtering', () {
    testWidgets('only renders active categories, hiding inactive categories',
        (tester) async {
      final cache = _FakeCache(
        channels: [
          makeChannel('c1', 'Sports Channel', 'sports'),
          makeChannel('c2', 'News Channel', 'news'),
          makeChannel('c3', 'Movies Channel', 'movies'),
        ],
        categories: [
          makeCategory('sports', 'Sports', 0, active: true),
          makeCategory('news', 'News', 1, active: true),
          makeCategory('movies', 'Movies', 2, active: false),
        ],
      );

      final container = ProviderContainer(
        overrides: [cacheServiceProvider.overrideWithValue(cache)],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sports'), findsOneWidget);
      expect(find.text('News'), findsOneWidget);
      expect(find.text('Movies'), findsNothing);
    });

    testWidgets('playzCategoriesProvider only yields active categories',
        (tester) async {
      final cache = _FakeCache(
        channels: [],
        categories: [
          makeCategory('sports', 'Sports', 0, active: true),
          makeCategory('movies', 'Movies', 1, active: false),
        ],
      );

      final container = ProviderContainer(
        overrides: [cacheServiceProvider.overrideWithValue(cache)],
      );
      addTearDown(container.dispose);

      final cats = await container.read(playzCategoriesProvider.future);
      expect(cats.length, 1);
      expect(cats.first.id, 'sports');
    });

    testWidgets('navigates back to categories list if active category becomes inactive',
        (tester) async {
      final cache = _FakeCache(
        channels: [
          makeChannel('c1', 'Sports Channel', 'sports'),
        ],
        categories: [
          makeCategory('sports', 'Sports', 0, active: true),
          makeCategory('news', 'News', 1, active: true),
        ],
      );

      final container = ProviderContainer(
        overrides: [cacheServiceProvider.overrideWithValue(cache)],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CategoriesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Sports category to open its channels
      await tester.tap(find.text('Sports'));
      await tester.pumpAndSettle();



      // Now we are on channels page inside categories screen
      expect(find.text('Sports Channel'), findsOneWidget);

      // Simulate Sports category becoming inactive during sync
      container.updateOverrides([
        cacheServiceProvider.overrideWithValue(
          _FakeCache(
            channels: [
              makeChannel('c1', 'Sports Channel', 'sports'),
            ],
            categories: [
              makeCategory('sports', 'Sports', 0, active: false),
              makeCategory('news', 'News', 1, active: true),
            ],
          ),
        ),
      ]);
      container.invalidate(categoriesProvider);
      container.invalidate(playzCategoriesProvider);
      await tester.pumpAndSettle();

      // Should automatically navigate back to Categories list, where News is shown and Sports is gone
      expect(find.text('News'), findsOneWidget);
      expect(find.text('Sports'), findsNothing);
      expect(find.text('Sports Channel'), findsNothing);
    });
  });
}
