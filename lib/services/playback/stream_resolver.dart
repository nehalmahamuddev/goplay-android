import '../../models/channel.dart';
import '../../models/event.dart';
import '../iptv_service.dart';
import '../stream_decryptor.dart';

/// Seam isolating external encrypted stream decryption and IPTV portal resolution.
abstract class StreamResolver {
  List<Channel>? getCachedChannelStreams(Channel channel);

  Future<List<Channel>> resolveEncryptedChannel(Channel channel);

  List<Channel>? getCachedEventStreams(SportEvent event);

  Future<List<Channel>> resolveSportEvent(SportEvent event);

  Future<Channel> resolveIptvChannel(Channel channel, {IptvService? iptvService});
}

/// Default production adapter backed by [StreamDecryptor] and [IptvService].
class DefaultStreamResolver implements StreamResolver {
  const DefaultStreamResolver();

  @override
  List<Channel>? getCachedChannelStreams(Channel channel) {
    final url = channel.streamUrl.trim();
    if (url.isEmpty) return null;
    return StreamDecryptor.getCachedStreams(url, channel.id);
  }

  @override
  Future<List<Channel>> resolveEncryptedChannel(Channel channel) {
    return StreamDecryptor.fetchChannelStreams(
      linksPath: channel.streamUrl,
      channelId: channel.id,
      channelName: channel.name,
      category: channel.category,
      logo: channel.logo,
    );
  }

  @override
  List<Channel>? getCachedEventStreams(SportEvent event) {
    final linksPath = event.links;
    if (linksPath == null || linksPath.isEmpty) return null;
    return StreamDecryptor.getCachedStreams(linksPath, event.id);
  }

  @override
  Future<List<Channel>> resolveSportEvent(SportEvent event) async {
    final linksPath = event.links;
    if (linksPath == null || linksPath.isEmpty) return const <Channel>[];
    return StreamDecryptor.fetchAndDecryptStreams(
      linksPath: linksPath,
      eventId: event.id,
      eventTitle: '${event.homeTeam.name} vs ${event.awayTeam.name}',
      logo: event.banner,
    );
  }

  @override
  Future<Channel> resolveIptvChannel(Channel channel, {IptvService? iptvService}) async {
    final service = iptvService ?? IptvService();
    return service.resolveChannelForPlayback(channel);
  }
}
