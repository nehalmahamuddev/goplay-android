import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

/// Listens for live playlist & category updates via [CatalogRepository] without
/// reaching into Supabase Realtime directly from UI widgets.
class CategoryM3uAutoSyncObserver extends ConsumerStatefulWidget {
  final Widget child;
  final Duration pollInterval;
  final Duration resumeVersionCooldown;

  const CategoryM3uAutoSyncObserver({
    super.key,
    required this.child,
    this.pollInterval = const Duration(minutes: 15),
    this.resumeVersionCooldown = const Duration(minutes: 2),
  });

  @override
  ConsumerState<CategoryM3uAutoSyncObserver> createState() =>
      _CategoryM3uAutoSyncObserverState();
}

class _CategoryM3uAutoSyncObserverState
    extends ConsumerState<CategoryM3uAutoSyncObserver>
    with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<void>? _remoteSub;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.pollInterval, (_) => _pollM3u());
    _subscribeRemoteChanges();
  }

  void _subscribeRemoteChanges() {
    _remoteSub = ref
        .read(catalogRepositoryProvider)
        .watchRemoteCatalogChanges()
        .listen(
      (_) => _checkCategoryVersions(forceM3uIfUnchanged: true),
      onError: (Object e) {
        debugPrint('CategoryM3uAutoSyncObserver: realtime stream error: $e');
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    await _pollM3u();
    await _checkCategoryVersions(cooldown: widget.resumeVersionCooldown);
  }

  Future<void> _pollM3u() async {
    if (_inFlight || !mounted) return;
    _inFlight = true;
    try {
      await ref.read(catalogRepositoryProvider).refreshM3uDirectly(
            minInterval: const Duration(seconds: 15),
          );
    } catch (e) {
      debugPrint('CategoryM3uAutoSyncObserver: poll failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _checkCategoryVersions({
    Duration cooldown = Duration.zero,
    bool forceM3uIfUnchanged = false,
  }) async {
    if (!mounted) return;
    try {
      final repo = ref.read(catalogRepositoryProvider);
      if (forceM3uIfUnchanged) {
        await repo.refreshM3uDirectly(force: true);
      }
      await repo.checkForCategoryChangesIfDue(cooldown: cooldown);
    } catch (e) {
      debugPrint('CategoryM3uAutoSyncObserver: version check failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_remoteSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
