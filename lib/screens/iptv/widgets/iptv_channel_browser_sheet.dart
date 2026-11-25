import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/typography.dart';
import '../../../models/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/iptv_service.dart';
import 'iptv_category_sheets.dart';
import 'iptv_svg_icon.dart';
import 'iptv_view_settings_sheet.dart';

/// Full-screen channel browser matching the APK opened playlist activity
/// (`All (N)` / group tabs, horizontal swipe via TabBarView, 300ms title search,
/// 24h smart cache + XMLTV EPG sync, 4 view modes, TabJump, Channel Info & Bookmarks).
class IptvChannelBrowserSheet extends ConsumerStatefulWidget {
  final IptvPlaylist playlist;

  const IptvChannelBrowserSheet({super.key, required this.playlist});

  static Future<void> show(BuildContext context, IptvPlaylist playlist) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => IptvChannelBrowserSheet(playlist: playlist),
      ),
    );
  }

  @override
  ConsumerState<IptvChannelBrowserSheet> createState() =>
      _IptvChannelBrowserSheetState();
}

class _IptvChannelBrowserSheetState
    extends ConsumerState<IptvChannelBrowserSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  TabController? _tabController;
  List<String> _tabTitles = const [];
  final List<TabController> _staleControllers = [];

  Timer? _searchDebounce;
  bool _isSearching = false;
  bool _isRefreshing = false;
  double _syncProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(selectedIptvPlaylistProvider.notifier).select(widget.playlist);
      ref.read(iptvSearchQueryProvider.notifier).setQuery('');
      ref.read(iptvSelectedCategoryProvider.notifier).select('All');
      _initCacheAndEpg();
    });
  }

  Future<void> _initCacheAndEpg() async {
    final settings = ref.read(iptvSettingsProvider);
    final playlist = widget.playlist;

    if (playlist.epgUrl != null && playlist.epgUrl!.isNotEmpty) {
      unawaited(ref.read(iptvEpgProvider.notifier).loadEpgForPlaylist(playlist));
    }

    final isRemoteSource = playlist.sourceType == IptvSourceType.m3uUrl ||
        playlist.sourceType == IptvSourceType.xtream ||
        playlist.sourceType == IptvSourceType.stalker;

    final shouldAutoSync = isRemoteSource &&
        playlist.url.trim().isNotEmpty &&
        (!settings.cacheEnabled || !playlist.isCacheFresh);

    if (shouldAutoSync) {
      await _refreshPlaylist(silentOnSuccess: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _tabController?.removeListener(_handleTabChanged);
    _tabController?.dispose();
    for (final c in _staleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureTabController(List<IptvGroupedCategory> groups) {
    final nextTitles = groups.map((g) => g.title).toList(growable: false);
    if (_tabController != null && listEquals(_tabTitles, nextTitles)) {
      return;
    }

    final old = _tabController;
    int nextIndex = 0;
    if (old != null && _tabTitles.isNotEmpty) {
      final prevTitle =
          old.index >= 0 && old.index < _tabTitles.length
              ? _tabTitles[old.index]
              : 'All';
      final match = nextTitles.indexOf(prevTitle);
      if (match >= 0) nextIndex = match;
    }

    old?.removeListener(_handleTabChanged);
    if (old != null) {
      _staleControllers.add(old);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_staleControllers.remove(old)) {
          old.dispose();
        }
      });
    }

    _tabTitles = nextTitles;
    if (nextTitles.isEmpty) {
      _tabController = null;
      return;
    }

    final created = TabController(
      length: nextTitles.length,
      vsync: this,
      initialIndex: nextIndex.clamp(0, nextTitles.length - 1),
    );
    created.addListener(_handleTabChanged);
    _tabController = created;
  }

  void _handleTabChanged() {
    final tc = _tabController;
    if (tc == null || tc.indexIsChanging) return;
    if (tc.index >= 0 && tc.index < _tabTitles.length) {
      final title = _tabTitles[tc.index];
      if (ref.read(iptvSelectedCategoryProvider) != title) {
        ref.read(iptvSelectedCategoryProvider.notifier).select(title);
      }
    }
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(iptvSearchQueryProvider.notifier).setQuery(raw);
    });
  }

  Future<void> _refreshPlaylist({bool silentOnSuccess = false}) async {
    if (_isRefreshing) return;
    final current = ref.read(selectedIptvPlaylistProvider) ?? widget.playlist;
    setState(() {
      _isRefreshing = true;
      _syncProgress = 0.20;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _syncProgress = 0.52);

      final refreshed = await ref
          .read(iptvPlaylistsProvider.notifier)
          .refreshPlaylist(current.id);

      if (mounted) setState(() => _syncProgress = 0.90);

      if (mounted && refreshed != null && !silentOnSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${refreshed.channels.length} channels',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: const Color(0xFFB3261E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncProgress = 1.0;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _handleBookmarkTap(
    Channel ch,
    IptvPlaylist activePlaylist,
    bool currentlyBookmarked,
  ) async {
    HapticFeedback.selectionClick();
    final notifier = ref.read(iptvBookmarksProvider.notifier);

    if (currentlyBookmarked) {
      await notifier.removeBookmark(ch.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Removed "${ch.name}" from Bookmarks'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }

    final settings = ref.read(iptvSettingsProvider);
    if (settings.rememberBookmarkChoice &&
        settings.rememberedCategories.isNotEmpty) {
      await notifier.saveBookmark(
        channel: ch,
        playlistId: activePlaylist.id,
        playlistName: activePlaylist.name,
        categories: settings.rememberedCategories,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Bookmarked "${ch.name}" in ${settings.rememberedCategories.join(", ")}',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Change',
              textColor: const Color(0xFFA8C7FA),
              onPressed: () async {
                await ref
                    .read(iptvSettingsProvider.notifier)
                    .saveBookmarkChoice(
                      remember: false,
                      categories: settings.rememberedCategories,
                    );
                if (!mounted) return;
                final picked = await IptvCategorySelectorDialog.show(context, ch);
                if (picked != null && mounted) {
                  await notifier.saveBookmark(
                    channel: ch,
                    playlistId: activePlaylist.id,
                    playlistName: activePlaylist.name,
                    categories: picked,
                  );
                }
              },
            ),
          ),
        );
      return;
    }

    final chosen = await IptvCategorySelectorDialog.show(context, ch);
    if (chosen == null || !mounted) return;

    await notifier.saveBookmark(
      channel: ch,
      playlistId: activePlaylist.id,
      playlistName: activePlaylist.name,
      categories: chosen,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Saved "${ch.name}" to ${chosen.join(", ")}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View',
            textColor: const Color(0xFFA8C7FA),
            onPressed: () {
              IptvBookmarksSheet.show(
                context,
                onPlayChannel: (target, scope) => launchIptvChannelPlayback(
                  context,
                  ref,
                  channel: target,
                  scopeChannels: scope,
                ),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final selectedFromState = ref.watch(selectedIptvPlaylistProvider);
    final activePlaylist =
        (selectedFromState != null && selectedFromState.id == widget.playlist.id)
            ? selectedFromState
            : widget.playlist;

    final settings = ref.watch(iptvSettingsProvider);
    final groupsFromProvider = ref.watch(iptvGroupedCategoriesProvider);
    final groups = groupsFromProvider.isNotEmpty ||
            selectedFromState?.id == activePlaylist.id
        ? groupsFromProvider
        : buildGroupedCategories(
            activePlaylist.channels,
            sortByCountDesc: settings.sortCategoriesByCount,
            hideAllCategory:
                activePlaylist.hideAllCategory || settings.hideAllCategory,
          );

    _ensureTabController(groups);

    final searchQuery = ref.watch(iptvSearchQueryProvider);
    final viewConfigs = ref.watch(iptvViewConfigsProvider);
    final viewConfig = viewConfigs[activePlaylist.id] ??
        viewConfigs['default'] ??
        const IptvViewConfig();

    final bookmarks = ref.watch(iptvBookmarksProvider);
    final epgMap = ref.watch(iptvEpgProvider)[activePlaylist.id];
    ref.watch(iptvEpgClockProvider);
    final now = DateTime.now();

    final tc = _tabController;
    final activeTitle = (tc != null &&
            groups.isNotEmpty &&
            tc.index >= 0 &&
            tc.index < groups.length)
        ? groups[tc.index].title
        : 'All';

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSearching) {
          _searchDebounce?.cancel();
          _searchController.clear();
          ref.read(iptvSearchQueryProvider.notifier).setQuery('');
          setState(() => _isSearching = false);
        }
      },
      child: Scaffold(
        backgroundColor: themeMode.surfaceColor,
        appBar: AppBar(
          backgroundColor: themeMode.surfaceColor,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            icon: IptvSvgIcon(IptvSvgIcons.arrowLeft, color: themeMode.onSurfaceColor, size: 20),
            onPressed: () {
              if (_isSearching) {
                _searchDebounce?.cancel();
                _searchController.clear();
                ref.read(iptvSearchQueryProvider.notifier).setQuery('');
                setState(() => _isSearching = false);
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    color: themeMode.onSurfaceColor,
                    fontSize: 16,
                  ),
                  cursorColor: accentColor.color,
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
                    hintStyle: TextStyle(
                      fontFamily: GoPlayType.family,
                      color: themeMode.onSurfaceMutedColor,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                )
              : Text(
                  activePlaylist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    color: themeMode.onSurfaceColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
          actions: _isSearching
              ? [
                  IconButton(
                    icon: IptvSvgIcon(IptvSvgIcons.close, color: themeMode.onSurfaceColor, size: 20),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      ref.read(iptvSearchQueryProvider.notifier).setQuery('');
                      setState(() => _isSearching = false);
                    },
                  ),
                ]
              : [
                  IconButton(
                    icon: IptvSvgIcon(IptvSvgIcons.search, color: themeMode.onSurfaceColor, size: 20),
                    tooltip: 'Search channels',
                    onPressed: () {
                      setState(() => _isSearching = true);
                    },
                  ),
                  IconButton(
                    icon: _isRefreshing
                        ? SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor.color,
                            ),
                          )
                        : IptvSvgIcon(IptvSvgIcons.refresh, color: themeMode.onSurfaceColor, size: 19),
                    tooltip: 'Sync playlist & TV guide',
                    onPressed:
                        _isRefreshing ? null : () => _refreshPlaylist(),
                  ),
                  IconButton(
                    icon: IptvSvgIcon(
                      IptvSvgIcons.layoutGrid,
                      color: themeMode.onSurfaceColor,
                      size: 20,
                    ),
                    tooltip: 'View settings',
                    onPressed: () =>
                        IptvViewSettingsSheet.show(context, activePlaylist.id),
                  ),
                  IconButton(
                    icon: IptvSvgIcon(
                      IptvSvgIcons.layoutList,
                      color: themeMode.onSurfaceColor,
                      size: 20,
                    ),
                    tooltip: 'Category tabs',
                    onPressed: groups.isEmpty
                        ? null
                        : () {
                            IptvTabJumpSheet.show(
                              context,
                              categories: groups,
                              activeCategoryTitle: activeTitle,
                              onSelectTabIndex: (idx) {
                                final controller = _tabController;
                                if (controller != null &&
                                    idx >= 0 &&
                                    idx < groups.length) {
                                  controller.animateTo(idx);
                                }
                              },
                            );
                          },
                  ),
                  const SizedBox(width: 2),
                ],
        ),
        body: Column(
          children: [
            if (groups.isNotEmpty && tc != null)
              Container(
                decoration: BoxDecoration(
                  color: themeMode.surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: themeMode.dividerColor, width: 1),
                  ),
                ),
                child: TabBar(
                  controller: tc,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: accentColor.color,
                  indicatorWeight: 2.5,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelColor: accentColor.color,
                  unselectedLabelColor: themeMode.onSurfaceMutedColor,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  labelStyle: const TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    for (final g in groups) Tab(height: 42, text: g.tabLabel),
                  ],
                ),
              ),
            if (_isRefreshing)
              LinearProgressIndicator(
                value: _syncProgress > 0 && _syncProgress < 1
                    ? _syncProgress
                    : null,
                minHeight: 2.5,
                backgroundColor: themeMode.surfaceContainerHigh,
                valueColor:
                    AlwaysStoppedAnimation<Color>(accentColor.color),
              ),
            Expanded(
              child: groups.isEmpty || tc == null
                  ? _buildEmptyState(hasSearch: false)
                  : TabBarView(
                      controller: tc,
                      children: [
                        for (final group in groups)
                          _buildTabContent(
                            group: group,
                            activePlaylist: activePlaylist,
                            searchQuery: searchQuery,
                            viewConfig: viewConfig,
                            bookmarks: bookmarks,
                            epgMap: epgMap,
                            now: now,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent({
    required IptvGroupedCategory group,
    required IptvPlaylist activePlaylist,
    required String searchQuery,
    required IptvViewConfig viewConfig,
    required Map<String, IptvBookmarkItem> bookmarks,
    required Map<String, List<IptvEpgProgramme>>? epgMap,
    required DateTime now,
  }) {
    final channels = filterIptvCategoryChannels(group.channels, searchQuery);
    if (channels.isEmpty) {
      return _buildEmptyState(hasSearch: searchQuery.trim().isNotEmpty);
    }

    switch (viewConfig.mode) {
      case IptvDisplayMode.list:
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
          itemCount: channels.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final ch = channels[index];
            return _buildListCard(
              ch: ch,
              scope: channels,
              activePlaylist: activePlaylist,
              isBookmarked: bookmarks.containsKey(ch.id),
              epgMap: epgMap,
              now: now,
            );
          },
        );

      case IptvDisplayMode.poster:
        final cols = viewConfig.spanCount.clamp(1, 12);
        final ratio =
            IptvPosterRatioPreset.byIndex(viewConfig.posterRatioIndex).aspectRatio;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: ratio,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final ch = channels[index];
            return _buildPosterCard(
              ch: ch,
              scope: channels,
              activePlaylist: activePlaylist,
              isBookmarked: bookmarks.containsKey(ch.id),
              epgMap: epgMap,
              now: now,
            );
          },
        );

      case IptvDisplayMode.square:
        final cols = viewConfig.spanCount.clamp(1, 12);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: cols >= 4 ? 0.72 : 0.78,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final ch = channels[index];
            return _buildSquareCard(
              ch: ch,
              scope: channels,
              activePlaylist: activePlaylist,
              isBookmarked: bookmarks.containsKey(ch.id),
              epgMap: epgMap,
              now: now,
            );
          },
        );

      case IptvDisplayMode.grid:
        final cols = viewConfig.spanCount.clamp(1, 12);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: cols <= 2 ? 0.96 : 0.85,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final ch = channels[index];
            return _buildGridCard(
              ch: ch,
              scope: channels,
              activePlaylist: activePlaylist,
              isBookmarked: bookmarks.containsKey(ch.id),
              epgMap: epgMap,
              now: now,
            );
          },
        );
    }
  }

  List<IptvEpgProgramme> _programmesFor(
    Channel ch,
    Map<String, List<IptvEpgProgramme>>? epgMap,
  ) {
    if (epgMap == null || epgMap.isEmpty) return const [];
    return lookupEpgProgrammesForChannel(ch, epgMap);
  }

  IptvEpgProgramme? _liveProgramme(
    List<IptvEpgProgramme> progs,
    DateTime now,
  ) {
    for (final p in progs) {
      if (p.isLiveAt(now)) return p;
    }
    return null;
  }

  String _groupLabel(Channel ch) =>
      (ch.category != null && ch.category!.trim().isNotEmpty)
          ? ch.category!.trim()
          : 'Undefined';

  Widget _buildGridCard({
    required Channel ch,
    required List<Channel> scope,
    required IptvPlaylist activePlaylist,
    required bool isBookmarked,
    required Map<String, List<IptvEpgProgramme>>? epgMap,
    required DateTime now,
  }) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final progs = _programmesFor(ch, epgMap);
    final liveProg = _liveProgramme(progs, now);
    final groupLabel = _groupLabel(ch);
    final subtitle =
        liveProg != null ? liveProg.title : 'No TV guide available | $groupLabel';

    return Material(
      color: themeMode.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: themeMode.dividerColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchIptvChannelPlayback(
          context,
          ref,
          channel: ch,
          scopeChannels: scope,
        ),
        onLongPress: () => IptvEpgInfoBottomSheet.show(
          context,
          channel: ch,
          programmes: progs,
          onPlay: () => launchIptvChannelPlayback(
            context,
            ref,
            channel: ch,
            scopeChannels: scope,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ChannelLogoView(channel: ch, fit: BoxFit.cover),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _BookmarkHeartButton(
                      isBookmarked: isBookmarked,
                      onTap: () =>
                          _handleBookmarkTap(ch, activePlaylist, isBookmarked),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: themeMode.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: liveProg != null ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 11.2,
                          height: 1.22,
                          color: liveProg != null
                              ? accentColor.color
                              : themeMode.onSurfaceMutedColor,
                        ),
                      ),
                    ),
                    if (liveProg != null) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: liveProg.progressAt(now),
                          minHeight: 2.5,
                          backgroundColor: themeMode.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor.color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard({
    required Channel ch,
    required List<Channel> scope,
    required IptvPlaylist activePlaylist,
    required bool isBookmarked,
    required Map<String, List<IptvEpgProgramme>>? epgMap,
    required DateTime now,
  }) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final progs = _programmesFor(ch, epgMap);
    final liveProg = _liveProgramme(progs, now);
    final groupLabel = _groupLabel(ch);
    final timeFmt = DateFormat('HH:mm');
    final subtitle = liveProg != null
        ? '${timeFmt.format(liveProg.startTime)}-${timeFmt.format(liveProg.stopTime)} ${liveProg.title}'
        : 'No TV guide available | $groupLabel';

    return Material(
      color: themeMode.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: themeMode.dividerColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchIptvChannelPlayback(
          context,
          ref,
          channel: ch,
          scopeChannels: scope,
        ),
        onLongPress: () => IptvEpgInfoBottomSheet.show(
          context,
          channel: ch,
          programmes: progs,
          onPlay: () => launchIptvChannelPlayback(
            context,
            ref,
            channel: ch,
            scopeChannels: scope,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 74,
                  height: 54,
                  child: _ChannelLogoView(channel: ch, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: themeMode.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 11.5,
                        color: liveProg != null
                            ? accentColor.color
                            : themeMode.onSurfaceMutedColor,
                      ),
                    ),
                    if (liveProg != null) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: liveProg.progressAt(now),
                          minHeight: 2.5,
                          backgroundColor: themeMode.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor.color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: themeMode.onSurfaceMutedColor,
                  size: 20,
                ),
                tooltip: 'Channel info',
                onPressed: () => IptvChannelInfoListSheet.show(context, ch),
              ),
              _BookmarkHeartButton(
                isBookmarked: isBookmarked,
                onTap: () => _handleBookmarkTap(ch, activePlaylist, isBookmarked),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterCard({
    required Channel ch,
    required List<Channel> scope,
    required IptvPlaylist activePlaylist,
    required bool isBookmarked,
    required Map<String, List<IptvEpgProgramme>>? epgMap,
    required DateTime now,
  }) {
    final progs = _programmesFor(ch, epgMap);
    final liveProg = _liveProgramme(progs, now);
    final groupLabel = _groupLabel(ch);

    return Material(
      color: const Color(0xFF141519),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF242731), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchIptvChannelPlayback(
          context,
          ref,
          channel: ch,
          scopeChannels: scope,
        ),
        onLongPress: () => IptvEpgInfoBottomSheet.show(
          context,
          channel: ch,
          programmes: progs,
          onPlay: () => launchIptvChannelPlayback(
            context,
            ref,
            channel: ch,
            scopeChannels: scope,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ChannelLogoView(channel: ch, fit: BoxFit.cover),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0x440C0D10),
                      const Color(0xEB0C0D10),
                    ],
                    stops: const [0.35, 0.68, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: _BookmarkHeartButton(
                isBookmarked: isBookmarked,
                onTap: () => _handleBookmarkTap(ch, activePlaylist, isBookmarked),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ch.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    liveProg != null ? liveProg.title : groupLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 10.5,
                      color: liveProg != null
                          ? const Color(0xFFA8C7FA)
                          : const Color(0xFFAEAEBA),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareCard({
    required Channel ch,
    required List<Channel> scope,
    required IptvPlaylist activePlaylist,
    required bool isBookmarked,
    required Map<String, List<IptvEpgProgramme>>? epgMap,
    required DateTime now,
  }) {
    final progs = _programmesFor(ch, epgMap);
    final liveProg = _liveProgramme(progs, now);
    final groupLabel = _groupLabel(ch);

    return Material(
      color: const Color(0xFF141519),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF242731), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchIptvChannelPlayback(
          context,
          ref,
          channel: ch,
          scopeChannels: scope,
        ),
        onLongPress: () => IptvEpgInfoBottomSheet.show(
          context,
          channel: ch,
          programmes: progs,
          onPlay: () => launchIptvChannelPlayback(
            context,
            ref,
            channel: ch,
            scopeChannels: scope,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ChannelLogoView(channel: ch, fit: BoxFit.cover),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _BookmarkHeartButton(
                      isBookmarked: isBookmarked,
                      onTap: () =>
                          _handleBookmarkTap(ch, activePlaylist, isBookmarked),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      liveProg != null ? liveProg.title : groupLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 10.5,
                        color: liveProg != null
                            ? const Color(0xFFA8C7FA)
                            : const Color(0xFF9EA2B0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasSearch}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSearch ? Icons.search_off_rounded : Icons.live_tv_rounded,
              size: 46,
              color: const Color(0xFF5A5D68),
            ),
            const SizedBox(height: 12),
            Text(
              hasSearch ? 'No matching channels' : 'No channels in this playlist',
              style: const TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? 'Try clearing or shortening your title filter.'
                  : 'Tap Sync in the top bar to re-fetch channels from source.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 12.5,
                color: Color(0xFF8E9099),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkHeartButton extends ConsumerWidget {
  final bool isBookmarked;
  final VoidCallback onTap;

  const _BookmarkHeartButton({
    required this.isBookmarked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accentColor = ref.watch(activeAccentColorProvider);
    final themeMode = ref.watch(activeThemeModeProvider);
    final activeHeartColor = (accentColor.color == Colors.white || accentColor.color.computeLuminance() > 0.8)
        ? const Color(0xFFEF4444)
        : accentColor.color;

    return Material(
      type: MaterialType.transparency,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: IptvSvgIcon(
            isBookmarked ? IptvSvgIcons.heartFilled : IptvSvgIcons.heart,
            size: 20,
            color: isBookmarked
                ? activeHeartColor
                : themeMode.onSurfaceMutedColor.withAlpha(140),
          ),
        ),
      ),
    );
  }
}

class _ChannelLogoView extends ConsumerWidget {
  final Channel channel;
  final BoxFit fit;

  const _ChannelLogoView({
    required this.channel,
    required this.fit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final logoUrl = channel.logo?.trim() ?? '';
    if (logoUrl.isEmpty) {
      return _FallbackLogo(name: channel.name);
    }

    return Container(
      color: themeMode.surfaceContainerHigh,
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        fit: fit,
        placeholder: (_, _) => _FallbackLogo(name: channel.name),
        errorWidget: (_, _, _) => _FallbackLogo(name: channel.name),
      ),
    );
  }
}

class _FallbackLogo extends ConsumerWidget {
  final String name;

  const _FallbackLogo({required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final clean = name.trim();
    final initials = clean.isEmpty
        ? 'TV'
        : clean
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join();
    return Container(
      color: themeMode.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: themeMode.onSurfaceMutedColor,
        ),
      ),
    );
  }
}
