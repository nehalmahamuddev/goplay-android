import '../../models/announcement.dart';
import '../../models/app_ui_config.dart';
import '../../models/category.dart';
import '../../models/channel.dart';
import '../../models/event.dart';
import '../../models/hero_banner_item.dart';

/// Persisted sync metadata for a category's direct M3U playlist.
class CategoryM3uMeta {
  final String m3uUrl;
  final String? etag;
  final String? lastModified;
  final String? contentHash;
  final DateTime? lastSyncedAt;

  const CategoryM3uMeta({
    required this.m3uUrl,
    this.etag,
    this.lastModified,
    this.contentHash,
    this.lastSyncedAt,
  });

  factory CategoryM3uMeta.fromJson(Map<String, dynamic> json) {
    return CategoryM3uMeta(
      m3uUrl: (json['m3u_url'] as String? ?? '').trim(),
      etag: json['etag'] as String?,
      lastModified: json['last_modified'] as String?,
      contentHash: json['content_hash'] as String?,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'm3u_url': m3uUrl,
        if (etag != null) 'etag': etag,
        if (lastModified != null) 'last_modified': lastModified,
        if (contentHash != null) 'content_hash': contentHash,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt!.toIso8601String(),
      };
}

/// Persistence seam for synchronized server/M3U catalog entities and metadata.
abstract interface class CatalogStore {
  void invalidateMemo();

  List<Channel> getLocalChannels();
  Future<void> saveLocalChannels(List<Channel> channels);

  List<Channel> getCategoryM3uChannels(String categoryId);
  Future<void> saveCategoryM3uChannels(String categoryId, List<Channel> channels);

  CategoryM3uMeta? getCategoryM3uMeta(String categoryId);
  Future<void> saveCategoryM3uMeta(String categoryId, CategoryM3uMeta meta);

  Future<void> clearCategoryM3uData(String categoryId);
  Set<String> getCachedM3uCategoryIds();
  bool hasAnyLocalChannelData();

  List<SportEvent> getLocalEvents();
  Future<void> saveLocalEvents(List<SportEvent> events);

  List<Category> getLocalCategories();
  Future<void> saveLocalCategories(List<Category> categories);

  List<Announcement> getLocalAnnouncements();
  Future<void> saveLocalAnnouncements(List<Announcement> announcements);

  List<HeroBannerItem> getLocalHeroBanners();
  Future<void> saveLocalHeroBanners(List<HeroBannerItem> banners);

  int? getLocalChannelsVersion();
  Future<void> saveLocalChannelsVersion(int version);

  int? getLocalEventsVersion();
  Future<void> saveLocalEventsVersion(int version);

  bool hasLocalUiConfig();
  AppUiConfig getLocalUiConfig();
  Future<void> saveLocalUiConfig(AppUiConfig config);

  int? getLocalUiConfigVersion();
  Future<void> saveLocalUiConfigVersion(int version);

  Future<void> resetLocalUiConfigToDefaults();
  Future<void> clearAllCache();
}

/// Pure in-memory [CatalogStore] implementation for headless tests.
class InMemoryCatalogStore implements CatalogStore {
  List<Channel> _channels = const [];
  List<Category> _categories = const [];
  List<SportEvent> _events = const [];
  List<Announcement> _announcements = const [];
  List<HeroBannerItem> _heroBanners = const [];
  final Map<String, List<Channel>> _m3uChannels = {};
  final Map<String, CategoryM3uMeta> _m3uMeta = {};
  int? _channelsVersion;
  int? _eventsVersion;
  AppUiConfig? _uiConfig;
  int? _uiConfigVersion;

  @override
  void invalidateMemo() {}

  @override
  List<Channel> getLocalChannels() => _channels;

  @override
  Future<void> saveLocalChannels(List<Channel> channels) async {
    _channels = List<Channel>.unmodifiable(channels);
  }

  @override
  List<Channel> getCategoryM3uChannels(String categoryId) =>
      _m3uChannels[categoryId] ?? const [];

  @override
  Future<void> saveCategoryM3uChannels(
    String categoryId,
    List<Channel> channels,
  ) async {
    _m3uChannels[categoryId] = List<Channel>.unmodifiable(channels);
  }

  @override
  CategoryM3uMeta? getCategoryM3uMeta(String categoryId) => _m3uMeta[categoryId];

  @override
  Future<void> saveCategoryM3uMeta(String categoryId, CategoryM3uMeta meta) async {
    _m3uMeta[categoryId] = meta;
  }

  @override
  Future<void> clearCategoryM3uData(String categoryId) async {
    _m3uChannels.remove(categoryId);
    _m3uMeta.remove(categoryId);
  }

  @override
  Set<String> getCachedM3uCategoryIds() =>
      {..._m3uChannels.keys, ..._m3uMeta.keys};

  @override
  bool hasAnyLocalChannelData() {
    if (_channels.isNotEmpty) return true;
    for (final cat in _categories) {
      if (cat.active && cat.hasM3uUrl && getCategoryM3uChannels(cat.id).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  @override
  List<SportEvent> getLocalEvents() => _events;

  @override
  Future<void> saveLocalEvents(List<SportEvent> events) async {
    final sorted = events.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _events = List<SportEvent>.unmodifiable(sorted);
  }

  @override
  List<Category> getLocalCategories() => _categories;

  @override
  Future<void> saveLocalCategories(List<Category> categories) async {
    _categories = List<Category>.unmodifiable(categories);
  }

  @override
  List<Announcement> getLocalAnnouncements() => _announcements;

  @override
  Future<void> saveLocalAnnouncements(List<Announcement> announcements) async {
    _announcements = List<Announcement>.unmodifiable(announcements);
  }

  @override
  List<HeroBannerItem> getLocalHeroBanners() => _heroBanners;

  @override
  Future<void> saveLocalHeroBanners(List<HeroBannerItem> banners) async {
    _heroBanners = List<HeroBannerItem>.unmodifiable(banners);
  }

  @override
  int? getLocalChannelsVersion() => _channelsVersion;

  @override
  Future<void> saveLocalChannelsVersion(int version) async {
    _channelsVersion = version;
  }

  @override
  int? getLocalEventsVersion() => _eventsVersion;

  @override
  Future<void> saveLocalEventsVersion(int version) async {
    _eventsVersion = version;
  }

  @override
  bool hasLocalUiConfig() => _uiConfig != null;

  @override
  AppUiConfig getLocalUiConfig() => _uiConfig ?? AppUiConfig.defaults();

  @override
  Future<void> saveLocalUiConfig(AppUiConfig config) async {
    _uiConfig = config;
  }

  @override
  int? getLocalUiConfigVersion() => _uiConfigVersion;

  @override
  Future<void> saveLocalUiConfigVersion(int version) async {
    _uiConfigVersion = version;
  }

  @override
  Future<void> resetLocalUiConfigToDefaults() async {
    _uiConfig = AppUiConfig.defaults();
    _uiConfigVersion = null;
  }

  @override
  Future<void> clearAllCache() async {
    _channels = const [];
    _categories = const [];
    _events = const [];
    _announcements = const [];
    _heroBanners = const [];
    _m3uChannels.clear();
    _m3uMeta.clear();
    _channelsVersion = null;
    _eventsVersion = null;
    _uiConfig = null;
    _uiConfigVersion = null;
  }
}
