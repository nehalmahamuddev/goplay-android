import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/category.dart';
import 'app_providers.dart';

/// Master list of fallback categories if network/database is unavailable.
const List<Category> defaultUnifiedCategories = [
  Category(
    id: 'bangla',
    name: 'Bangla',
    iconUrl: 'https://assets-playztv.pages.dev/category/bn.png',
    type: 'custom',
    playzEndpoint: 'channels/Qk4xNzY3MDIzMTU1NzMy.txt',
    sortOrder: -3,
    active: true,
  ),
  Category(
    id: 'kolkata',
    name: 'Kolkata',
    iconUrl: 'https://assets-playztv.pages.dev/category/kolkata.jpg',
    type: 'custom',
    playzEndpoint: 'channels/S29sa2F0YTE3NjcwMDgwNjY5MDg.txt',
    sortOrder: -2,
    active: true,
  ),
  Category(
    id: 'kids',
    name: 'Kids',
    iconUrl: 'https://assets-playztv.pages.dev/category/kids.jpg',
    type: 'custom',
    playzEndpoint: 'channels/S2lkczE3NjcwMDgyMjAzNzM.txt',
    sortOrder: -1,
    active: true,
  ),
  Category(
    id: 'sports',
    name: 'Sports',
    iconUrl: 'https://blogger.googleusercontent.com/img/b/R29vZ2xl/AVvXsEhyx-rZq_n38i8qJ85w-1E/s1600/1000407701.jpg',
    type: 'custom',
    playzEndpoint: 'channels/U3BvcnRzIDE3NjcwMDcwMjc1Njc.txt',
    sortOrder: 1,
    active: true,
  ),
  Category(
    id: 'news',
    name: 'News',
    iconUrl: 'https://assets-playztv.pages.dev/category/news.jpg',
    type: 'custom',
    playzEndpoint: 'channels/TmV3czE3NjcwMDgxODM1MjQ.txt',
    sortOrder: 2,
    active: true,
  ),
  Category(
    id: 'entertainment',
    name: 'Entertainment',
    iconUrl: 'https://assets-playztv.pages.dev/category/ent.jpg',
    type: 'custom',
    playzEndpoint: 'channels/RW50ZXJ0YWlubWVudDE3NjcwMDg0NDY4OTE.txt',
    sortOrder: 3,
    active: true,
  ),
  Category(
    id: 'movie',
    name: 'Movie',
    iconUrl: 'https://assets-playztv.pages.dev/category/mov.jpg',
    type: 'custom',
    playzEndpoint: 'channels/TW92aWUxNzY3MDA4NDgxMzM3.txt',
    sortOrder: 4,
    active: true,
  ),
  Category(
    id: 'music',
    name: 'Music',
    iconUrl: 'https://assets-playztv.pages.dev/category/music.jpg',
    type: 'custom',
    playzEndpoint: 'channels/TXVzaWMxNzY3MDA4NTMyNjM3.txt',
    sortOrder: 5,
    active: true,
  ),
  Category(
    id: 'infotainment',
    name: 'Infotainment',
    iconUrl: 'https://assets-playztv.pages.dev/category/info.jpg',
    type: 'custom',
    playzEndpoint: 'channels/SW5mb3RhaW5tZW50MTc2NzAwODU2NjcwNg.txt',
    sortOrder: 6,
    active: true,
  ),
  Category(
    id: 'islamic',
    name: 'Islamic',
    iconUrl: 'https://assets-playztv.pages.dev/category/isl.jpg',
    type: 'custom',
    playzEndpoint: 'channels/SXNsYW1pYzE3NjcwMDgyNTA2NzI.txt',
    sortOrder: 7,
    active: true,
  ),
  Category(
    id: 'radio',
    name: 'Radio',
    iconUrl: 'https://assets-playztv.pages.dev/category/rad.jpg',
    type: 'custom',
    playzEndpoint: 'channels/UmFkaW8xNzY3MDA4Mjg0MjM5.txt',
    sortOrder: 8,
    active: true,
  ),
  Category(
    id: 'nepal',
    name: 'Nepal',
    iconUrl: 'https://assets-playztv.pages.dev/category/np.jpg',
    type: 'custom',
    playzEndpoint: 'channels/TmVwYWwxNzY3MDI1MjMxODU0.txt',
    sortOrder: 9,
    active: true,
  ),
  Category(
    id: 'pakistan',
    name: 'Pakistan',
    iconUrl: 'https://assets-playztv.pages.dev/category/pkk2.jpg',
    type: 'm3u',
    m3uUrl: 'https://m3u-tvb.pages.dev/pk.m3ux',
    sortOrder: 10,
    active: true,
  ),
];

/// Provides Categories from merged Supabase categories table (filtered for active categories)
final playzCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final categories = await ref.watch(categoriesProvider.future);
  return categories.where((c) => c.active).toList();
});

/// Holds the currently selected Category for single-screen expansion
final playzSelectedCategoryProvider =
    NotifierProvider<PlayzSelectedCategoryNotifier, Category?>(
  PlayzSelectedCategoryNotifier.new,
);

class PlayzSelectedCategoryNotifier extends Notifier<Category?> {
  @override
  Category? build() => null;

  void select(Category? category) => state = category;
}

/// Fetches channels for a selected Category through the unified
/// [CatalogRepository] so M3U and DB channels never diverge from [channelsProvider].
final playzCategoryChannelsProvider =
    FutureProvider.family<List<Channel>, Category>((ref, category) async {
  if (!category.active) return const [];
  final liveCatalog = await ref.watch(channelsProvider.future);
  return ref.watch(catalogRepositoryProvider).loadCategoryChannels(
        category,
        liveCatalog: liveCatalog,
      );
});
