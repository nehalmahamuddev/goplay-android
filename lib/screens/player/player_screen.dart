import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../providers/app_providers.dart';
import '../../models/channel.dart';
import '../../models/event.dart';
import '../../widgets/player/channel_video_player.dart';
import '../../widgets/tv_focus_wrapper.dart';
import '../../services/stream_decryptor.dart';

// ─── Pre-cached top-level constants — zero per-frame allocations ─

// Top-bar gradient pre-cached — avoids allocation on every fullscreen build
const _kTopBarGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xDC000000), Color(0x78000000), Colors.transparent],
  ),
);

// Avatar decoration
const _kAvatarDeco = BoxDecoration(
  color: Color(0x14FFFFFF),
  shape: BoxShape.circle,
  border: Border.fromBorderSide(
    BorderSide(color: Color(0x1AFFFFFF), width: 1.0),
  ),
);

const _kSectionLabelStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.darkOnSurfaceVariant,
  fontSize: GoPlayType.sm,
  fontWeight: FontWeight.w700,
  height: GoPlayType.leadingFlat,
  letterSpacing: GoPlayType.trackingWide,
);

const _kTileNameActiveStyle = TextStyle(
  fontFamily: GoPlayType.family,
  height: GoPlayType.leadingSnug,
  color: GoPlayTheme.primary,
  fontSize: GoPlayType.base,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.1,
);
const _kTileNameNormalStyle = TextStyle(
  fontFamily: GoPlayType.family,
  height: GoPlayType.leadingSnug,
  color: GoPlayTheme.darkOnSurface,
  fontSize: GoPlayType.base,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.1,
);

const _kTileMetaActiveStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.primary,
  fontSize: GoPlayType.xs,
  height: GoPlayType.leadingSnug,
);
const _kTileMetaNormalStyle = TextStyle(
  fontFamily: GoPlayType.family,
  color: GoPlayTheme.darkOnSurfaceMuted,
  fontSize: GoPlayType.xs,
  height: GoPlayType.leadingSnug,
);

// Cached identity matrix — never reallocated
final _kIdentityMatrix = Matrix4.identity();
final _kHoverMatrix = Matrix4.translationValues(0.0, -1.0, 0.0);

class PlayerScreen extends ConsumerStatefulWidget {
  final String channelId;

  /// The ordered channel list this player session is scoped to.
  ///
  /// Despite the name this is not only an event's channels — it is "the list
  /// the user came from", and it drives prev/next, the side panel, and the
  /// top-bar chips. An event passes its own channels; the Home rails pass the
  /// rail they were tapped in.
  ///
  /// When null, the player falls back to every channel sharing the current
  /// channel's category. That fallback is right for the category grid and
  /// search, and wrong for any curated list — a caller that renders a specific
  /// set of channels must pass that set here, or the user will be dropped into
  /// the whole category on the first channel switch.
  final List<String>? eventChannels;
  final List<Channel>? dynamicChannels;
  final SportEvent? sportEvent;

  final bool forceFullscreen;

  const PlayerScreen({
    super.key,
    required this.channelId,
    this.eventChannels,
    this.dynamicChannels,
    this.sportEvent,
    this.forceFullscreen = false,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late String _currentChannelId;
  List<Channel> _currentChannelServers = [];
  int _activeServerIndex = 0;
  bool _controlsVisible = true;
  bool _isFullViewMode = false;
  bool _isScreenLocked = false;
  bool _showUnlockButton = false;
  Timer? _controlsTimer;
  Timer? _unlockButtonTimer;
  String? _lastHistoryChannelId;
  static const _pipChannel = MethodChannel('com.goplay/pip');
  bool _isTvDevice = false; // Set once in first build, used to skip orientation locks

  void _showUnlockPrompt() {
    _unlockButtonTimer?.cancel();
    setState(() {
      _showUnlockButton = true;
    });
    _unlockButtonTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showUnlockButton = false);
      }
    });
  }

  void _unlockScreen() {
    _unlockButtonTimer?.cancel();
    setState(() {
      _isScreenLocked = false;
      _showUnlockButton = false;
      _controlsVisible = true;
    });
    _startControlsTimer();
    HapticFeedback.mediumImpact();
  }

  // ── TV Panel Focus Routing ──────────────────────────────────────
  // Dedicated focus scope for the channel-list side panel.
  // When the user presses D-Pad Right from the player, focus shifts here.
  // When the user presses D-Pad Left from the channel list, focus returns to player.
  final FocusScopeNode _channelPanelFocusScope = FocusScopeNode(debugLabel: 'ChannelPanelScope');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'PlayPauseFocusNode');
  // Exposed to the inner ChannelVideoPlayerNative so it can call
  // _channelPanelFocusScope.requestFocus() when D-Pad Right is pressed.
  bool _channelPanelHasFocus = false;
  List<Channel> _resolvedDynamicChannels = [];
  bool _isResolvingStream = false;
  bool _resolutionFailed = false;

  void _handleServerSelected(int index) {
    if (_currentChannelServers.isEmpty || index < 0 || index >= _currentChannelServers.length) return;
    final previousServer = _activeServerIndex < _currentChannelServers.length
        ? _currentChannelServers[_activeServerIndex]
        : null;
    final nextServer = _currentChannelServers[index];

    setState(() => _activeServerIndex = index);

    if (mounted && previousServer != null && previousServer.id != nextServer.id) {
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.swap_calls_rounded, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${previousServer.name} unavailable. Switched to ${nextServer.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF14141E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.3), width: 0.8),
          ),
        ),
      );
    }
  }

  Future<void> _selectChannel(String id, List<Channel> allChannels) async {
    final candidate = allChannels.cast<Channel?>().firstWhere(
      (c) => c?.id == id,
      orElse: () => null,
    );
    if (candidate != null) {
      final activeServers = candidate.streamServers
          .where((s) => s.active && s.streamUrl.isNotEmpty && !s.streamUrl.startsWith('pro/') && !s.streamUrl.contains('.txt'))
          .toList();
      if (activeServers.isNotEmpty) {
        final streams = activeServers.map((s) => s.toPlayableChannel(
          parentChannelId: candidate.id,
          parentName: candidate.name,
          logo: candidate.logo,
          category: candidate.category,
        )).toList();

        if (mounted) {
          setState(() {
            _currentChannelId = candidate.id;
            _currentChannelServers = streams;
            _activeServerIndex = 0;
            _resolutionFailed = false;
          });
          _startControlsTimer();
          return;
        }
      }
    }
    if (candidate != null &&
        (candidate.streamUrl.startsWith('pro/') || candidate.streamUrl.contains('.txt'))) {
      if (mounted) setState(() => _isResolvingStream = true);
      try {
        final streams = await StreamDecryptor.fetchChannelStreams(
          linksPath: candidate.streamUrl,
          channelId: candidate.id,
          channelName: candidate.name,
          category: candidate.category,
          logo: candidate.logo,
        );
        if (streams.isNotEmpty && mounted) {
          setState(() {
            _isResolvingStream = false;
            _resolutionFailed = false;
            _resolvedDynamicChannels = [
              ..._resolvedDynamicChannels.where((c) => !c.id.startsWith('${candidate.id}_')),
              ...streams,
            ];
            _currentChannelId = candidate.id;
            _currentChannelServers = streams;
            _activeServerIndex = 0;
          });
          _startControlsTimer();
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isResolvingStream = false;
          _resolutionFailed = true;
        });
      }
    }
    if (mounted) {
      setState(() {
        _currentChannelId = id;
        _currentChannelServers = [];
        _activeServerIndex = 0;
        _resolutionFailed = false;
      });
      _startControlsTimer();
    }
  }

  Future<void> _resolveSportEvent(SportEvent event) async {
    final linksPath = event.links;
    if (linksPath == null || linksPath.isEmpty) {
      if (mounted) {
        setState(() {
          _isResolvingStream = false;
          _resolutionFailed = true;
        });
      }
      return;
    }

    try {
      final streams = await StreamDecryptor.fetchAndDecryptStreams(
        linksPath: linksPath,
        eventId: event.id,
        eventTitle: '${event.homeTeam.name} vs ${event.awayTeam.name}',
        logo: event.banner,
      );

      if (streams.isNotEmpty && mounted) {
        setState(() {
          _isResolvingStream = false;
          _resolutionFailed = false;
          _resolvedDynamicChannels = [
            ..._resolvedDynamicChannels.where((c) => !c.id.startsWith('live_${event.id.replaceAll('/', '_')}')),
            ...streams,
          ];
          _currentChannelId = streams.first.id;
          _currentChannelServers = streams;
          _activeServerIndex = 0;
        });
        _startControlsTimer();
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isResolvingStream = false;
        _resolutionFailed = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _currentChannelId = widget.channelId;
    if (widget.dynamicChannels != null && widget.dynamicChannels!.isNotEmpty) {
      _currentChannelServers = List<Channel>.from(widget.dynamicChannels!);
      _activeServerIndex = 0;
    } else if (widget.sportEvent != null) {
      _isResolvingStream = true;
      _resolveSportEvent(widget.sportEvent!);
    }
    _startControlsTimer();

    // Keep screen awake while player is active
    WakelockPlus.enable();

    if (widget.forceFullscreen) {
      _isFullViewMode = true;
      // Orientation lock deferred to first build() where we can detect TV
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyFullscreenOrientation();
      });
    }

    // Only enable PiP on app minimize when in Full View mode
    _pipChannel.invokeMethod('setPlayerActive', widget.forceFullscreen);
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPiPModeChanged') {
        final isInPiP = call.arguments as bool? ?? false;
        if (isInPiP) {
          setState(() {
            _controlsVisible = false;
          });
        }
      }
    });
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    // Use a longer hide delay on TV — remote navigation is slower than touch
    final delay = _isTvDevice ? const Duration(seconds: 8) : const Duration(seconds: 4);
    _controlsTimer = Timer(delay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onPlayerTap() {
    if (_isScreenLocked) {
      _showUnlockPrompt();
      return;
    }
    final next = !_controlsVisible;
    setState(() => _controlsVisible = next);
    if (next) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _onPlayerInteract() {
    if (_controlsVisible) {
      _startControlsTimer();
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullViewMode = !_isFullViewMode;
      _controlsVisible = true;
      if (!_isFullViewMode) {
        _isScreenLocked = false;
        _showUnlockButton = false;
        _unlockButtonTimer?.cancel();
      }
    });

    // Toggle PiP mode on minimize — only active in Full View mode
    _pipChannel.invokeMethod('setPlayerActive', _isFullViewMode);

    if (_isFullViewMode) {
      _applyFullscreenOrientation();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _safeSetOrientation(DeviceOrientation.values);
    }
    _startControlsTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  /// Apply fullscreen orientation lock — skipped on TV devices (always landscape)
  void _applyFullscreenOrientation() {
    if (!_isTvDevice) {
      _safeSetOrientation([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Wraps setPreferredOrientations in try-catch — some TV dongles/sticks
  /// throw PlatformException when you try to lock orientation.
  void _safeSetOrientation(List<DeviceOrientation> orientations) {
    try {
      SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {
      // Silently ignore on TV devices that don't support orientation changes
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _unlockButtonTimer?.cancel();
    _channelPanelFocusScope.dispose();
    _playPauseFocusNode.dispose();
    _pipChannel.invokeMethod('setPlayerActive', false);
    _pipChannel.setMethodCallHandler(null);
    // Allow screen to sleep again when leaving the player
    WakelockPlus.disable();
    _safeSetOrientation(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    // Stop tracking active channel
    ref.read(analyticsServiceProvider).stopWatching();
    
    super.dispose();
  }

  void _addToHistory(Channel channel) {
    if (_lastHistoryChannelId != channel.id) {
      _lastHistoryChannelId = channel.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(watchHistoryProvider.notifier).addChannel(channel);
          // Track active channel playback
          ref.read(analyticsServiceProvider).startWatching(channel.id, channel.name);
        }
      });
    }
  }

  /// Screen-level key handler.
  ///
  /// Handles:
  ///  - F key          → toggle full-view mode
  ///  - Escape / Back  → exit full-view or pop
  ///
  /// All other keys bubble to the inner ChannelVideoPlayerNative FocusNode.
  KeyEventResult _handlePlayerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // TV Remote Wake-Up: If player controls have auto-hidden, ANY remote key press
    // immediately shows all controls, focuses Play/Pause, and starts the 8s timer.
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
      _startControlsTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _playPauseFocusNode.requestFocus();
        }
      });
      return KeyEventResult.handled;
    }

    final lKey = event.logicalKey;
    final pKey = event.physicalKey;

    // F key → toggle full-view mode
    if (lKey == LogicalKeyboardKey.keyF ||
        pKey == PhysicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // Escape / Back → exit full-view first, then pop
    if (lKey == LogicalKeyboardKey.goBack ||
        lKey == LogicalKeyboardKey.escape) {
      if (_isFullViewMode) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Called by [ChannelVideoPlayerNative] when D-Pad Right is pressed
  /// and the user wants to shift focus to the channel list panel.
  void _focusChannelPanel() {
    if (!_channelPanelHasFocus) {
      // Make controls visible so the panel is visible
      setState(() {
        _controlsVisible = true;
        _channelPanelHasFocus = true;
      });
      _controlsTimer?.cancel();
      // Request focus on the side-panel scope
      _channelPanelFocusScope.requestFocus();
    }
  }

  /// Called by the channel panel's FocusScope when it loses focus back to player.
  void _focusPlayer() {
    if (_channelPanelHasFocus) {
      setState(() {
        _channelPanelHasFocus = false;
      });
      _startControlsTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final channelsAsync = ref.watch(channelsProvider);
    final mq = MediaQuery.of(context);
    // TV detection: matches improved logic from ShellScreen
    final isTv = mq.navigationMode == NavigationMode.directional ||
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional ||
        mq.size.shortestSide >= 960;
    // Cache TV detection for orientation logic (only set once)
    if (!_isTvDevice && isTv) _isTvDevice = true;
    final isLandscape = mq.orientation == Orientation.landscape || mq.size.width > mq.size.height;
    final isWide = isTv || isLandscape || mq.size.width >= 600;
    final isFullscreen = _isFullViewMode || widget.forceFullscreen;
    final maxPlayerH = mq.size.height * 0.45;
    final responsivePlayerHeight = (mq.size.width * 9 / 16).clamp(maxPlayerH < 180.0 ? maxPlayerH : 180.0, maxPlayerH);

    return PopScope(
      // Allow pop only when not in full-view and not screen-locked
      canPop: !_isFullViewMode && !_isScreenLocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isScreenLocked) {
          _showUnlockPrompt();
          return;
        }
        // canPop==false means we're in full-view mode — collapse it
        _toggleFullscreen();
      },
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handlePlayerKeyEvent,
        child: Scaffold(
          backgroundColor: cs.surface,
          body: DecoratedBox(
            decoration: BoxDecoration(color: cs.surface),
          child: channelsAsync.when(
            data: (channels) {
              final eventPlaceholder = widget.sportEvent != null &&
                      !_resolvedDynamicChannels.any((c) => c.id == _currentChannelId)
                  ? Channel(
                      id: _currentChannelId,
                      name: '${widget.sportEvent!.homeTeam.name} vs ${widget.sportEvent!.awayTeam.name}',
                      category: widget.sportEvent!.sport.isNotEmpty ? widget.sportEvent!.sport : 'Live Sports',
                      streamUrl: '',
                      logo: widget.sportEvent!.banner,
                      headers: const {},
                    )
                  : null;

              final allChannels = [
                ...channels,
                if (widget.dynamicChannels != null) ...widget.dynamicChannels!,
                ..._resolvedDynamicChannels,
                ?eventPlaceholder,
              ];


              final channel = allChannels.cast<Channel?>().firstWhere(
                (c) => c?.id == _currentChannelId,
                orElse: () => null,
              );

              if (channel == null ||
                  (_resolutionFailed &&
                      channel.streamUrl.isEmpty &&
                      _currentChannelServers.isEmpty)) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.live_tv_rounded, size: 48, color: GoPlayTheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        widget.sportEvent != null
                            ? 'Live feed is not currently active.\nKickoff might not have started yet.'
                            : 'Channel not found',
                        textAlign: TextAlign.center,
                        style: GoPlayType.body.copyWith(color: GoPlayTheme.darkOnSurface),
                      ),
                      if (widget.sportEvent != null) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                          ),
                          onPressed: () {
                            setState(() {
                              _resolutionFailed = false;
                              _isResolvingStream = true;
                            });
                            _resolveSportEvent(widget.sportEvent!);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry Connection'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // Populate from native Supabase streamServers if present
              if (_currentChannelServers.isEmpty) {
                final activeServers = channel.streamServers
                    .where((s) => s.active && s.streamUrl.isNotEmpty && !s.streamUrl.startsWith('pro/') && !s.streamUrl.contains('.txt'))
                    .toList();
                if (activeServers.isNotEmpty) {
                  _currentChannelServers = activeServers.map((s) => s.toPlayableChannel(
                    parentChannelId: channel.id,
                    parentName: channel.name,
                    logo: channel.logo,
                    category: channel.category,
                  )).toList();
                }
              }

              // Auto-resolve encrypted stream in the background without blocking pure native player mount
              if ((channel.streamUrl.startsWith('pro/') || channel.streamUrl.contains('.txt')) &&
                  _currentChannelServers.isEmpty &&
                  !_isResolvingStream) {
                _isResolvingStream = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _selectChannel(channel.id, allChannels);
                });
              }


              final currentPlayChannel = (_currentChannelServers.isNotEmpty &&
                      _activeServerIndex < _currentChannelServers.length)
                  ? _currentChannelServers[_activeServerIndex]
                  : channel;

              _addToHistory(channel);

              // Find related channels to enable prev/next buttons
              final relatedChannels = widget.eventChannels != null
                  ? widget.eventChannels!
                        .map((id) {
                          final match = allChannels.where((c) => c.id == id);
                          return match.isNotEmpty ? match.first : null;
                        })
                        .whereType<Channel>()
                        .toList()
                  : allChannels
                        .where((c) => c.category == channel.category && !c.id.contains('_server_'))
                        .toList();

              final currentIndex = relatedChannels.indexWhere(
                (c) => c.id == channel.id,
              );
              final prevChannel = (currentIndex > 0)
                  ? relatedChannels[currentIndex - 1]
                  : null;
              final nextChannel =
                  (currentIndex != -1 &&
                      currentIndex < relatedChannels.length - 1)
                  ? relatedChannels[currentIndex + 1]
                  : null;

              final onPrev = prevChannel != null
                  ? () => _selectChannel(prevChannel.id, allChannels)
                  : null;

              final onNext = nextChannel != null
                  ? () => _selectChannel(nextChannel.id, allChannels)
                  : null;

              // WIDESCREEN / TV RESPONSIVE SPLIT LAYOUT (NON-FULLSCREEN)
              if (isWide && !isFullscreen) {
                return Row(
                  children: [
                    // ── Player panel ──────────────────────────────
                    Expanded(
                      flex: 7,
                      child: _PlayerContainer(
                        channel: currentPlayChannel,
                        servers: _currentChannelServers.length > 1 ? _currentChannelServers : null,
                        activeServerIndex: _activeServerIndex,
                        onServerSelected: _handleServerSelected,
                        isFullscreen: false,
                        controlsVisible: _controlsVisible,
                        onTap: _onPlayerTap,
                        onFullscreenToggle: _toggleFullscreen,
                        showBackButton: true,
                        isLocked: _isScreenLocked,
                        showUnlockButton: _showUnlockButton,
                        onUnlock: _unlockScreen,
                        onLockChanged: (locked) => setState(() => _isScreenLocked = locked),
                        topBar: _FullscreenTopBar(
                          category: channel.category ?? '',
                          currentChannelId: channel.id,
                          isFullscreen: false,
                          onBackPressed: () => Navigator.of(context).pop(),
                          onChannelSelected: (id) => _selectChannel(id, allChannels),
                          eventChannels: widget.eventChannels,
                          dynamicChannels: widget.dynamicChannels,
                          onFocusDown: () {
                            _playPauseFocusNode.requestFocus();
                          },
                          onInteract: _onPlayerInteract,
                        ),
                        onPreviousChannel: onPrev,
                        onNextChannel: onNext,
                        onInteract: _onPlayerInteract,
                        // TV: D-Pad Right from player → shift focus to channel panel
                        onFocusChannelPanel: isTv ? _focusChannelPanel : null,
                        isTvDevice: isTv,
                        playPauseFocusNode: _playPauseFocusNode,
                      ),
                    ),
                    const VerticalDivider(
                      width: 0.8,
                      thickness: 0.8,
                      color: Color(0x14FFFFFF),
                    ),

                    // ── Channel list side panel ────────────────────
                    // Wrapped in a FocusScope so we can route focus in/out cleanly.
                    FocusScope(
                      node: _channelPanelFocusScope,
                      onFocusChange: (hasFocus) {
                        // When the panel LOSES focus back to the player area
                        if (!hasFocus && _channelPanelHasFocus) {
                          _focusPlayer();
                        }
                      },
                      child: KeyboardListener(
                        focusNode: FocusNode(canRequestFocus: false),
                        onKeyEvent: (event) {
                          // D-Pad Left from channel list → return focus to player
                          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                            // Move focus back to player — find nearest sibling
                            FocusScope.of(context).previousFocus();
                            _focusPlayer();
                          }
                        },
                        child: SizedBox(
                          width: mq.size.width > 1100 ? 380 : 320,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: _channelPanelHasFocus
                                ? BoxDecoration(
                                    color: cs.surfaceContainerLow,
                                    border: Border(
                                      left: BorderSide(color: cs.primary, width: 1.5),
                                    ),
                                  )
                                : BoxDecoration(
                                    color: cs.surface,
                                    border: Border(
                                      left: BorderSide(color: cs.outline.withValues(alpha: 0.2), width: 0.8),
                                    ),
                                  ),
                            child: SafeArea(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_currentChannelServers.length > 1)
                                    _ServerBadgesRow(
                                      servers: _currentChannelServers,
                                      activeServerIndex: _activeServerIndex,
                                      onServerSelected: (index) {
                                        setState(() => _activeServerIndex = index);
                                      },
                                    ),
                                  const _SectionLabel(text: 'SWITCH CHANNEL'),
                                  Expanded(
                                    child: _RelatedChannelsList(
                                      category: channel.category ?? '',
                                      currentChannelId: channel.id,
                                      isScrollable: true,
                                      onChannelSelected: (id) async {
                                        await _selectChannel(id, allChannels);
                                        // Return focus to player after switching channel
                                        if (isTv) _focusPlayer();
                                      },
                                      eventChannels: widget.eventChannels,
                                      dynamicChannels: [
                                        if (widget.dynamicChannels != null) ...widget.dynamicChannels!,
                                        ..._resolvedDynamicChannels,
                                      ],
                                      panelHasFocus: _channelPanelHasFocus && isTv,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // PORTRAIT / MOBILE LAYOUT (also handles fullscreen)
              // Both children always exist in the Stack to preserve
              // widget identity and prevent AndroidView recreation.
              return Stack(
                children: [
                  // 1. Channel list — always present, hidden via Offstage
                  Positioned.fill(
                    child: Offstage(
                      offstage: isFullscreen,
                      child: Column(
                        children: [
                          SizedBox(
                            height: mq.padding.top + responsivePlayerHeight,
                          ), // Placeholder for the player
                          Expanded(
                            child: SafeArea(
                              top: false,
                              bottom: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_currentChannelServers.length > 1)
                                    _ServerBadgesRow(
                                      servers: _currentChannelServers,
                                      activeServerIndex: _activeServerIndex,
                                      onServerSelected: _handleServerSelected,
                                    ),
                                  const _SectionLabel(text: 'SWITCH CHANNEL'),
                                  Expanded(
                                    child: _RelatedChannelsList(
                                      category: channel.category ?? '',
                                      currentChannelId: channel.id,
                                      isScrollable: true,
                                      onChannelSelected: (id) =>
                                          _selectChannel(id, allChannels),
                                      eventChannels: widget.eventChannels,
                                      dynamicChannels: [
                                        if (widget.dynamicChannels != null) ...widget.dynamicChannels!,
                                        ..._resolvedDynamicChannels,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. The Video Player — same tree position, same constraint type
                  Positioned(
                    top: isFullscreen ? 0 : mq.padding.top,
                    left: 0,
                    right: 0,
                    height: isFullscreen ? mq.size.height : responsivePlayerHeight,
                    child: _PlayerContainer(
                      channel: currentPlayChannel,
                      servers: _currentChannelServers.length > 1 ? _currentChannelServers : null,
                      activeServerIndex: _activeServerIndex,
                      onServerSelected: _handleServerSelected,
                      isFullscreen: isFullscreen,
                      controlsVisible: _controlsVisible,
                      onTap: _onPlayerTap,
                      onFullscreenToggle: _toggleFullscreen,
                      showBackButton: !isFullscreen,
                      onPreviousChannel: onPrev,
                      onNextChannel: onNext,
                      onInteract: _onPlayerInteract,
                      isLocked: _isScreenLocked,
                      showUnlockButton: _showUnlockButton,
                      onUnlock: _unlockScreen,
                      onLockChanged: (locked) => setState(() => _isScreenLocked = locked),
                      height: responsivePlayerHeight,
                      topBar: isFullscreen
                          ? _FullscreenTopBar(
                              category: channel.category ?? '',
                              currentChannelId: channel.id,
                              isFullscreen: true,
                              onBackPressed: widget.forceFullscreen
                                  ? () => Navigator.of(context).pop()
                                  : _toggleFullscreen,
                              onChannelSelected: (id) =>
                                  _selectChannel(id, allChannels),
                              eventChannels: widget.eventChannels,
                              dynamicChannels: [
                                if (widget.dynamicChannels != null) ...widget.dynamicChannels!,
                                ..._resolvedDynamicChannels,
                              ],
                              onFocusDown: () {
                                _playPauseFocusNode.requestFocus();
                              },
                              onInteract: _onPlayerInteract,
                            )
                          : null,
                      playPauseFocusNode: _playPauseFocusNode,
                    ),
                  ),
                ],
              );
            },
            loading: () => Center(
              child: CircularProgressIndicator(
                color: cs.primary,
                strokeWidth: 2,
              ),
            ),
            error: (e, s) => Center(
              child: Text(
                'Error: $e',
                style: GoPlayType.body.copyWith(color: GoPlayTheme.error),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ─── Player Container (isolated repaints) ───────────────────────

class _PlayerContainer extends StatelessWidget {
  final Channel channel;
  final List<Channel>? servers;
  final int activeServerIndex;
  final ValueChanged<int>? onServerSelected;
  final bool isFullscreen;
  final double? height;
  final bool controlsVisible;
  final VoidCallback onTap;
  final VoidCallback onFullscreenToggle;
  final bool showBackButton;
  final Widget? topBar;
  final VoidCallback? onPreviousChannel;
  final VoidCallback? onNextChannel;
  final VoidCallback? onInteract;
  // TV-only: called when D-Pad Right is pressed to shift focus to channel list
  final VoidCallback? onFocusChannelPanel;
  final bool isTvDevice;
  final FocusNode? playPauseFocusNode;
  final bool isLocked;
  final bool showUnlockButton;
  final VoidCallback? onUnlock;
  final ValueChanged<bool>? onLockChanged;

  const _PlayerContainer({
    required this.channel,
    this.servers,
    this.activeServerIndex = 0,
    this.onServerSelected,
    required this.isFullscreen,
    this.height,
    required this.controlsVisible,
    required this.onTap,
    required this.onFullscreenToggle,
    this.showBackButton = false,
    this.topBar,
    this.onPreviousChannel,
    this.onNextChannel,
    this.onInteract,
    this.onFocusChannelPanel,
    this.isTvDevice = false,
    this.playPauseFocusNode,
    this.isLocked = false,
    this.showUnlockButton = false,
    this.onUnlock,
    this.onLockChanged,
  });

  @override
  Widget build(BuildContext context) {
    // In fullscreen: wrap the entire stack in a FocusTraversalGroup so the
    // top bar (Back + channel chips) and the player controls (center + bottom)
    // all participate in ONE unified focus tree. ReadingOrderTraversalPolicy
    // traverses naturally top→bottom so D-Pad Up/Down moves between the 3 rows.
    final stack = SizedBox(
      height: isFullscreen ? double.infinity : (height ?? double.infinity),
      width: double.infinity,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            // Video — isolated from overlay repaints
            RepaintBoundary(
              child: ChannelVideoPlayer.create(
                channel: channel,
                isFullscreen: isFullscreen,
                onFullscreenToggle: onFullscreenToggle,
                showControls: isLocked ? false : controlsVisible,
                onTap: onTap,
                onPreviousChannel: onPreviousChannel,
                onNextChannel: onNextChannel,
                onInteract: onInteract,
                onFocusChannelPanel: onFocusChannelPanel,
                isTvDevice: isTvDevice,
                playPauseFocusNode: playPauseFocusNode,
                servers: servers,
                activeServerIndex: activeServerIndex,
                onServerSelected: onServerSelected,
                isLocked: isLocked,
                onLockChanged: onLockChanged,
              ),
            ),

            // If locked: tap anywhere triggers onTap -> _showUnlockPrompt
            if (isLocked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),

            // Floating Unlock Pill (Single-tap to unlock)
            if (showUnlockButton && onUnlock != null)
              Positioned(
                bottom: isFullscreen ? 50 : 24,
                left: 0,
                right: 0,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.scale(
                          scale: 0.92 + (0.08 * value),
                          child: child,
                        ),
                      );
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onUnlock,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xEE141418),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                              const BoxShadow(
                                color: Colors.black87,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_open_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tap to unlock',
                                style: TextStyle(
                                  fontFamily: GoPlayType.family,
                                  color: Colors.white,
                                  fontSize: GoPlayType.sm,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Back button
            if (showBackButton && topBar == null && !isLocked)
              Positioned(
                top: 16,
                left: 16,
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: AnimatedOpacity(
                    opacity: controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: const _BackButton(),
                  ),
                ),
              ),

            // Fullscreen top bar
            if (topBar != null && !isLocked)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !controlsVisible,
                  child: AnimatedOpacity(
                    opacity: controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: topBar!,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!isFullscreen) return stack;

    // Fullscreen: wrap in a single FocusTraversalGroup so the top bar and
    // the player center/bottom controls are one contiguous focus scope that
    // Flutter can traverse with D-Pad Up/Down/Left/Right.
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: stack,
    );
  }
}

// ─── Back Button (premium glass design) ─────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(
        Icons.arrow_back_rounded,
        color: Colors.white,
      ),
      iconSize: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }
}

// ─── Stream Server Filter Chips (Matches Homepage Today's Matches category chips) ──

class _ServerBadgesRow extends StatelessWidget {
  final List<Channel> servers;
  final int activeServerIndex;
  final ValueChanged<int> onServerSelected;

  const _ServerBadgesRow({
    required this.servers,
    required this.activeServerIndex,
    required this.onServerSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: servers.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final s = servers[index];
            final isSelected = index == activeServerIndex;
            final name = s.name.isNotEmpty ? s.name : 'Server ${index + 1}';

            return TvFocusable(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                HapticFeedback.lightImpact();
                onServerSelected(index);
              },
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onServerSelected(index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primary
                        : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outline.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                        fontSize: GoPlayType.sm,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        height: GoPlayType.leadingSnug,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Section Label ──────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(text, style: _kSectionLabelStyle),
    );
  }
}

// ─── Channel Avatar (lightweight) ───────────────────────────────

class _ChannelAvatar extends StatelessWidget {
  final String name;
  final String? logo;
  final double size;
  const _ChannelAvatar({required this.name, this.logo, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final initials = name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: _kAvatarDeco,
        child: logo != null && logo!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: logo!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                memCacheWidth: (size * 2).toInt(),
                memCacheHeight: (size * 2).toInt(),
                fadeInDuration: const Duration(milliseconds: 150),
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                placeholder: (context, url) => Center(
                  child: Text(
                    initials,
                    style: GoPlayType.inter(
                      color: GoPlayTheme.darkOnSurfaceVariant,
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w800,
                      height: GoPlayType.leadingFlat,
                    ),
                  ),
                ),
                errorWidget: (context, url, err) => Center(
                  child: Text(
                    initials,
                    style: GoPlayType.inter(
                      color: GoPlayTheme.darkOnSurfaceVariant,
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w800,
                      height: GoPlayType.leadingFlat,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initials,
                  style: GoPlayType.inter(
                    color: GoPlayTheme.darkOnSurfaceVariant,
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.w800,
                    height: GoPlayType.leadingFlat,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RelatedChannelsList extends ConsumerStatefulWidget {
  final String category;
  final String currentChannelId;
  final bool isScrollable;
  final Function(String) onChannelSelected;
  final List<String>? eventChannels;
  final List<Channel>? dynamicChannels;
  /// When true (TV + panel has focus), the current playing or last-focused channel item gets autofocus
  final bool panelHasFocus;

  const _RelatedChannelsList({
    required this.category,
    required this.currentChannelId,
    required this.isScrollable,
    required this.onChannelSelected,
    this.eventChannels,
    this.dynamicChannels,
    this.panelHasFocus = false,
  });

  @override
  ConsumerState<_RelatedChannelsList> createState() => _RelatedChannelsListState();
}

class _RelatedChannelsListState extends ConsumerState<_RelatedChannelsList> {
  String? _lastFocusedChannelId;

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(channelsProvider);

    return channelsAsync.when(
      data: (channels) {
        final allChannels = [
          ...channels,
          if (widget.dynamicChannels != null) ...widget.dynamicChannels!,
        ];
        final List<Channel> related;
        if (widget.eventChannels != null) {
          related = widget.eventChannels!
              .map((id) {
                final match = allChannels.where((c) => c.id == id);
                return match.isNotEmpty ? match.first : null;
              })
              .whereType<Channel>()
              .toList();
        } else {
          related = allChannels.where((c) => c.category == widget.category && !c.id.contains('_server_')).toList();
        }

        if (related.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'No other channels in this category',
                textAlign: TextAlign.center,
                style: GoPlayType.body.copyWith(color: GoPlayTheme.darkOnSurfaceMuted),
              ),
            ),
          );
        }

        // Target last focused channel if available; fallback to currently playing channel
        final targetId = _lastFocusedChannelId ?? widget.currentChannelId;
        int targetIdx = related.indexWhere((c) => c.id == targetId);
        if (targetIdx == -1) {
          targetIdx = related.indexWhere((c) => c.id == widget.currentChannelId);
        }
        if (targetIdx == -1) targetIdx = 0;

        final autoFocusIdx = widget.panelHasFocus ? targetIdx : -1;

        if (widget.isScrollable) {
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: related.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final ch = related[index];
              final isCurrent = ch.id == widget.currentChannelId;
              return _ChannelTile(
                key: ValueKey(ch.id),
                channel: ch,
                isCurrent: isCurrent,
                autoFocus: index == autoFocusIdx,
                onFocused: () {
                  _lastFocusedChannelId = ch.id;
                },
                onTap: () => widget.onChannelSelected(ch.id),
              );
            },
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in related)
              _ChannelTile(
                channel: ch,
                isCurrent: ch.id == widget.currentChannelId,
                onTap: () => widget.onChannelSelected(ch.id),
              ),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

// ─── Channel Tile (interactive hover & stateful animation) ──────

class _ChannelTile extends StatefulWidget {
  final Channel channel;
  final bool isCurrent;
  final VoidCallback onTap;
  final bool autoFocus;
  final VoidCallback? onFocused;

  const _ChannelTile({
    super.key,
    required this.channel,
    required this.isCurrent,
    required this.onTap,
    this.autoFocus = false,
    this.onFocused,
  });

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _isHovered = false;
  late final FocusNode _tileFocusNode;

  @override
  void initState() {
    super.initState();
    _tileFocusNode = FocusNode(debugLabel: 'TileFocus-${widget.channel.name}');
    _tileFocusNode.addListener(_onFocusChange);
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tileFocusNode.requestFocus();
      });
    }
  }

  void _onFocusChange() {
    if (_tileFocusNode.hasFocus) {
      widget.onFocused?.call();
    }
  }

  @override
  void didUpdateWidget(_ChannelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoFocus && !oldWidget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tileFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _tileFocusNode.removeListener(_onFocusChange);
    _tileFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final channel = widget.channel;
    final isCurrent = widget.isCurrent;

    final normalDeco = BoxDecoration(
      color: cs.surfaceContainer,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
    );
    final activeDeco = BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      border: Border.fromBorderSide(
        BorderSide(color: cs.primary, width: 1.0),
      ),
      boxShadow: [
        BoxShadow(color: cs.primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
      ],
    );
    final hoveredDeco = BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TvFocusable(
        focusNode: _tileFocusNode,
        borderRadius: BorderRadius.circular(16),
        autoFocus: widget.autoFocus,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          cursor: isCurrent ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: isCurrent ? null : widget.onTap,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            transform: _isHovered && !isCurrent
                ? _kHoverMatrix
                : _kIdentityMatrix,
            decoration: isCurrent
                ? activeDeco
                : (_isHovered ? hoveredDeco : normalDeco),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _ChannelAvatar(
                    name: channel.displayName,
                    logo: channel.logo,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                channel.displayName,
                                style: isCurrent
                                    ? _kTileNameActiveStyle.copyWith(color: cs.primary)
                                    : _kTileNameNormalStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            channel.quality,
                            channel.category,
                            channel.country,
                          ].where((s) => s != null && s.isNotEmpty).join(' · '),
                          style: isCurrent
                              ? _kTileMetaActiveStyle.copyWith(color: cs.primary)
                              : _kTileMetaNormalStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isCurrent)
                    _buildPlayingTag(cs)
                  else if (channel.isLive)
                    const _LiveDot(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildPlayingTag(ColorScheme cs) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'PLAYING',
          style: TextStyle(
            fontFamily: GoPlayType.family,
            color: cs.primary,
            fontSize: GoPlayType.xs,
            fontWeight: FontWeight.w800,
            height: GoPlayType.leadingFlat,
            letterSpacing: GoPlayType.trackingMeta,
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 6,
      height: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: GoPlayTheme.liveBadge,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Equalizer Bars (CustomPainter — zero widget rebuilds) ──────



// ─── Fullscreen Top Bar ─────────────────────────────────────────

class _FullscreenTopBar extends ConsumerWidget {
  final String category;
  final String currentChannelId;
  final VoidCallback onBackPressed;
  final Function(String) onChannelSelected;
  final List<String>? eventChannels;
  final List<Channel>? dynamicChannels;
  final bool isFullscreen;
  /// Called when D-Pad Down is pressed in the top bar, allowing the parent
  /// to move focus explicitly to the center player controls.
  final VoidCallback? onFocusDown;
  final VoidCallback? onInteract;

  const _FullscreenTopBar({
    required this.category,
    required this.currentChannelId,
    required this.onBackPressed,
    required this.onChannelSelected,
    this.eventChannels,
    this.dynamicChannels,
    this.isFullscreen = true,
    this.onFocusDown,
    this.onInteract,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(channelsProvider);
    final mq = MediaQuery.of(context);
    final double leftInset = isFullscreen ? math.max(12.0, mq.padding.left) : 8.0;
    final double rightInset = isFullscreen ? math.max(12.0, mq.padding.right) : 8.0;

    final bar = DecoratedBox(
      decoration: _kTopBarGradient,
      child: SafeArea(
        top: isFullscreen,
        bottom: false,
        left: false,
        right: false,
        child: Padding(
          padding: EdgeInsets.only(
            top: isFullscreen ? 8.0 : 4.0,
            bottom: isFullscreen ? 6.0 : 4.0,
            left: leftInset,
            right: rightInset,
          ),
          child: SizedBox(
            height: isFullscreen ? 48 : 42,
            child: Row(
              children: [
                // 1. Back button
                TvFocusable(
                  isCircle: true,
                  onTap: onBackPressed,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                // 2. Horizontal Channels list
                Expanded(
                  child: channelsAsync.when(
                    data: (channels) {
                      final allChannels = [
                        ...channels,
                        if (dynamicChannels != null) ...dynamicChannels!,
                      ];
                      final List<Channel> related;
                      if (eventChannels != null) {
                        related = eventChannels!
                            .map((id) {
                              final match = allChannels.where((c) => c.id == id);
                              return match.isNotEmpty ? match.first : null;
                            })
                            .whereType<Channel>()
                            .toList();
                      } else {
                        related = allChannels
                            .where((c) => c.category == category && !c.id.contains('_server_'))
                            .toList();
                      }
                      if (related.isEmpty) return const SizedBox.shrink();
                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 4, right: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: related.length,
                        itemBuilder: (context, index) {
                          final ch = related[index];
                          final isCurrent = ch.id == currentChannelId;
                          return _ServerChip(
                            label: ch.displayName,
                            isCurrent: isCurrent,
                            onTap: () => onChannelSelected(ch.id),
                            onFocusDown: onFocusDown,
                          );
                        },
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onFocusDown == null) return bar;

    // Wrap bar in a Focus that intercepts D-Pad Down → move focus to
    // center controls explicitly, bypassing any Stack-traversal ambiguity.
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          onInteract?.call();
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            onFocusDown!();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            // Prevent focus loss when pressing Up on top-most row!
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: bar,
    );
  }
}

class _ServerChip extends StatefulWidget {
  final String label;
  final bool isCurrent;
  final VoidCallback onTap;
  /// Optional: called when D-Pad Down is pressed while this chip is focused.
  final VoidCallback? onFocusDown;

  const _ServerChip({
    required this.label,
    required this.isCurrent,
    required this.onTap,
    this.onFocusDown,
  });

  @override
  State<_ServerChip> createState() => _ServerChipState();
}

class _ServerChipState extends State<_ServerChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeDeco = BoxDecoration(
      color: cs.primary,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.0),
      boxShadow: [
        BoxShadow(
          color: cs.primary.withValues(alpha: 0.35),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
    final inactiveDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 0.8),
    );

    final activeStyle = TextStyle(
      fontFamily: GoPlayType.family,
      height: GoPlayType.leadingSnug,
      color: cs.onPrimary,
      fontSize: GoPlayType.sm,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    );
    final inactiveStyle = const TextStyle(
      fontFamily: GoPlayType.family,
      height: GoPlayType.leadingSnug,
      color: Colors.white,
      fontSize: GoPlayType.sm,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: TvFocusable(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.isCurrent ? null : widget.onTap,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            onTap: widget.isCurrent ? null : widget.onTap,
            child: AnimatedScale(
              scale: _isPressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                decoration: widget.isCurrent ? activeDeco : inactiveDeco,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Text(
                    widget.label,
                    style: widget.isCurrent ? activeStyle : inactiveStyle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
