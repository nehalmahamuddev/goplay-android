import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/app_providers.dart';

/// Coordinates automatic direct M3U syncing and minimal-DB admin change
/// detection while the main app shell is alive:
///
/// 1. Periodically refreshes locally saved category `m3u_url`s every 15 minutes
///    with zero Supabase DB queries.
/// 2. On app resume, refreshes saved M3U links directly and checks the single
///    `app_settings.channels_version` field (debounced) to catch admin edits.
/// 3. Listens to Supabase Realtime updates on `public.app_settings` (`id = 1`)
///    so mid-session admin `m3u_url` changes propagate immediately.
class CategoryM3uAutoSyncObserver extends ConsumerStatefulWidget {
  final Widget child;
  final Duration pollInterval;

  const CategoryM3uAutoSyncObserver({
    super.key,
    required this.child,
    this.pollInterval = const Duration(minutes: 15),
  });

  @override
  ConsumerState<CategoryM3uAutoSyncObserver> createState() =>
      _CategoryM3uAutoSyncObserverState();
}

class _CategoryM3uAutoSyncObserverState
    extends ConsumerState<CategoryM3uAutoSyncObserver>
    with WidgetsBindingObserver {
  Timer? _periodicTimer;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPeriodicM3uSync();
    _subscribeToAppSettingsRealtime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _unsubscribeRealtime();
    super.dispose();
  }

  void _startPeriodicM3uSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(widget.pollInterval, (_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(syncServiceProvider)
            .refreshM3uDirectly()
            .catchError((_) => false),
      );
    });
  }

  void _subscribeToAppSettingsRealtime() {
    try {
      final client = Supabase.instance.client;
      final channel = client.channel('public:app_settings:m3u_sync');
      channel
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'app_settings',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: 1,
            ),
            callback: (payload) {
              if (!mounted) return;
              final newVersion = payload.newRecord['channels_version'] as int?;
              unawaited(
                ref
                    .read(syncServiceProvider)
                    .syncIfRemoteVersionNewer(newVersion)
                    .catchError((_) => false),
              );
            },
          )
          .subscribe();
      _realtimeChannel = channel;
    } catch (_) {
      // Supabase may be uninitialized in tests or offline environments.
    }
  }

  void _unsubscribeRealtime() {
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_handleResume());
    }
  }

  Future<void> _handleResume() async {
    final syncService = ref.read(syncServiceProvider);
    try {
      // Check for admin category/m3u_url changes first so a direct M3U refresh
      // never races with an updated or cleared URL.
      final didFullSync = await syncService.checkForCategoryChangesIfDue();
      if (!didFullSync && mounted) {
        await syncService.refreshM3uDirectly(
          minInterval: const Duration(seconds: 15),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
