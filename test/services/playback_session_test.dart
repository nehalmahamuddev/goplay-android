import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/channel.dart';
import 'package:goplay/models/drm_config.dart';
import 'package:goplay/models/event.dart';
import 'package:goplay/models/stream_server.dart';
import 'package:goplay/services/iptv_service.dart';
import 'package:goplay/services/playback/playback_session.dart';
import 'package:goplay/services/playback/stream_resolver.dart';

class _FakeStreamResolver implements StreamResolver {
  List<Channel>? cachedChannelStreams;
  List<Channel> resolvedChannelStreams = const [];
  bool throwOnChannelResolve = false;

  List<Channel>? cachedEventStreams;
  List<Channel> resolvedEventStreams = const [];
  bool throwOnEventResolve = false;

  Channel? resolvedIptv;

  @override
  List<Channel>? getCachedChannelStreams(Channel channel) => cachedChannelStreams;

  @override
  Future<List<Channel>> resolveEncryptedChannel(Channel channel) async {
    if (throwOnChannelResolve) throw Exception('resolve failed');
    return resolvedChannelStreams;
  }

  @override
  List<Channel>? getCachedEventStreams(SportEvent event) => cachedEventStreams;

  @override
  Future<List<Channel>> resolveSportEvent(SportEvent event) async {
    if (throwOnEventResolve) throw Exception('event failed');
    return resolvedEventStreams;
  }

  @override
  Future<Channel> resolveIptvChannel(Channel channel, {IptvService? iptvService}) async {
    return resolvedIptv ?? channel;
  }
}

void main() {
  group('PlaybackSessionCoordinator', () {
    test('buildChannelLaunch expands active non-encrypted StreamServers when multiple exist', () {
      final ch = Channel(
        id: 'sony_ten',
        name: 'Sony Ten 1',
        category: 'sports',
        streamUrl: 'https://primary.test/stream.m3u8',
        streamServers: const [
          StreamServer(id: 's1', channelId: 'sony_ten', name: 'HD 1', streamUrl: 'https://cdn1.test/1.m3u8', active: true),
          StreamServer(id: 's2', channelId: 'sony_ten', name: 'HD 2', streamUrl: 'https://cdn2.test/2.m3u8', active: true),
          StreamServer(id: 's3', channelId: 'sony_ten', name: 'Encrypted', streamUrl: 'pro/foo.txt', active: true),
          StreamServer(id: 's4', channelId: 'sony_ten', name: 'Off', streamUrl: 'https://off.test/4.m3u8', active: false),
        ],
      );

      const coordinator = PlaybackSessionCoordinator();
      final args = coordinator.buildChannelLaunch(ch, scope: [ch]);

      expect(args.routeLocation, '/player/sony_ten');
      expect(args.dynamicChannels, hasLength(2));
      expect(args.dynamicChannels!.map((s) => s.streamUrl), [
        'https://cdn1.test/1.m3u8',
        'https://cdn2.test/2.m3u8',
      ]);
      expect(args.eventChannels, isNull); // scope length < 2
    });

    test('selectChannel resolves encrypted manifests through StreamResolver seam', () async {
      final fakeResolver = _FakeStreamResolver()
        ..resolvedChannelStreams = [
          Channel(
            id: 'enc_ch_srv_1',
            name: 'Server 1',
            streamUrl: 'https://resolved.test/1.m3u8',
          ),
        ];

      final coordinator = PlaybackSessionCoordinator(resolver: fakeResolver);
      final catalog = [
        Channel(id: 'enc_ch', name: 'Encrypted Ch', streamUrl: 'pro/secret.txt'),
      ];

      final initial = coordinator.createInitialState(
        const PlaybackLaunchArgs(channelId: 'enc_ch'),
      );
      final next = await coordinator.selectChannel(initial, 'enc_ch', catalog);

      expect(next.currentChannelId, 'enc_ch');
      expect(next.servers, hasLength(1));
      expect(next.activePlayableChannel(catalog.first).streamUrl, 'https://resolved.test/1.m3u8');
      expect(next.resolutionFailed, isFalse);

      // Failure path
      fakeResolver.throwOnChannelResolve = true;
      final failed = await coordinator.selectChannel(initial, 'enc_ch', catalog);
      expect(failed.resolutionFailed, isTrue);
      expect(failed.isResolving, isFalse);
    });

    test('resolveSportEvent transitions to resolved stream and handles missing links', () async {
      final fakeResolver = _FakeStreamResolver()
        ..resolvedEventStreams = [
          Channel(
            id: 'live_ev1_0',
            name: 'Live Feed 1',
            streamUrl: 'https://match.test/live.m3u8',
          ),
        ];
      final coordinator = PlaybackSessionCoordinator(resolver: fakeResolver);

      final eventWithLinks = SportEvent(
        id: 'ev1',
        sport: 'Cricket',
        league: 'ICC',
        homeTeam: const Team(name: 'Team A'),
        awayTeam: const Team(name: 'Team B'),
        startTime: DateTime.utc(2026, 11, 27, 12, 0),
        status: 'live',
        channels: const [],
        linkNames: const [],
        links: 'pro/match.txt',
      );

      final launch = coordinator.buildEventLaunch(eventWithLinks);
      expect(launch, isNotNull);
      final initState = coordinator.createInitialState(launch!);
      expect(initState.isResolving, isTrue);

      final resolved = await coordinator.resolveSportEvent(initState, eventWithLinks);
      expect(resolved.isResolving, isFalse);
      expect(resolved.resolutionFailed, isFalse);
      expect(resolved.servers.single.streamUrl, 'https://match.test/live.m3u8');
    });

    test('resolveRelatedChannels preserves event scope and excludes synthetic _server_ entries by default', () {
      final catalog = [
        Channel(id: 'c1', name: 'C1', category: 'sports', streamUrl: 'https://1.m3u8'),
        Channel(id: 'c1_server_1', name: 'S1', category: 'sports', streamUrl: 'https://1a.m3u8'),
        Channel(id: 'c2', name: 'C2', category: 'news', streamUrl: 'https://2.m3u8'),
      ];

      final byCategory = PlaybackSessionCoordinator.resolveRelatedChannels(
        catalog: catalog,
        category: 'sports',
      );
      expect(byCategory.map((c) => c.id), ['c1']);

      final byScope = PlaybackSessionCoordinator.resolveRelatedChannels(
        catalog: catalog,
        eventChannels: ['c2', 'c1'],
        category: 'sports',
      );
      expect(byScope.map((c) => c.id), ['c2', 'c1']);
    });

    test('prepareIptvLaunch uses StreamResolver for lazy Stalker/ClearKey and URL-encodes ID', () async {
      final rawIptv = Channel(
        id: 'iptv:stalker/42',
        name: 'Stalker 42',
        streamUrl: 'http://portal/server/load.php?action=create_link&cmd=123',
        drm: const DrmConfig(type: DrmType.clearkey, licenseUrl: 'https://keys.test/ck'),
      );
      final resolvedIptv = Channel(
        id: 'iptv:stalker/42',
        name: 'Stalker 42',
        streamUrl: 'https://cdn.test/resolved.m3u8',
      );

      final fakeResolver = _FakeStreamResolver()..resolvedIptv = resolvedIptv;
      final coordinator = PlaybackSessionCoordinator(resolver: fakeResolver);

      expect(PlaybackSessionCoordinator.needsIptvResolution(rawIptv), isTrue);

      final launch = await coordinator.prepareIptvLaunch(
        rawIptv,
        scopeChannels: [rawIptv],
      );
      expect(launch.routeLocation, '/player/iptv%3Astalker%2F42');
      expect(launch.dynamicChannels!.single.streamUrl, 'https://cdn.test/resolved.m3u8');
    });
  });
}
