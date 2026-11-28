import 'package:flutter/foundation.dart';
import '../../models/channel.dart';
import '../../models/event.dart';
import '../iptv_service.dart';
import 'stream_resolver.dart';

/// Typed navigation payload passed into `PlayerScreen` via GoRouter `extra`.
@immutable
class PlaybackLaunchArgs {
  final String channelId;
  final List<String>? eventChannels;
  final List<Channel>? dynamicChannels;
  final SportEvent? sportEvent;
  final bool forceFullscreen;

  const PlaybackLaunchArgs({
    required this.channelId,
    this.eventChannels,
    this.dynamicChannels,
    this.sportEvent,
    this.forceFullscreen = false,
  });

  String get routeLocation => '/player/${Uri.encodeComponent(channelId)}';

  Map<String, dynamic> toExtra() => {
        if (eventChannels != null) 'eventChannels': eventChannels,
        if (dynamicChannels != null) 'dynamicChannels': dynamicChannels,
        if (sportEvent != null) 'sportEvent': sportEvent,
        'forceFullscreen': forceFullscreen,
      };

  factory PlaybackLaunchArgs.fromExtra(Object? extra, String channelId) {
    if (extra is PlaybackLaunchArgs) return extra;
    if (extra is Map<String, dynamic>) {
      return PlaybackLaunchArgs(
        channelId: channelId,
        eventChannels: (extra['eventChannels'] as List?)?.cast<String>(),
        dynamicChannels: (extra['dynamicChannels'] as List?)?.cast<Channel>(),
        sportEvent: extra['sportEvent'] as SportEvent?,
        forceFullscreen: extra['forceFullscreen'] as bool? ?? false,
      );
    }
    return PlaybackLaunchArgs(channelId: channelId);
  }
}

/// Immutable state snapshot observed by `PlayerScreen` during channel/event switching.
@immutable
class PlaybackSessionState {
  final String currentChannelId;
  final List<Channel> servers;
  final int activeServerIndex;
  final List<Channel> resolvedDynamicChannels;
  final bool isResolving;
  final bool resolutionFailed;

  const PlaybackSessionState({
    required this.currentChannelId,
    this.servers = const <Channel>[],
    this.activeServerIndex = 0,
    this.resolvedDynamicChannels = const <Channel>[],
    this.isResolving = false,
    this.resolutionFailed = false,
  });

  PlaybackSessionState copyWith({
    String? currentChannelId,
    List<Channel>? servers,
    int? activeServerIndex,
    List<Channel>? resolvedDynamicChannels,
    bool? isResolving,
    bool? resolutionFailed,
  }) {
    return PlaybackSessionState(
      currentChannelId: currentChannelId ?? this.currentChannelId,
      servers: servers ?? this.servers,
      activeServerIndex: activeServerIndex ?? this.activeServerIndex,
      resolvedDynamicChannels:
          resolvedDynamicChannels ?? this.resolvedDynamicChannels,
      isResolving: isResolving ?? this.isResolving,
      resolutionFailed: resolutionFailed ?? this.resolutionFailed,
    );
  }

  /// Returns the active server stream when multi-server is present, else [fallback].
  Channel activePlayableChannel(Channel fallback) {
    if (servers.isNotEmpty && activeServerIndex < servers.length) {
      return servers[activeServerIndex];
    }
    return fallback;
  }
}

/// Deep module unifying stream-server expansion, encrypted/IPTV resolution,
/// scope filtering, and player launch preparation behind a narrow interface.
class PlaybackSessionCoordinator {
  final StreamResolver resolver;

  const PlaybackSessionCoordinator({
    this.resolver = const DefaultStreamResolver(),
  });

  /// True when a stream URL points to an encrypted PlayZ manifest (`pro/*.txt`).
  static bool isEncryptedManifestUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    return trimmed.startsWith('pro/') || trimmed.contains('.txt');
  }

  /// True when an IPTV channel requires lazy Stalker `create_link` or remote ClearKey lookup.
  static bool needsIptvResolution(Channel channel) {
    return channel.streamUrl.contains('action=create_link') ||
        (channel.drm?.isClearKey == true &&
            (channel.drm?.clearKeys?.isEmpty ?? true) &&
            channel.drm?.licenseUrl != null);
  }

  /// Expands active direct [StreamServer] entries into playable [Channel] servers.
  static List<Channel> expandPlayableServers(Channel channel) {
    final activeServers = channel.streamServers
        .where(
          (s) =>
              s.active &&
              s.streamUrl.trim().isNotEmpty &&
              !isEncryptedManifestUrl(s.streamUrl),
        )
        .toList();
    if (activeServers.isEmpty) return const <Channel>[];

    return activeServers
        .map(
          (s) => s.toPlayableChannel(
            parentChannelId: channel.id,
            parentName: channel.name,
            logo: channel.logo,
            category: channel.category,
          ),
        )
        .toList(growable: false);
  }

  /// Single source of truth for merging resolved/refreshed channels, scoped
  /// dynamic channels, and static catalog into one priority-ordered list.
  static List<Channel> mergeCatalog({
    required List<Channel> catalog,
    List<Channel>? dynamicChannels,
    List<Channel> resolvedDynamicChannels = const <Channel>[],
    Channel? eventPlaceholder,
  }) {
    final seenIds = <String>{};
    final merged = <Channel>[];
    void addAllUnique(Iterable<Channel>? list) {
      if (list == null) return;
      for (final ch in list) {
        if (seenIds.add(ch.id)) {
          merged.add(ch);
        }
      }
    }

    addAllUnique(resolvedDynamicChannels);
    addAllUnique(dynamicChannels);
    addAllUnique(catalog);
    if (eventPlaceholder != null && seenIds.add(eventPlaceholder.id)) {
      merged.add(eventPlaceholder);
    }
    return merged;
  }

  /// Single source of truth for resolving adjacent channels in the player's
  /// prev/next buttons, side channel panel, and fullscreen top chip strip.
  static List<Channel> resolveRelatedChannels({
    required List<Channel> catalog,
    List<String>? eventChannels,
    List<Channel>? dynamicChannels,
    List<Channel> resolvedDynamicChannels = const <Channel>[],
    String? category,
  }) {
    final all = mergeCatalog(
      catalog: catalog,
      dynamicChannels: dynamicChannels,
      resolvedDynamicChannels: resolvedDynamicChannels,
    );

    if (eventChannels != null) {
      final byId = <String, Channel>{};
      for (final ch in all) {
        byId.putIfAbsent(ch.id, () => ch);
      }
      return [
        for (final id in eventChannels)
          if (byId.containsKey(id)) byId[id]!,
      ];
    }

    return all
        .where((c) => c.category == category && !c.id.contains('_server_'))
        .toList(growable: false);
  }

  /// Builds typed launch arguments for a TV or M3U channel across every screen.
  PlaybackLaunchArgs buildChannelLaunch(
    Channel channel, {
    List<Channel>? scope,
    bool forceFullscreen = false,
  }) {
    final scopeIds = (scope != null && scope.length > 1)
        ? scope.map((c) => c.id).toList(growable: false)
        : null;

    // 1. Direct DB multi-server expansion (active only when >= 2 servers exist)
    final expanded = expandPlayableServers(channel);
    if (expanded.length > 1) {
      return PlaybackLaunchArgs(
        channelId: channel.id,
        eventChannels: scopeIds,
        dynamicChannels: expanded,
        forceFullscreen: forceFullscreen,
      );
    }

    // 2. Direct single-stream channel
    if (!isEncryptedManifestUrl(channel.streamUrl)) {
      return PlaybackLaunchArgs(
        channelId: channel.id,
        eventChannels: scopeIds,
        forceFullscreen: forceFullscreen,
      );
    }

    // 3. Cached PlayZ encrypted manifest
    final cached = resolver.getCachedChannelStreams(channel);
    return PlaybackLaunchArgs(
      channelId: channel.id,
      eventChannels: scopeIds,
      dynamicChannels: (cached != null && cached.isNotEmpty) ? cached : null,
      forceFullscreen: forceFullscreen,
    );
  }

  /// Builds typed launch arguments for a live sports event, or `null` when
  /// neither event channels nor encrypted manifest links exist yet.
  PlaybackLaunchArgs? buildEventLaunch(SportEvent event) {
    if (event.channels.isNotEmpty) {
      return PlaybackLaunchArgs(
        channelId: event.channels.first,
        eventChannels: event.channels,
        sportEvent: event,
        forceFullscreen: true,
      );
    }

    final linksPath = event.links;
    if (linksPath != null && linksPath.isNotEmpty) {
      final cached = resolver.getCachedEventStreams(event);
      if (cached != null && cached.isNotEmpty) {
        return PlaybackLaunchArgs(
          channelId: cached.first.id,
          eventChannels: cached.map((c) => c.id).toList(growable: false),
          dynamicChannels: cached,
          sportEvent: event,
          forceFullscreen: true,
        );
      }

      return PlaybackLaunchArgs(
        channelId: 'live_${event.id.replaceAll('/', '_')}_0',
        sportEvent: event,
        forceFullscreen: true,
      );
    }

    return null;
  }

  /// Resolves lazy IPTV Stalker/ClearKey endpoints and returns typed launch args.
  Future<PlaybackLaunchArgs> prepareIptvLaunch(
    Channel channel, {
    required List<Channel> scopeChannels,
    IptvService? iptvService,
  }) async {
    final resolved = needsIptvResolution(channel)
        ? await resolver.resolveIptvChannel(channel, iptvService: iptvService)
        : channel;

    final updatedScope = [
      for (final c in scopeChannels) (c.id == resolved.id) ? resolved : c,
    ];
    if (!updatedScope.any((c) => c.id == resolved.id)) {
      updatedScope.insert(0, resolved);
    }

    return PlaybackLaunchArgs(
      channelId: resolved.id,
      eventChannels: updatedScope.map((c) => c.id).toList(growable: false),
      dynamicChannels: updatedScope,
      forceFullscreen: true,
    );
  }

  /// Computes initial session state upon opening `PlayerScreen`.
  PlaybackSessionState createInitialState(PlaybackLaunchArgs args) {
    final dynamicList = args.dynamicChannels;
    final hasDistinctPlaylistChannels = dynamicList != null &&
        dynamicList.isNotEmpty &&
        args.eventChannels != null &&
        dynamicList.any((c) => c.id == args.channelId && !c.id.contains('_server_'));

    if (dynamicList != null && dynamicList.isNotEmpty && !hasDistinctPlaylistChannels) {
      return PlaybackSessionState(
        currentChannelId: args.channelId,
        servers: List<Channel>.from(dynamicList),
        activeServerIndex: 0,
      );
    }

    if (args.sportEvent != null) {
      return PlaybackSessionState(
        currentChannelId: args.channelId,
        isResolving: true,
      );
    }

    return PlaybackSessionState(currentChannelId: args.channelId);
  }

  /// Resolves channel selection, server expansion, and lazy encrypted streams.
  Future<PlaybackSessionState> selectChannel(
    PlaybackSessionState current,
    String id,
    List<Channel> allChannels,
  ) async {
    Channel? candidate;
    for (final c in allChannels) {
      if (c.id == id) {
        candidate = c;
        break;
      }
    }

    if (candidate != null) {
      final servers = expandPlayableServers(candidate);
      if (servers.isNotEmpty) {
        return current.copyWith(
          currentChannelId: candidate.id,
          servers: servers,
          activeServerIndex: 0,
          isResolving: false,
          resolutionFailed: false,
        );
      }

      if (isEncryptedManifestUrl(candidate.streamUrl)) {
        try {
          final streams = await resolver.resolveEncryptedChannel(candidate);
          if (streams.isNotEmpty) {
            final prefix = '${candidate.id}_';
            final mergedDynamic = [
              ...current.resolvedDynamicChannels.where((c) => !c.id.startsWith(prefix)),
              ...streams,
            ];
            return PlaybackSessionState(
              currentChannelId: candidate.id,
              servers: streams,
              activeServerIndex: 0,
              resolvedDynamicChannels: mergedDynamic,
              isResolving: false,
              resolutionFailed: false,
            );
          }
        } catch (_) {}

        return current.copyWith(
          currentChannelId: id,
          isResolving: false,
          resolutionFailed: true,
        );
      }
    }

    return current.copyWith(
      currentChannelId: id,
      servers: const <Channel>[],
      activeServerIndex: 0,
      isResolving: false,
      resolutionFailed: false,
    );
  }

  /// Resolves live sports event streams into dynamic server channels.
  Future<PlaybackSessionState> resolveSportEvent(
    PlaybackSessionState current,
    SportEvent event,
  ) async {
    final linksPath = event.links;
    if (linksPath == null || linksPath.isEmpty) {
      return current.copyWith(
        isResolving: false,
        resolutionFailed: true,
      );
    }

    try {
      final streams = await resolver.resolveSportEvent(event);
      if (streams.isNotEmpty) {
        final prefix = 'live_${event.id.replaceAll('/', '_')}';
        final mergedDynamic = [
          ...current.resolvedDynamicChannels.where((c) => !c.id.startsWith(prefix)),
          ...streams,
        ];
        return PlaybackSessionState(
          currentChannelId: streams.first.id,
          servers: streams,
          activeServerIndex: 0,
          resolvedDynamicChannels: mergedDynamic,
          isResolving: false,
          resolutionFailed: false,
        );
      }
    } catch (_) {}

    return current.copyWith(
      isResolving: false,
      resolutionFailed: true,
    );
  }
}
