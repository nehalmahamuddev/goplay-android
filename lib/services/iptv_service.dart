import 'package:dio/dio.dart';

import '../models/channel.dart';
import '../models/drm_config.dart';
import '../models/iptv_playlist.dart';
import 'iptv/iptv_source_adapter.dart';
import 'iptv/iptv_storage_adapter.dart';
import 'iptv/playlist_parser.dart' as playlist_parser;
import 'iptv/playlist_parser.dart' show ParsedPlaylistResult;

export 'iptv/iptv_source_adapter.dart'
    show DioIptvSourceAdapter, IptvSourceAdapter, StalkerTestResult;
export 'iptv/iptv_storage_adapter.dart'
    show
        HiveIptvStorageAdapter,
        InMemoryIptvStorageAdapter,
        IptvStorageAdapter;
export 'iptv/playlist_parser.dart'
    show
        ParsedPlaylistResult,
        PlaylistParseParams,
        buildM3uExportString,
        kEpgQualityRegex,
        lookupEpgProgrammesForChannel,
        normalizeEpgKey,
        parseM3uOrJsonContent,
        parseXmltvEpg;
export 'iptv/stream_url_parser.dart' show StreamUrlParser, parseUrlWithParams;

/// Facade coordinating IPTV storage persistence and remote/local playlist
/// ingestion through pluggable [IptvStorageAdapter] and [IptvSourceAdapter] seams.
class IptvService {
  IptvService({
    Dio? dio,
    IptvStorageAdapter? storage,
    IptvSourceAdapter? source,
  })  : _storage = storage ?? HiveIptvStorageAdapter(),
        _source = source ?? DioIptvSourceAdapter(dio: dio);

  final IptvStorageAdapter _storage;
  final IptvSourceAdapter _source;

  // ─── Storage Delegation ──────────────────────────────────────────

  Future<List<IptvPlaylist>> getSavedPlaylists() =>
      _storage.getSavedPlaylists();

  Future<void> savePlaylist(IptvPlaylist playlist) =>
      _storage.savePlaylist(playlist);

  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists) =>
      _storage.saveAllPlaylists(playlists);

  Future<void> deletePlaylist(String id) => _storage.deletePlaylist(id);

  IptvGlobalSettings loadGlobalSettings() => _storage.loadGlobalSettings();

  Future<void> saveGlobalSettings(IptvGlobalSettings settings) =>
      _storage.saveGlobalSettings(settings);

  Map<String, IptvViewConfig> loadViewConfigs() => _storage.loadViewConfigs();

  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs) =>
      _storage.saveViewConfigs(configs);

  Map<String, IptvBookmarkItem> loadBookmarks() => _storage.loadBookmarks();

  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks) =>
      _storage.saveBookmarks(bookmarks);

  List<IptvEpgSource> loadSavedEpgSources() =>
      _storage.loadSavedEpgSources();

  Future<void> saveEpgSources(List<IptvEpgSource> sources) =>
      _storage.saveEpgSources(sources);

  /// Formats one or more [playlists] as a standard `#EXTM3U` document.
  static String buildM3uExportString(Iterable<IptvPlaylist> playlists) =>
      playlist_parser.buildM3uExportString(playlists);

  // ─── Playlist Ingestion & Probe Delegation ───────────────────────

  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist) =>
      _source.fetchAndParse(playlist);

  Future<List<Channel>> parseM3uFromUrl(
    String url,
    String playlistId, {
    Map<String, String>? headers,
  }) async {
    final res = await parseM3uFromUrlWithMeta(url, playlistId, headers: headers);
    return res.channels;
  }

  Future<ParsedPlaylistResult> parseM3uFromUrlWithMeta(
    String url,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
    String? requestType,
  }) =>
      _source.parseM3uFromUrlWithMeta(
        url,
        playlistId,
        headers: headers,
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
        requestType: requestType,
      );

  Future<List<Channel>> parseM3uFromFileOrText(
    String pathOrText,
    String playlistId,
  ) async {
    final res = await parseM3uFromFileOrTextWithMeta(pathOrText, playlistId);
    return res.channels;
  }

  Future<ParsedPlaylistResult> parseM3uFromFileOrTextWithMeta(
    String pathOrText,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
  }) =>
      _source.parseM3uFromFileOrTextWithMeta(
        pathOrText,
        playlistId,
        headers: headers,
        defaultDrm: defaultDrm,
        defaultManifestType: defaultManifestType,
      );

  Future<Channel> resolveChannelForPlayback(Channel ch) =>
      _source.resolveChannelForPlayback(ch);

  Future<Map<String, List<IptvEpgProgramme>>> fetchAndParseEpg(
    String epgUrl, {
    Map<String, String>? headers,
  }) =>
      _source.fetchAndParseEpg(epgUrl, headers: headers);

  Future<List<Channel>> fetchXtreamChannels({
    required String hostUrl,
    required String username,
    required String password,
    required String playlistId,
    bool importLive = true,
    bool importVod = true,
    bool importSeries = true,
    Map<String, String>? headers,
    String streamFormat = 'TS',
    String parserType = 'API Codes',
  }) =>
      _source.fetchXtreamChannels(
        hostUrl: hostUrl,
        username: username,
        password: password,
        playlistId: playlistId,
        importLive: importLive,
        importVod: importVod,
        importSeries: importSeries,
        headers: headers,
        streamFormat: streamFormat,
        parserType: parserType,
      );

  Future<List<Channel>> fetchStalkerChannels({
    required String portalUrl,
    required String macAddress,
    required String playlistId,
  }) =>
      _source.fetchStalkerChannels(
        portalUrl: portalUrl,
        macAddress: macAddress,
        playlistId: playlistId,
      );

  Future<String?> probeUrlMimeType(
    String url, {
    Map<String, String>? headers,
  }) =>
      _source.probeUrlMimeType(url, headers: headers);

  Future<StalkerTestResult> testStalkerConnection({
    required String portalUrl,
    required String macAddress,
  }) =>
      _source.testStalkerConnection(
        portalUrl: portalUrl,
        macAddress: macAddress,
      );
}
