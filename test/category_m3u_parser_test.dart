import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/drm_config.dart';
import 'package:goplay/services/category_m3u_service.dart';

void main() {
  group('parseCategoryM3uContent', () {
    test('parses M3U entries into categoryId with headers and ClearKey DRM', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 tvg-id="tsports.bd" tvg-logo="https://img.test/ts.png" group-title="IgnoredGroup",T Sports HD
#EXTVLCOPT:http-user-agent=GoPlayAgent/1.0
#EXTVLCOPT:http-referrer=https://ref.test/
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100
https://cdn.test/tsports/index.mpd|Origin=https://origin.test
''';

      final channels = parseCategoryM3uContent(m3u, 'sports');

      expect(channels, hasLength(1));
      final ch = channels.single;
      expect(ch.category, 'sports');
      expect(ch.name, 'T Sports HD');
      expect(ch.logo, 'https://img.test/ts.png');
      expect(ch.tvgId, 'tsports.bd');
      expect(ch.streamUrl, 'https://cdn.test/tsports/index.mpd');
      expect(ch.headers['User-Agent'], 'GoPlayAgent/1.0');
      expect(ch.headers['Referer'], 'https://ref.test/');
      expect(ch.headers['Origin'], 'https://origin.test');
      expect(ch.drm?.type, DrmType.clearkey);
      expect(ch.drm?.kid, '00112233445566778899aabbccddeeff');
      expect(ch.drm?.key, 'ffeeddccbbaa99887766554433221100');
      expect(ch.streamServers, hasLength(1));
    });

    test('merges duplicate normalized channel names into one Channel with multiple StreamServers', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1 tvg-logo="https://img.test/sony.png",SONY AATH HD
https://s1.test/sony/live.m3u8|User-Agent=UA1
#EXTINF:-1,0. Sony aath
#EXTVLCOPT:http-user-agent=UA2
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=0123456789abcdef0123456789abcdef:fedcba9876543210fedcba9876543210
https://s2.test/sony/live.mpd
#EXTINF:-1,Other Channel
https://s1.test/other.m3u8
''';

      final channels = parseCategoryM3uContent(m3u, 'kids');

      expect(channels, hasLength(2));
      final merged = channels.first;
      expect(merged.displayName, 'Sony Aath');
      expect(merged.logo, 'https://img.test/sony.png');
      expect(merged.streamUrl, 'https://s1.test/sony/live.m3u8');
      expect(merged.streamServers, hasLength(2));
      expect(merged.streamServers[0].name, 'Server 1');
      expect(merged.streamServers[0].streamUrl, 'https://s1.test/sony/live.m3u8');
      expect(merged.streamServers[0].headers['User-Agent'], 'UA1');
      expect(merged.streamServers[1].name, 'Server 2');
      expect(merged.streamServers[1].streamUrl, 'https://s2.test/sony/live.mpd');
      expect(merged.streamServers[1].headers['User-Agent'], 'UA2');
      expect(merged.streamServers[1].drm?.type, DrmType.clearkey);
      expect(merged.streamServers[0].channelId, merged.id);
      expect(merged.streamServers[1].channelId, merged.id);
    });

    test('deduplicates identical stream URLs within the same merged channel', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1,Channel A
https://cdn.test/a.m3u8
#EXTINF:-1,Channel A
https://cdn.test/a.m3u8
''';

      final channels = parseCategoryM3uContent(m3u, 'bangla');
      expect(channels, hasLength(1));
      expect(channels.single.streamServers, hasLength(1));
    });

    test('generates deterministic stable IDs across channel reordering and URL token rotation', () {
      const m3uV1 = '''
#EXTM3U
#EXTINF:-1 tvg-id="ch-alpha",Alpha TV
https://cdn.test/alpha.m3u8?token=111
#EXTINF:-1,Beta News
https://cdn.test/beta.m3u8?token=222
''';

      const m3uV2 = '''
#EXTM3U
#EXTINF:-1,Beta News
https://cdn.test/beta.m3u8?token=999
#EXTINF:-1 tvg-id="ch-alpha",Alpha TV
https://cdn.test/alpha.m3u8?token=888
''';

      final v1 = parseCategoryM3uContent(m3uV1, 'news');
      final v2 = parseCategoryM3uContent(m3uV2, 'news');

      expect(v1[0].id, v2[1].id);
      expect(v1[1].id, v2[0].id);
      expect(v1[0].id, startsWith('m3u_news_'));
      expect(v1[0].id, isNot(equals(v1[1].id)));
    });

    test('supports JSON playlist content and returns empty for blank payloads', () {
      expect(parseCategoryM3uContent('   \n#EXTM3U\n', 'bangla'), isEmpty);

      const jsonPlaylist = '''
[
  {"name": "Bangla Vision", "url": "https://cdn.test/bv.m3u8", "logo": "https://img.test/bv.png"},
  {"name": "Bangla Vision", "url": "https://cdn2.test/bv.m3u8"}
]
''';
      final channels = parseCategoryM3uContent(jsonPlaylist, 'bangla');
      expect(channels, hasLength(1));
      expect(channels.single.category, 'bangla');
      expect(channels.single.streamServers, hasLength(2));
    });
  });
}
