import 'channel.dart';
import 'drm_config.dart';

/// Supported IPTV source types matching the APK "Add New Content" sheet.
enum IptvSourceType {
  m3uUrl('Playlist Link (M3U/JSON)', 'Remote playlist link via URL'),
  m3uFile('Local Playlist (M3U/JSON)', 'Local file or pasted M3U/JSON text'),
  xtream('Xtream Codes', 'Username, password and server host'),
  stalker('STB / Stalker / MAC Portal', 'Portal URL and device MAC address'),
  directStream('Network Video Stream', 'Direct stream URL with optional DRM');

  final String label;
  final String description;
  const IptvSourceType(this.label, this.description);
}

/// 4 channel card display modes matching `M3U8MediationAdapter` (`0..3`).
enum IptvDisplayMode {
  list(0, 'List'),
  grid(1, 'Grid'),
  poster(2, 'Poster'),
  square(3, 'Square');

  final int code;
  final String label;
  const IptvDisplayMode(this.code, this.label);

  static IptvDisplayMode fromName(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'list':
        return IptvDisplayMode.list;
      case 'poster':
        return IptvDisplayMode.poster;
      case 'square':
        return IptvDisplayMode.square;
      case 'grid':
      default:
        return IptvDisplayMode.grid;
    }
  }
}

/// 9 preset aspect ratios matching Poster mode `sliderRatio` (`0..8`) in `context.md`.
class IptvPosterRatioPreset {
  final int index;
  final String label;
  final double aspectRatio; // width / height

  const IptvPosterRatioPreset(this.index, this.label, this.aspectRatio);

  static const List<IptvPosterRatioPreset> presets = [
    IptvPosterRatioPreset(0, '2:3', 2 / 3),
    IptvPosterRatioPreset(1, '3:4', 3 / 4),
    IptvPosterRatioPreset(2, '4:5', 4 / 5),
    IptvPosterRatioPreset(3, '1:1', 1.0),
    IptvPosterRatioPreset(4, '4:3', 4 / 3),
    IptvPosterRatioPreset(5, '3:2', 3 / 2),
    IptvPosterRatioPreset(6, '16:10', 16 / 10),
    IptvPosterRatioPreset(7, '16:9', 16 / 9),
    IptvPosterRatioPreset(8, '5:7', 5 / 7),
  ];

  static IptvPosterRatioPreset byIndex(int idx) {
    if (idx < 0 || idx >= presets.length) return presets.first;
    return presets[idx];
  }
}

/// Per-playlist (and global fallback) layout configuration persisted in Hive.
class IptvViewConfig {
  final IptvDisplayMode mode;
  final int spanCount;
  final int posterRatioIndex;

  const IptvViewConfig({
    this.mode = IptvDisplayMode.grid,
    this.spanCount = 2,
    this.posterRatioIndex = 0,
  });

  IptvViewConfig copyWith({
    IptvDisplayMode? mode,
    int? spanCount,
    int? posterRatioIndex,
  }) {
    return IptvViewConfig(
      mode: mode ?? this.mode,
      spanCount: spanCount ?? this.spanCount,
      posterRatioIndex: posterRatioIndex ?? this.posterRatioIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'spanCount': spanCount,
        'posterRatioIndex': posterRatioIndex,
      };

  factory IptvViewConfig.fromJson(Map<String, dynamic> json) {
    return IptvViewConfig(
      mode: IptvDisplayMode.fromName(json['mode'] as String?),
      spanCount: (json['spanCount'] as num?)?.toInt() ?? 2,
      posterRatioIndex: (json['posterRatioIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Global IPTV preferences mirrored from the source APK's SharedPreferences.
class IptvGlobalSettings {
  /// `enableSortPlaylist`: sorts grouped categories descending by channel count (`listSize`),
  /// keeping the "All" category pinned at index 0.
  final bool sortCategoriesByCount;

  /// `playlistHideAllCategory`: omits the synthetic "All" tab when true.
  final bool hideAllCategory;

  /// `playlistCacheEnabled`: 24-hour local cache reuse on repeat playlist opens.
  final bool cacheEnabled;

  /// `remember_choice`: skip category selector modal when bookmarking channels.
  final bool rememberBookmarkChoice;

  /// `remembered_categories`: saved category names when `rememberBookmarkChoice` is true.
  final List<String> rememberedCategories;

  /// User-defined bookmark category buckets.
  final List<String> bookmarkCategories;

  const IptvGlobalSettings({
    this.sortCategoriesByCount = false,
    this.hideAllCategory = false,
    this.cacheEnabled = true,
    this.rememberBookmarkChoice = false,
    this.rememberedCategories = const ['All'],
    this.bookmarkCategories = const ['All', 'Sports', 'Movies', 'News', 'Kids'],
  });

  IptvGlobalSettings copyWith({
    bool? sortCategoriesByCount,
    bool? hideAllCategory,
    bool? cacheEnabled,
    bool? rememberBookmarkChoice,
    List<String>? rememberedCategories,
    List<String>? bookmarkCategories,
  }) {
    return IptvGlobalSettings(
      sortCategoriesByCount: sortCategoriesByCount ?? this.sortCategoriesByCount,
      hideAllCategory: hideAllCategory ?? this.hideAllCategory,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      rememberBookmarkChoice: rememberBookmarkChoice ?? this.rememberBookmarkChoice,
      rememberedCategories: rememberedCategories ?? this.rememberedCategories,
      bookmarkCategories: bookmarkCategories ?? this.bookmarkCategories,
    );
  }

  Map<String, dynamic> toJson() => {
        'sortCategoriesByCount': sortCategoriesByCount,
        'hideAllCategory': hideAllCategory,
        'cacheEnabled': cacheEnabled,
        'rememberBookmarkChoice': rememberBookmarkChoice,
        'rememberedCategories': rememberedCategories,
        'bookmarkCategories': bookmarkCategories,
      };

  factory IptvGlobalSettings.fromJson(Map<String, dynamic> json) {
    return IptvGlobalSettings(
      sortCategoriesByCount: json['sortCategoriesByCount'] as bool? ?? false,
      hideAllCategory: json['hideAllCategory'] as bool? ?? false,
      cacheEnabled: json['cacheEnabled'] as bool? ?? true,
      rememberBookmarkChoice: json['rememberBookmarkChoice'] as bool? ?? false,
      rememberedCategories: (json['rememberedCategories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['All'],
      bookmarkCategories: (json['bookmarkCategories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['All', 'Sports', 'Movies', 'News', 'Kids'],
    );
  }
}

/// XMLTV Electronic Programme Guide slot matched to a channel.
class IptvEpgProgramme {
  final String channelKey;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime stopTime;

  const IptvEpgProgramme({
    required this.channelKey,
    required this.title,
    this.description,
    required this.startTime,
    required this.stopTime,
  });

  bool isLiveAt(DateTime now) =>
      !now.isBefore(startTime) && now.isBefore(stopTime);

  bool isUpcomingAt(DateTime now) => !stopTime.isBefore(now);

  double progressAt(DateTime now) {
    final total = stopTime.difference(startTime).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = now.difference(startTime).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'channelKey': channelKey,
        'title': title,
        if (description != null) 'description': description,
        'startTime': startTime.toIso8601String(),
        'stopTime': stopTime.toIso8601String(),
      };

  factory IptvEpgProgramme.fromJson(Map<String, dynamic> json) {
    return IptvEpgProgramme(
      channelKey: json['channelKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      stopTime: DateTime.tryParse(json['stopTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// User-saved global XMLTV EPG source managed in "Manage TV Guide" (`ManageEpgActivity`).
class IptvEpgSource {
  final String id;
  final String name;
  final String url;
  final DateTime addedAt;
  final DateTime? lastSynced;
  final int channelCount;

  const IptvEpgSource({
    required this.id,
    required this.name,
    required this.url,
    required this.addedAt,
    this.lastSynced,
    this.channelCount = 0,
  });

  IptvEpgSource copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? addedAt,
    DateTime? lastSynced,
    int? channelCount,
  }) {
    return IptvEpgSource(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      addedAt: addedAt ?? this.addedAt,
      lastSynced: lastSynced ?? this.lastSynced,
      channelCount: channelCount ?? this.channelCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'addedAt': addedAt.toIso8601String(),
        if (lastSynced != null) 'lastSynced': lastSynced!.toIso8601String(),
        'channelCount': channelCount,
      };

  factory IptvEpgSource.fromJson(Map<String, dynamic> json) {
    return IptvEpgSource(
      id: json['id'] as String? ?? 'epg_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'TV Guide (XMLTV)',
      url: json['url'] as String? ?? '',
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.now(),
      lastSynced: json['lastSynced'] != null
          ? DateTime.tryParse(json['lastSynced'] as String)
          : null,
      channelCount: (json['channelCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Category group container matching `GroupedM3U8Entry` in the source APK.
class IptvGroupedCategory {
  final String title;
  final List<Channel> channels;
  final bool isAllTab;

  const IptvGroupedCategory({
    required this.title,
    required this.channels,
    this.isAllTab = false,
  });

  int get count => channels.length;

  String get tabLabel => '$title (${channels.length})';
}

/// Persisted IPTV bookmark storing full playable Channel data + categories.
class IptvBookmarkItem {
  final Channel channel;
  final String playlistId;
  final String playlistName;
  final List<String> categories;
  final DateTime savedAt;

  const IptvBookmarkItem({
    required this.channel,
    required this.playlistId,
    required this.playlistName,
    this.categories = const ['All'],
    required this.savedAt,
  });

  IptvBookmarkItem copyWith({
    Channel? channel,
    String? playlistId,
    String? playlistName,
    List<String>? categories,
    DateTime? savedAt,
  }) {
    return IptvBookmarkItem(
      channel: channel ?? this.channel,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      categories: categories ?? this.categories,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'channel': channel.toJson(),
        'playlistId': playlistId,
        'playlistName': playlistName,
        'categories': categories,
        'savedAt': savedAt.toIso8601String(),
      };

  factory IptvBookmarkItem.fromJson(Map<String, dynamic> json) {
    return IptvBookmarkItem(
      channel: Channel.fromJson(
          Map<String, dynamic>.from(json['channel'] as Map)),
      playlistId: json['playlistId'] as String? ?? '',
      playlistName: json['playlistName'] as String? ?? 'IPTV Playlist',
      categories: (json['categories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['All'],
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Data model representing a user-managed IPTV playlist or connection
class IptvPlaylist {
  final String id;
  final String name;
  final IptvSourceType sourceType;
  final String url;
  final String? username;
  final String? password;
  final String? macAddress;
  final String? epgUrl;
  final String? dohEndpoint;
  final String? userAgent;
  final String? referer;
  final String? cookie;
  final String? origin;
  final String? manifestType;
  final DrmConfig? drm;
  final Map<String, String> headers;
  final bool importLive;
  final bool importVod;
  final bool importSeries;
  final bool hideAllCategory;
  final String? authorization;
  final String? requestType;
  final String? subtitleUrl;
  final String? streamFormat;
  final String? parserType;
  final String? stalkerToken;
  final String? stalkerExpiry;
  final DateTime addedAt;
  final DateTime? lastSync;
  final int channelCount;
  final List<Channel> channels;

  const IptvPlaylist({
    required this.id,
    required this.name,
    required this.sourceType,
    required this.url,
    this.username,
    this.password,
    this.macAddress,
    this.epgUrl,
    this.dohEndpoint,
    this.userAgent,
    this.referer,
    this.cookie,
    this.origin,
    this.manifestType,
    this.drm,
    this.headers = const {},
    this.importLive = true,
    this.importVod = true,
    this.importSeries = true,
    this.hideAllCategory = false,
    this.authorization,
    this.requestType,
    this.subtitleUrl,
    this.streamFormat,
    this.parserType,
    this.stalkerToken,
    this.stalkerExpiry,
    required this.addedAt,
    this.lastSync,
    this.channelCount = 0,
    this.channels = const [],
  });

  bool get isCacheFresh =>
      channels.isNotEmpty &&
      lastSync != null &&
      DateTime.now().difference(lastSync!).inHours < 24;

  IptvPlaylist copyWith({
    String? id,
    String? name,
    IptvSourceType? sourceType,
    String? url,
    String? username,
    String? password,
    String? macAddress,
    String? epgUrl,
    String? dohEndpoint,
    String? userAgent,
    String? referer,
    String? cookie,
    String? origin,
    String? manifestType,
    DrmConfig? drm,
    Map<String, String>? headers,
    bool? importLive,
    bool? importVod,
    bool? importSeries,
    bool? hideAllCategory,
    String? authorization,
    String? requestType,
    String? subtitleUrl,
    String? streamFormat,
    String? parserType,
    String? stalkerToken,
    String? stalkerExpiry,
    DateTime? addedAt,
    DateTime? lastSync,
    int? channelCount,
    List<Channel>? channels,
  }) {
    return IptvPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      sourceType: sourceType ?? this.sourceType,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      macAddress: macAddress ?? this.macAddress,
      epgUrl: epgUrl ?? this.epgUrl,
      dohEndpoint: dohEndpoint ?? this.dohEndpoint,
      userAgent: userAgent ?? this.userAgent,
      referer: referer ?? this.referer,
      cookie: cookie ?? this.cookie,
      origin: origin ?? this.origin,
      manifestType: manifestType ?? this.manifestType,
      drm: drm ?? this.drm,
      headers: headers ?? this.headers,
      importLive: importLive ?? this.importLive,
      importVod: importVod ?? this.importVod,
      importSeries: importSeries ?? this.importSeries,
      hideAllCategory: hideAllCategory ?? this.hideAllCategory,
      authorization: authorization ?? this.authorization,
      requestType: requestType ?? this.requestType,
      subtitleUrl: subtitleUrl ?? this.subtitleUrl,
      streamFormat: streamFormat ?? this.streamFormat,
      parserType: parserType ?? this.parserType,
      stalkerToken: stalkerToken ?? this.stalkerToken,
      stalkerExpiry: stalkerExpiry ?? this.stalkerExpiry,
      addedAt: addedAt ?? this.addedAt,
      lastSync: lastSync ?? this.lastSync,
      channelCount: channelCount ?? this.channelCount,
      channels: channels ?? this.channels,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sourceType': sourceType.name,
        'url': url,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        if (macAddress != null) 'macAddress': macAddress,
        if (epgUrl != null) 'epgUrl': epgUrl,
        if (dohEndpoint != null) 'dohEndpoint': dohEndpoint,
        if (userAgent != null) 'userAgent': userAgent,
        if (referer != null) 'referer': referer,
        if (cookie != null) 'cookie': cookie,
        if (origin != null) 'origin': origin,
        if (manifestType != null) 'manifestType': manifestType,
        if (drm != null) 'drm': drm!.toJson(),
        if (headers.isNotEmpty) 'headers': headers,
        'importLive': importLive,
        'importVod': importVod,
        'importSeries': importSeries,
        'hideAllCategory': hideAllCategory,
        if (authorization != null) 'authorization': authorization,
        if (requestType != null) 'requestType': requestType,
        if (subtitleUrl != null) 'subtitleUrl': subtitleUrl,
        if (streamFormat != null) 'streamFormat': streamFormat,
        if (parserType != null) 'parserType': parserType,
        if (stalkerToken != null) 'stalkerToken': stalkerToken,
        if (stalkerExpiry != null) 'stalkerExpiry': stalkerExpiry,
        'addedAt': addedAt.toIso8601String(),
        if (lastSync != null) 'lastSync': lastSync!.toIso8601String(),
        'channelCount': channelCount,
        'channels': channels.map((c) => c.toJson()).toList(),
      };

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) {
    final rawType = json['sourceType'] as String? ?? 'm3uUrl';
    final sourceType = IptvSourceType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => IptvSourceType.m3uUrl,
    );

    List<Channel> parsedChannels = const [];
    if (json['channels'] is List) {
      parsedChannels = (json['channels'] as List)
          .whereType<Map>()
          .map((m) => Channel.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    return IptvPlaylist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'IPTV Playlist',
      sourceType: sourceType,
      url: json['url'] as String? ?? '',
      username: json['username'] as String?,
      password: json['password'] as String?,
      macAddress: json['macAddress'] as String?,
      epgUrl: json['epgUrl'] as String?,
      dohEndpoint: json['dohEndpoint'] as String?,
      userAgent: json['userAgent'] as String?,
      referer: json['referer'] as String?,
      cookie: json['cookie'] as String?,
      origin: json['origin'] as String?,
      manifestType: json['manifestType'] as String?,
      drm: DrmConfig.fromJson(json['drm']),
      headers: json['headers'] is Map
          ? Map<String, String>.from(
              (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          : const {},
      importLive: json['importLive'] as bool? ?? true,
      importVod: json['importVod'] as bool? ?? true,
      importSeries: json['importSeries'] as bool? ?? true,
      hideAllCategory: json['hideAllCategory'] as bool? ?? false,
      authorization: json['authorization'] as String?,
      requestType: json['requestType'] as String?,
      subtitleUrl: json['subtitleUrl'] as String?,
      streamFormat: json['streamFormat'] as String?,
      parserType: json['parserType'] as String?,
      stalkerToken: json['stalkerToken'] as String?,
      stalkerExpiry: json['stalkerExpiry'] as String?,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSync: json['lastSync'] != null
          ? DateTime.tryParse(json['lastSync'] as String)
          : null,
      channelCount: json['channelCount'] as int? ?? parsedChannels.length,
      channels: parsedChannels,
    );
  }
}
