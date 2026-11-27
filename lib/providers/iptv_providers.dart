import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/drm_config.dart';
import '../models/iptv_playlist.dart';
import '../services/iptv_service.dart';
import 'app_providers.dart';

/// Singleton service provider
final iptvServiceProvider = Provider<IptvService>((ref) => IptvService());

/// Playlist Home sort mode: `'default'`, `'newest'`, `'oldest'`, `'asc'`, `'desc'`, `'count'`
final iptvHomeSortModeProvider =
    NotifierProvider<IptvHomeSortModeNotifier, String>(
  IptvHomeSortModeNotifier.new,
);

class IptvHomeSortModeNotifier extends Notifier<String> {
  @override
  String build() => 'default';

  void setSort(String mode) => state = mode;
}

/// Kept as an alias so any legacy references to `iptvSortModeProvider` keep compiling cleanly.
final iptvSortModeProvider = iptvHomeSortModeProvider;

/// Global IPTV preferences persisted in Hive (`enableSortPlaylist`, `hideAllCategory`, `cacheEnabled`, `rememberChoice`, etc.)
final iptvSettingsProvider =
    NotifierProvider<IptvSettingsNotifier, IptvGlobalSettings>(
  IptvSettingsNotifier.new,
);

class IptvSettingsNotifier extends Notifier<IptvGlobalSettings> {
  @override
  IptvGlobalSettings build() {
    return ref.read(iptvServiceProvider).loadGlobalSettings();
  }

  Future<void> updateSettings(IptvGlobalSettings next) async {
    state = next;
    await ref.read(iptvServiceProvider).saveGlobalSettings(next);
  }

  Future<void> toggleSortCategoriesByCount([bool? value]) async {
    final next = value ?? !state.sortCategoriesByCount;
    await updateSettings(state.copyWith(sortCategoriesByCount: next));
  }

  Future<void> toggleHideAllCategory([bool? value]) async {
    final next = value ?? !state.hideAllCategory;
    await updateSettings(state.copyWith(hideAllCategory: next));
  }

  Future<void> toggleCacheEnabled([bool? value]) async {
    final next = value ?? !state.cacheEnabled;
    await updateSettings(state.copyWith(cacheEnabled: next));
  }

  Future<void> saveBookmarkChoice({
    required bool remember,
    required List<String> categories,
  }) async {
    final normalized = categories.where((e) => e.trim().isNotEmpty).toList();
    await updateSettings(
      state.copyWith(
        rememberBookmarkChoice: remember,
        rememberedCategories:
            remember && normalized.isNotEmpty ? normalized : const ['All'],
      ),
    );
  }

  Future<void> addBookmarkCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (state.bookmarkCategories
        .any((c) => c.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    await updateSettings(
      state.copyWith(
        bookmarkCategories: [...state.bookmarkCategories, trimmed],
      ),
    );
  }

  Future<void> removeBookmarkCategory(String name) async {
    if (name.toLowerCase() == 'all') return;
    final nextCats = state.bookmarkCategories
        .where((c) => c.toLowerCase() != name.toLowerCase())
        .toList();
    await updateSettings(state.copyWith(bookmarkCategories: nextCats));
  }

  Future<void> setBackgroundMode(
    IptvBackgroundMode mode, {
    String? imagePath,
  }) async {
    await updateSettings(
      state.copyWith(
        backgroundMode: mode,
        backgroundImagePath: imagePath,
        clearBackgroundImagePath: mode != IptvBackgroundMode.customImage,
      ),
    );
  }
}

/// Per-playlist view settings map (`playlistId -> IptvViewConfig`) matching `context.md` §6.2.
final iptvViewConfigsProvider =
    NotifierProvider<IptvViewConfigsNotifier, Map<String, IptvViewConfig>>(
  IptvViewConfigsNotifier.new,
);

class IptvViewConfigsNotifier extends Notifier<Map<String, IptvViewConfig>> {
  @override
  Map<String, IptvViewConfig> build() {
    return ref.read(iptvServiceProvider).loadViewConfigs();
  }

  IptvViewConfig configFor(String playlistId) {
    return state[playlistId] ?? state['default'] ?? const IptvViewConfig();
  }

  Future<void> setConfig(String playlistId, IptvViewConfig config) async {
    final next = Map<String, IptvViewConfig>.from(state);
    next[playlistId] = config;
    state = next;
    await ref.read(iptvServiceProvider).saveViewConfigs(next);
  }

  Future<void> resetPlaylist(String playlistId) async {
    final next = Map<String, IptvViewConfig>.from(state)..remove(playlistId);
    state = next;
    await ref.read(iptvServiceProvider).saveViewConfigs(next);
  }

  Future<void> resetAll() async {
    state = const {};
    await ref.read(iptvServiceProvider).saveViewConfigs(const {});
  }
}

/// Persisted IPTV Bookmarks (`channelId -> IptvBookmarkItem`) synced with `favoriteChannelIdsProvider`.
final iptvBookmarksProvider =
    NotifierProvider<IptvBookmarksNotifier, Map<String, IptvBookmarkItem>>(
  IptvBookmarksNotifier.new,
);

class IptvBookmarksNotifier extends Notifier<Map<String, IptvBookmarkItem>> {
  @override
  Map<String, IptvBookmarkItem> build() {
    return ref.read(iptvServiceProvider).loadBookmarks();
  }

  bool isBookmarked(String channelId) => state.containsKey(channelId);

  Future<void> saveBookmark({
    required Channel channel,
    required String playlistId,
    required String playlistName,
    List<String> categories = const ['All'],
  }) async {
    final cleanCats = categories.where((c) => c.trim().isNotEmpty).toList();
    if (!cleanCats.any((c) => c.toLowerCase() == 'all')) {
      cleanCats.add('All');
    }

    final next = Map<String, IptvBookmarkItem>.from(state);
    next[channel.id] = IptvBookmarkItem(
      channel: channel,
      playlistId: playlistId,
      playlistName: playlistName,
      categories: cleanCats,
      savedAt: DateTime.now(),
    );
    state = next;

    final favs = ref.read(favoriteChannelIdsProvider);
    if (!favs.contains(channel.id)) {
      ref.read(favoriteChannelIdsProvider.notifier).toggle(channel.id);
    }

    await ref.read(iptvServiceProvider).saveBookmarks(next);
  }

  Future<void> removeBookmark(String channelId) async {
    if (!state.containsKey(channelId)) return;
    final next = Map<String, IptvBookmarkItem>.from(state)..remove(channelId);
    state = next;

    final favs = ref.read(favoriteChannelIdsProvider);
    if (favs.contains(channelId)) {
      ref.read(favoriteChannelIdsProvider.notifier).toggle(channelId);
    }

    await ref.read(iptvServiceProvider).saveBookmarks(next);
  }
}

/// Active XMLTV EPG maps keyed by source (`epgUrl` or `playlistId`).
final iptvEpgProvider =
    NotifierProvider<IptvEpgNotifier, Map<String, Map<String, List<IptvEpgProgramme>>>>(
  IptvEpgNotifier.new,
);

class IptvEpgNotifier
    extends Notifier<Map<String, Map<String, List<IptvEpgProgramme>>>> {
  @override
  Map<String, Map<String, List<IptvEpgProgramme>>> build() => const {};

  Future<void> loadEpgForPlaylist(
    IptvPlaylist playlist, {
    bool forceRefresh = false,
  }) async {
    final epgUrl = playlist.epgUrl?.trim();
    if (epgUrl == null || epgUrl.isEmpty) return;
    if (!forceRefresh && state.containsKey(playlist.id)) return;

    final service = ref.read(iptvServiceProvider);
    final headers = <String, String>{
      ...playlist.headers,
      if (playlist.userAgent != null && playlist.userAgent!.isNotEmpty)
        'User-Agent': playlist.userAgent!,
    };
    final parsed = await service.fetchAndParseEpg(
      epgUrl,
      headers: headers.isNotEmpty ? headers : null,
    );
    if (parsed.isNotEmpty) {
      state = {...state, playlist.id: parsed};
    }
  }

  void setEpgForTesting(
    String playlistId,
    Map<String, List<IptvEpgProgramme>> map,
  ) {
    state = {...state, playlistId: map};
  }

  /// Fetch and cache an arbitrary XMLTV EPG feed keyed by [key] (defaults to [epgUrl]).
  Future<int> loadEpgUrl(
    String epgUrl, {
    String? key,
    Map<String, String>? headers,
    bool forceRefresh = false,
  }) async {
    final trimmed = epgUrl.trim();
    if (trimmed.isEmpty) return 0;
    final storeKey = key ?? trimmed;
    if (!forceRefresh && state[storeKey] != null) {
      return state[storeKey]!.length;
    }

    final parsed = await ref
        .read(iptvServiceProvider)
        .fetchAndParseEpg(trimmed, headers: headers);
    if (parsed.isNotEmpty) {
      state = {...state, storeKey: parsed};
    }
    return parsed.length;
  }

  void removeKey(String key) {
    if (!state.containsKey(key)) return;
    final next = Map<String, Map<String, List<IptvEpgProgramme>>>.from(state)
      ..remove(key);
    state = next;
  }

  void clearAll() {
    state = const {};
  }
}

/// Global user-saved XMLTV EPG feeds managed by `IptvManageEpgSheet` (`ManageEpgActivity`).
final iptvSavedEpgSourcesProvider =
    NotifierProvider<IptvSavedEpgSourcesNotifier, List<IptvEpgSource>>(
  IptvSavedEpgSourcesNotifier.new,
);

class IptvSavedEpgSourcesNotifier extends Notifier<List<IptvEpgSource>> {
  @override
  List<IptvEpgSource> build() {
    return ref.read(iptvServiceProvider).loadSavedEpgSources();
  }

  Future<IptvEpgSource> addOrUpdateSource({
    required String name,
    required String url,
  }) async {
    final trimmedUrl = url.trim();
    final effectiveName =
        name.trim().isNotEmpty ? name.trim() : 'TV Guide (XMLTV)';
    final now = DateTime.now();

    final count = await ref
        .read(iptvEpgProvider.notifier)
        .loadEpgUrl(trimmedUrl, key: trimmedUrl, forceRefresh: true);

    final existingIdx = state.indexWhere((s) => s.url == trimmedUrl);
    final source = existingIdx >= 0
        ? state[existingIdx].copyWith(
            name: effectiveName,
            lastSynced: now,
            channelCount: count,
          )
        : IptvEpgSource(
            id: 'epg_${now.millisecondsSinceEpoch}',
            name: effectiveName,
            url: trimmedUrl,
            addedAt: now,
            lastSynced: now,
            channelCount: count,
          );

    final next = existingIdx >= 0
        ? (List<IptvEpgSource>.from(state)..[existingIdx] = source)
        : [source, ...state];

    state = next;
    await ref.read(iptvServiceProvider).saveEpgSources(next);
    return source;
  }

  Future<int> syncSource(String id) async {
    final idx = state.indexWhere((s) => s.id == id);
    if (idx < 0) return 0;
    final target = state[idx];
    final count = await ref
        .read(iptvEpgProvider.notifier)
        .loadEpgUrl(target.url, key: target.url, forceRefresh: true);
    final updated = target.copyWith(
      lastSynced: DateTime.now(),
      channelCount: count,
    );
    final next = List<IptvEpgSource>.from(state)..[idx] = updated;
    state = next;
    await ref.read(iptvServiceProvider).saveEpgSources(next);
    return count;
  }

  Future<int> syncAllSources() async {
    int totalSynced = 0;
    final next = <IptvEpgSource>[];
    for (final s in state) {
      final count = await ref
          .read(iptvEpgProvider.notifier)
          .loadEpgUrl(s.url, key: s.url, forceRefresh: true);
      totalSynced += count;
      next.add(s.copyWith(lastSynced: DateTime.now(), channelCount: count));
    }
    state = next;
    await ref.read(iptvServiceProvider).saveEpgSources(next);
    return totalSynced;
  }

  Future<void> removeSource(String id) async {
    final target = state.where((s) => s.id == id).firstOrNull;
    if (target != null) {
      ref.read(iptvEpgProvider.notifier).removeKey(target.url);
    }
    final next = state.where((s) => s.id != id).toList();
    state = next;
    await ref.read(iptvServiceProvider).saveEpgSources(next);
  }

  Future<void> clearAllSources() async {
    for (final s in state) {
      ref.read(iptvEpgProvider.notifier).removeKey(s.url);
    }
    state = const [];
    await ref.read(iptvServiceProvider).saveEpgSources(const []);
  }
}

/// Periodic minute ticker for updating live EPG progress bars smoothly.
final iptvEpgClockProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 60),
    (_) => DateTime.now(),
  );
});

/// ID of the currently opened playlist; [selectedIptvPlaylistProvider] derives
/// the live [IptvPlaylist] from [iptvPlaylistsProvider] without manual mirroring.
final selectedIptvPlaylistIdProvider =
    NotifierProvider<SelectedIptvPlaylistIdNotifier, String?>(
  SelectedIptvPlaylistIdNotifier.new,
);

class SelectedIptvPlaylistIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? playlistId) => state = playlistId;
}

/// Currently opened playlist derived cleanly from [iptvPlaylistsProvider].
final selectedIptvPlaylistProvider = Provider<IptvPlaylist?>((ref) {
  final selectedId = ref.watch(selectedIptvPlaylistIdProvider);
  if (selectedId == null) return null;
  final playlists = ref.watch(iptvPlaylistsProvider).value;
  if (playlists == null) return null;
  for (final p in playlists) {
    if (p.id == selectedId) return p;
  }
  return null;
});

/// Active search query in opened playlist
final iptvSearchQueryProvider =
    NotifierProvider<IptvSearchQueryNotifier, String>(
  IptvSearchQueryNotifier.new,
);

class IptvSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) => state = q;
}

/// Selected category inside an opened playlist
final iptvSelectedCategoryProvider =
    NotifierProvider<IptvSelectedCategoryNotifier, String>(
  IptvSelectedCategoryNotifier.new,
);

class IptvSelectedCategoryNotifier extends Notifier<String> {
  @override
  String build() => 'All';

  void select(String cat) => state = cat;
}

/// State notifier managing user-saved IPTV playlists
final iptvPlaylistsProvider =
    AsyncNotifierProvider<IptvPlaylistsNotifier, List<IptvPlaylist>>(
  IptvPlaylistsNotifier.new,
);

class IptvPlaylistsNotifier extends AsyncNotifier<List<IptvPlaylist>> {
  @override
  Future<List<IptvPlaylist>> build() async {
    final service = ref.read(iptvServiceProvider);
    return service.getSavedPlaylists();
  }

  /// Add a new playlist, parse its streams, and persist to Hive
  Future<IptvPlaylist> addPlaylist(IptvPlaylist playlist) async {
    final service = ref.read(iptvServiceProvider);
    final parsed = await service.fetchAndParse(playlist);
    await service.savePlaylist(parsed);

    final current = state.value ?? [];
    state = AsyncData([parsed, ...current.where((p) => p.id != parsed.id)]);
    return parsed;
  }

  /// Update an existing playlist metadata (or re-fetch when [resync] is true)
  Future<IptvPlaylist> updatePlaylist(
    IptvPlaylist updated, {
    bool resync = false,
  }) async {
    final service = ref.read(iptvServiceProvider);
    final effective = resync ? await service.fetchAndParse(updated) : updated;
    await service.savePlaylist(effective);

    final current = state.value ?? [];
    final index = current.indexWhere((p) => p.id == effective.id);
    if (index != -1) {
      final list = List<IptvPlaylist>.from(current);
      list[index] = effective;
      state = AsyncData(list);
    }

    return effective;
  }

  /// Refresh / re-sync an existing playlist & return the updated playlist
  Future<IptvPlaylist?> refreshPlaylist(String id) async {
    final current = state.value ?? [];
    final index = current.indexWhere((p) => p.id == id);
    if (index == -1) return null;

    final target = current[index];
    final service = ref.read(iptvServiceProvider);

    final refreshed = await service.fetchAndParse(target);
    await service.savePlaylist(refreshed);

    final updated = List<IptvPlaylist>.from(current);
    updated[index] = refreshed;
    state = AsyncData(updated);

    if (refreshed.epgUrl != null && refreshed.epgUrl!.isNotEmpty) {
      await ref
          .read(iptvEpgProvider.notifier)
          .loadEpgForPlaylist(refreshed, forceRefresh: true);
    }
    return refreshed;
  }

  Future<void> reorderPlaylists(int oldIndex, int newIndex) async {
    final current = state.value ?? [];
    if (oldIndex < 0 || oldIndex >= current.length) return;
    if (newIndex < 0 || newIndex > current.length) return;

    final updated = List<IptvPlaylist>.from(current);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);

    state = AsyncData(updated);
    final service = ref.read(iptvServiceProvider);
    await service.saveAllPlaylists(updated);
  }

  Future<void> deletePlaylist(String id) async {
    final service = ref.read(iptvServiceProvider);
    await service.deletePlaylist(id);

    final current = state.value ?? [];
    state = AsyncData(current.where((p) => p.id != id).toList());
  }

  Future<void> deletePlaylists(Iterable<String> ids) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final service = ref.read(iptvServiceProvider);
    for (final id in idSet) {
      await service.deletePlaylist(id);
    }
    final current = state.value ?? [];
    state = AsyncData(current.where((p) => !idSet.contains(p.id)).toList());
  }

  Future<void> syncAllPlaylists() async {
    final list = List<IptvPlaylist>.from(state.value ?? []);
    for (final p in list) {
      try {
        await refreshPlaylist(p.id);
      } catch (_) {}
    }
  }

  Future<void> clearAll() async {
    final service = ref.read(iptvServiceProvider);
    final current = state.value ?? [];
    for (final p in current) {
      await service.deletePlaylist(p.id);
    }
    state = const AsyncData([]);
  }

  Future<IptvPlaylist> importSamplePlaylist() async {
    final sampleChannels = [
      Channel(
        id: 'sample_ch_1',
        name: 'Big Buck Bunny (HLS ClearKey DRM)',
        streamUrl:
            'https://bitmovin-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8',
        logo:
            'https://upload.wikimedia.org/wikipedia/commons/c/c5/Big_buck_bunny_poster_big.jpg',
        category: 'DRM Demo',
        quality: '1080p',
        isLive: false,
        drm: const DrmConfig(
          type: DrmType.clearkey,
          kid: 'eb6767cf0234eabb89452292f159abb1',
          key: '89aeb5261c23f0ab956681246005c9b8',
          clearKeys: {
            'eb6767cf0234eabb89452292f159abb1': '89aeb5261c23f0ab956681246005c9b8',
          },
        ),
      ),
      Channel(
        id: 'sample_ch_2',
        name: 'Tears of Steel (4K UHD DASH)',
        streamUrl: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
        logo:
            'https://upload.wikimedia.org/wikipedia/commons/b/b8/Tears_of_Steel_poster.jpg',
        category: 'Movies',
        quality: '4K',
        isLive: false,
      ),
      Channel(
        id: 'sample_ch_3',
        name: 'Sintel Open Movie (Full HD)',
        streamUrl:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
        logo:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/8/8f/Sintel_poster.jpg/800px-Sintel_poster.jpg',
        category: 'Family',
        quality: '1080p',
        isLive: false,
      ),
      Channel(
        id: 'sample_ch_4',
        name: 'Red Bull TV Live Stream',
        streamUrl:
            'https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8',
        logo:
            'https://upload.wikimedia.org/wikipedia/en/thumb/f/f5/Red_Bull_TV_logo.svg/512px-Red_Bull_TV_logo.svg.png',
        category: 'Sports',
        quality: '1080p60',
        isLive: true,
      ),
      Channel(
        id: 'sample_ch_5',
        name: 'NASA TV HD',
        streamUrl:
            'https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8',
        logo: 'https://upload.wikimedia.org/wikipedia/commons/e/e5/NASA_logo.svg',
        category: 'Documentary',
        quality: 'HD',
        isLive: true,
      ),
    ];

    final sample = IptvPlaylist(
      id: 'iptv_sample_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Sample IPTV & DRM Demo Streams',
      sourceType: IptvSourceType.m3uUrl,
      url: 'https://raw.githubusercontent.com/iptv-org/iptv/master/streams/us.m3u',
      addedAt: DateTime.now(),
      lastSync: DateTime.now(),
      channelCount: sampleChannels.length,
      channels: sampleChannels,
    );

    final service = ref.read(iptvServiceProvider);
    await service.savePlaylist(sample);

    final current = state.value ?? [];
    state = AsyncData([sample, ...current.where((p) => p.id != sample.id)]);
    return sample;
  }

  String exportBackupJson() {
    final list = state.value ?? [];
    final jsonList = list.map((p) => p.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(jsonList);
  }

  Future<int> importBackupJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) return 0;

    final service = ref.read(iptvServiceProvider);
    int imported = 0;
    final current = List<IptvPlaylist>.from(state.value ?? []);

    for (final item in decoded) {
      if (item is Map) {
        try {
          final playlist = IptvPlaylist.fromJson(Map<String, dynamic>.from(item));
          await service.savePlaylist(playlist);
          current.removeWhere((p) => p.id == playlist.id);
          current.insert(0, playlist);
          imported++;
        } catch (_) {}
      }
    }

    state = AsyncData(current);
    return imported;
  }
}

/// Pure function implementing APK grouping & sorting logic (`Lx/Il1LI1I1iI;->i1iL1ILlll1lL`):
/// 1. Accumulates valid channels into insertion-ordered map keyed by `groupTitle` (fallback `'Undefined'`).
/// 2. If [sortByCountDesc] is true and >1 group, sorts descending by `entries.length` (`IIiI11ii1l1` case 19).
/// 3. **After** sorting, prepends `"All"` at index `0` unless [hideAllCategory] is true.
List<IptvGroupedCategory> buildGroupedCategories(
  List<Channel> channels, {
  bool sortByCountDesc = false,
  bool hideAllCategory = false,
}) {
  final valid = channels.where((c) => c.streamUrl.trim().isNotEmpty).toList();
  final groupedMap = <String, List<Channel>>{};

  for (final ch in valid) {
    final key = (ch.category != null && ch.category!.trim().isNotEmpty)
        ? ch.category!.trim()
        : 'Undefined';
    groupedMap.putIfAbsent(key, () => <Channel>[]).add(ch);
  }

  final groups = groupedMap.entries
      .map((e) => IptvGroupedCategory(title: e.key, channels: e.value))
      .toList();

  if (sortByCountDesc && groups.length > 1) {
    groups.sort((a, b) => b.count.compareTo(a.count));
  }

  if (!hideAllCategory) {
    groups.insert(
      0,
      IptvGroupedCategory(
        title: 'All',
        channels: valid,
        isAllTab: true,
      ),
    );
  }

  return groups;
}

/// Grouped category tabs for the currently selected playlist.
final iptvGroupedCategoriesProvider = Provider<List<IptvGroupedCategory>>((ref) {
  final playlist = ref.watch(selectedIptvPlaylistProvider);
  if (playlist == null) return const [];
  final settings = ref.watch(iptvSettingsProvider);
  return buildGroupedCategories(
    playlist.channels,
    sortByCountDesc: settings.sortCategoriesByCount,
    hideAllCategory: playlist.hideAllCategory || settings.hideAllCategory,
  );
});

/// Unique category labels (e.g. `['All', 'Family', 'Movies', ...]`).
final iptvCategoriesProvider = Provider<List<String>>((ref) {
  final groups = ref.watch(iptvGroupedCategoriesProvider);
  if (groups.isEmpty) return const ['All'];
  return groups.map((g) => g.title).toList(growable: false);
});

/// Filtered channels for a specific category tab using APK title-only search (`Lx/i1iI1LLi;`).
List<Channel> filterIptvCategoryChannels(List<Channel> source, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return source;
  return source
      .where((ch) => ch.name.toLowerCase().contains(query))
      .toList(growable: false);
}

/// Backwards-compatible provider exposing the active category's filtered channels.
final filteredIptvChannelsProvider = Provider<List<Channel>>((ref) {
  final groups = ref.watch(iptvGroupedCategoriesProvider);
  if (groups.isEmpty) return const [];
  final selectedCat = ref.watch(iptvSelectedCategoryProvider);
  final query = ref.watch(iptvSearchQueryProvider);

  final group = groups.firstWhere(
    (g) => g.title.toLowerCase() == selectedCat.toLowerCase(),
    orElse: () => groups.first,
  );
  return filterIptvCategoryChannels(group.channels, query);
});

/// Matches individual channels across all saved playlists (`MultiSearchActivity` parity).
List<({IptvPlaylist playlist, Channel channel})> searchChannelsAcrossPlaylists(
  List<IptvPlaylist> playlists,
  String rawQuery, {
  int limit = 60,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return const [];

  final results = <({IptvPlaylist playlist, Channel channel})>[];
  for (final playlist in playlists) {
    for (final ch in playlist.channels) {
      final inName = ch.name.toLowerCase().contains(query);
      final inCategory = ch.category?.toLowerCase().contains(query) ?? false;
      if (inName || inCategory) {
        results.add((playlist: playlist, channel: ch));
        if (results.length >= limit) return results;
      }
    }
  }
  return results;
}
