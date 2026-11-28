import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/models/drm_config.dart';
import 'package:goplay/models/iptv_playlist.dart';
import 'package:goplay/providers/iptv_providers.dart';
import 'package:goplay/services/iptv_service.dart';
import 'package:goplay/services/stream_decryptor.dart';

class _FakeIptvSourceAdapter implements IptvSourceAdapter {
  _FakeIptvSourceAdapter(this.onFetch);

  final IptvPlaylist Function(IptvPlaylist) onFetch;

  @override
  Future<IptvPlaylist> fetchAndParse(IptvPlaylist playlist) async =>
      onFetch(playlist);

  @override
  Future<Map<String, List<IptvEpgProgramme>>> fetchAndParseEpg(
    String epgUrl, {
    Map<String, String>? headers,
  }) async =>
      const {};

  @override
  Future<List<Channel>> fetchStalkerChannels({
    required String portalUrl,
    required String macAddress,
    required String playlistId,
  }) async =>
      const [];

  @override
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
  }) async =>
      const [];

  @override
  Future<ParsedPlaylistResult> parseM3uFromFileOrTextWithMeta(
    String pathOrText,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
  }) async =>
      const ParsedPlaylistResult(channels: []);

  @override
  Future<ParsedPlaylistResult> parseM3uFromUrlWithMeta(
    String url,
    String playlistId, {
    Map<String, String>? headers,
    DrmConfig? defaultDrm,
    String? defaultManifestType,
    String? requestType,
  }) async =>
      const ParsedPlaylistResult(channels: []);

  @override
  Future<String?> probeUrlMimeType(
    String url, {
    Map<String, String>? headers,
  }) async =>
      'application/vnd.apple.mpegurl';

  @override
  Future<Channel> resolveChannelForPlayback(Channel ch) async => ch;

  @override
  Future<StalkerTestResult> testStalkerConnection({
    required String portalUrl,
    required String macAddress,
  }) async =>
      const StalkerTestResult(mac: '00:1A:79:00:00:01', token: 'tok');
}

void main() {
  group('StreamUrlParser & PlaylistParser', () {
    test('parsePipeHeaders and StreamDecryptor.parseStreamUrl share identical behavior', () {
      const raw =
          'https://cdn.example/live.m3u8|User-Agent=CustomAgent&Referer=https://ref.test';
      final direct = StreamUrlParser.parsePipeHeaders(raw);
      final compat = StreamDecryptor.parseStreamUrl(raw);

      expect(direct.url, 'https://cdn.example/live.m3u8');
      expect(direct.headers['User-Agent'], 'CustomAgent');
      expect(direct.headers['Referer'], 'https://ref.test');
      expect(compat.url, direct.url);
      expect(compat.headers, direct.headers);
    });

    test('parseUrlWithParams decodes exthttp Base64 headers and ClearKey params', () {
      final innerCustom = base64Encode(utf8.encode('custom-token-42'));
      final exthttp = base64Encode(
        utf8.encode('{"X-Test":"1","dt-custom-data":"$innerCustom"}'),
      );
      final parsed = StreamUrlParser.parseUrlWithParams(
        'https://cdn.test/video.mpd|exthttp=$exthttp&drmscheme=clearkey&drmlicense=00112233445566778899aabbccddeeff:11111111111111111111111111111111',
      );

      expect(parsed.url, 'https://cdn.test/video.mpd');
      expect(parsed.headers['X-Test'], '1');
      expect(parsed.headers['dt-custom-data'], 'custom-token-42');
      expect(parsed.drm?.type, DrmType.clearkey);
      expect(parsed.drm?.key, '11111111111111111111111111111111');
    });

    test('buildM3uExportString round-trips through parseM3uOrJsonContent', () {
      final playlist = IptvPlaylist(
        id: 'pl_1',
        name: 'Pack',
        sourceType: IptvSourceType.m3uUrl,
        url: 'https://m3u.test/pack.m3u',
        addedAt: DateTime.utc(2026, 11, 27),
        lastSync: DateTime.utc(2026, 11, 27),
        channels: [
          Channel(
            id: 'ch_1',
            name: 'Channel One FHD',
            streamUrl: 'https://cdn.test/1.m3u8',
            category: 'Sports',
            tvgId: 'ch1.id',
          ),
        ],
      );

      final exported = buildM3uExportString([playlist]);
      final reparsed = parseM3uOrJsonContent(exported, 'recheck');

      expect(reparsed.channels, hasLength(1));
      expect(reparsed.channels.single.name, 'Channel One FHD');
      expect(reparsed.channels.single.category, 'Sports');
      expect(reparsed.channels.single.tvgId, 'ch1.id');
      expect(reparsed.channels.single.quality, 'FHD');
    });
  });

  group('IptvStorageAdapter & derived selectedIptvPlaylistProvider', () {
    test('selectedIptvPlaylistProvider derives live updates and deletion without manual mirroring', () async {
      final initial = IptvPlaylist(
        id: 'pl_a',
        name: 'Initial Pack',
        sourceType: IptvSourceType.m3uUrl,
        url: 'https://m3u.test/a.m3u',
        addedAt: DateTime.utc(2026, 11, 27),
        lastSync: DateTime.utc(2026, 11, 27),
        channelCount: 1,
        channels: [
          Channel(
            id: 'c1',
            name: 'Old Channel',
            streamUrl: 'https://cdn.test/old.m3u8',
          ),
        ],
      );

      final storage = InMemoryIptvStorageAdapter([initial]);
      final source = _FakeIptvSourceAdapter(
        (pl) => pl.copyWith(
          name: 'Updated Pack',
          channelCount: 1,
          channels: [
            Channel(
              id: 'c2',
              name: 'New Channel',
              streamUrl: 'https://cdn.test/new.m3u8',
            ),
          ],
        ),
      );
      final service = IptvService(storage: storage, source: source);

      final container = ProviderContainer(
        overrides: [iptvServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(iptvPlaylistsProvider.future);
      container.read(selectedIptvPlaylistIdProvider.notifier).select('pl_a');
      expect(container.read(selectedIptvPlaylistProvider)?.name, 'Initial Pack');

      await container.read(iptvPlaylistsProvider.notifier).refreshPlaylist('pl_a');
      final afterRefresh = container.read(selectedIptvPlaylistProvider);
      expect(afterRefresh?.name, 'Updated Pack');
      expect(afterRefresh?.channels.single.id, 'c2');

      await container.read(iptvPlaylistsProvider.notifier).deletePlaylist('pl_a');
      expect(container.read(selectedIptvPlaylistProvider), isNull);
    });

    test('frequently-updating playlists revalidate when stale, deduplicate concurrent syncs, and match shifted channel IDs', () async {
      final staleTime = DateTime.now().subtract(const Duration(minutes: 10));
      final freshTime = DateTime.now().subtract(const Duration(seconds: 20));

      final stalePlaylist = IptvPlaylist(
        id: 'pl_freq',
        name: 'Rotating Tokens',
        sourceType: IptvSourceType.m3uUrl,
        url: 'https://m3u.test/rotating.m3u',
        addedAt: staleTime,
        lastSync: staleTime,
        channelCount: 1,
        channels: [
          Channel(
            id: 'pl_freq_c_sports.hd_1',
            name: 'Sports HD',
            category: 'Sports',
            tvgId: 'sports.hd',
            streamUrl: 'https://cdn.test/live.m3u8?token=expired',
          ),
        ],
      );

      final freshPlaylist = IptvPlaylist(
        id: 'pl_fresh',
        name: 'Fresh Pack',
        sourceType: IptvSourceType.m3uUrl,
        url: 'https://m3u.test/fresh.m3u',
        addedAt: freshTime,
        lastSync: freshTime,
        channelCount: 1,
        channels: [
          Channel(
            id: 'pl_fresh_c_1_1',
            name: 'Fresh One',
            streamUrl: 'https://cdn.test/fresh.m3u8',
          ),
        ],
      );

      expect(stalePlaylist.isCacheFresh, isTrue);
      expect(stalePlaylist.needsBackgroundRevalidation(), isTrue);
      expect(freshPlaylist.needsBackgroundRevalidation(), isFalse);

      var fetchCount = 0;
      final storage = InMemoryIptvStorageAdapter([stalePlaylist, freshPlaylist]);
      final source = _FakeIptvSourceAdapter((pl) {
        fetchCount++;
        if (pl.id == 'pl_freq') {
          // Simulate index shift (channel moved from index 1 -> index 2) and rotated token
          return pl.copyWith(
            lastSync: DateTime.now(),
            channelCount: 2,
            channels: [
              Channel(
                id: 'pl_freq_c_intro_1',
                name: 'Intro Channel',
                category: 'Info',
                streamUrl: 'https://cdn.test/intro.m3u8',
              ),
              Channel(
                id: 'pl_freq_c_sports.hd_2',
                name: 'Sports HD',
                category: 'Sports',
                tvgId: 'sports.hd',
                streamUrl: 'https://cdn.test/live.m3u8?token=fresh_123',
                headers: const {'Authorization': 'Bearer fresh_tok'},
              ),
            ],
          );
        }
        return pl;
      });

      final container = ProviderContainer(
        overrides: [
          iptvServiceProvider.overrideWithValue(
            IptvService(storage: storage, source: source),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(iptvPlaylistsProvider.future);

      // 1. Background stale sync updates only pl_freq (not pl_fresh).
      await container
          .read(iptvPlaylistsProvider.notifier)
          .syncStalePlaylists(maxAge: const Duration(minutes: 5));
      expect(fetchCount, 1);

      // 2. Concurrent refreshPlaylist calls share a single in-flight fetch.
      await Future.wait([
        container.read(iptvPlaylistsProvider.notifier).refreshPlaylist('pl_freq'),
        container.read(iptvPlaylistsProvider.notifier).refreshPlaylist('pl_freq'),
      ]);
      expect(fetchCount, 2);

      // 3. Failed stale channel resolves to the updated channel even across index shifts.
      final staleFailed = stalePlaylist.channels.single;
      final recovered = await container
          .read(iptvPlaylistsProvider.notifier)
          .refreshChannelFromSource(staleFailed);
      expect(recovered, isNotNull);
      expect(recovered!.id, 'pl_freq_c_sports.hd_2');
      expect(recovered.streamUrl, 'https://cdn.test/live.m3u8?token=fresh_123');
      expect(recovered.headers['Authorization'], 'Bearer fresh_tok');
    });
  });
}
