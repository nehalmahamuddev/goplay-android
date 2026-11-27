import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../models/event.dart';
import 'playback/playback_session.dart';

/// Convenience launcher delegating Live Event launch prep to [PlaybackSessionCoordinator].
class EventStreamLauncher {
  EventStreamLauncher._();

  static const PlaybackSessionCoordinator _coordinator = PlaybackSessionCoordinator();

  /// Resolves cached event streams and navigates immediately to `PlayerScreen`.
  static Future<void> launch(BuildContext context, SportEvent event) async {
    final args = _coordinator.buildEventLaunch(event);
    if (args != null) {
      await context.push(args.routeLocation, extra: args.toExtra());
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No active streams available yet. Check back closer to kickoff.'),
        backgroundColor: GoPlayTheme.error,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
