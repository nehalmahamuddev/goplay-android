import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/channel.dart';
import 'playback/playback_session.dart';

/// Convenience launcher delegating TV/M3U channel launch prep to [PlaybackSessionCoordinator].
class ChannelStreamLauncher {
  ChannelStreamLauncher._();

  static const PlaybackSessionCoordinator _coordinator = PlaybackSessionCoordinator();

  /// Prepares playback launch arguments and pushes the player route.
  static Future<void> launch(
    BuildContext context,
    Channel channel, {
    List<Channel>? scope,
    bool forceFullscreen = false,
  }) async {
    final args = _coordinator.buildChannelLaunch(
      channel,
      scope: scope,
      forceFullscreen: forceFullscreen,
    );
    await context.push(args.routeLocation, extra: args.toExtra());
  }
}
