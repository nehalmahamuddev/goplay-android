import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../models/category.dart';
import '../../providers/app_providers.dart';
import '../../providers/theme_provider.dart';
import '../../providers/playz_providers.dart';
import '../../widgets/cards/channel_card.dart';
import '../../widgets/tv_focus_wrapper.dart';
import 'package:go_router/go_router.dart';

enum CategorySortOption { defaultOrder, nameAsc, countDesc }
enum ChannelSortOption { defaultOrder, nameAsc, nameDesc }

/// Categories Screen matching the reference UI with GoPlay's dark theme & volt styling.
///
/// Features:
/// - Screen 1: 2-column Category list with circular emblems, bold typography, and volt hover glow.
/// - Screen 2: 4-column Channel grid per category with circular logos, 2-line titles, and star favorites.
/// - In-page search toggle for both Categories and Channels.
/// - Star toggle to filter favorite categories / channels.
/// - Smooth animated transitions between list and grid.
/// - Full D-Pad Android TV support via [TvFocusable].
/// - Handles Android back navigation seamlessly via [PopScope].
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  // Navigation & selection
  Category? _selectedCategory;
  String? _lastSelectedCategoryId;
  final Map<String, FocusNode> _categoryFocusNodes = {};

  FocusNode _getFocusNodeForCategory(String id) {
    return _categoryFocusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'Cat_$id'));
  }

  // Search states
  final TextEditingController _categorySearchController = TextEditingController();
  String _categorySearchQuery = '';

  final TextEditingController _channelSearchController = TextEditingController();
  String _channelSearchQuery = '';

  // Filter & Sort states
  CategorySortOption _categorySort = CategorySortOption.defaultOrder;
  ChannelSortOption _channelSort = ChannelSortOption.defaultOrder;
  bool _filterFavoriteCategories = false;
  bool _filterFavoriteChannels = false;

  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _channelScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _categorySearchController.addListener(() {
      final q = _categorySearchController.text.trim().toLowerCase();
      if (q != _categorySearchQuery) {
        setState(() => _categorySearchQuery = q);
      }
    });

    _channelSearchController.addListener(() {
      final q = _channelSearchController.text.trim().toLowerCase();
      if (q != _channelSearchQuery) {
        setState(() => _channelSearchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _categorySearchController.dispose();
    _channelSearchController.dispose();
    _categoryScrollController.dispose();
    _channelScrollController.dispose();
    for (final fn in _categoryFocusNodes.values) {
      fn.dispose();
    }
    _categoryFocusNodes.clear();
    super.dispose();
  }

  void _onCategoryTapped(Category category) {
    HapticFeedback.selectionClick();
    _lastSelectedCategoryId = category.id;
    setState(() {
      _selectedCategory = category;
      _channelSearchController.clear();
      _channelSearchQuery = '';
      _filterFavoriteChannels = false;
      _channelSort = ChannelSortOption.defaultOrder;
    });
    ref.read(playzSelectedCategoryProvider.notifier).select(category);
  }

  void _goBackToCategories() {
    HapticFeedback.lightImpact();
    setState(() {
      _channelSearchController.clear();
      _channelSearchQuery = '';
      _filterFavoriteChannels = false;
      _channelSort = ChannelSortOption.defaultOrder;
      _selectedCategory = null;
    });
    ref.read(playzSelectedCategoryProvider.notifier).select(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lastSelectedCategoryId != null) {
        _categoryFocusNodes[_lastSelectedCategoryId]?.requestFocus();
      }
    });
  }

  int _calculateCategoryColumns(BuildContext context) {
    final configured = ref.watch(uiConfigProvider).categoriesScreen.categoryGridColumns;
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1200) return math.max(4, configured);
    if (width >= 720) return math.max(3, configured);
    return (configured >= 1 && configured <= 4) ? configured : 2;
  }

  double _calculateCategoryAspectRatio(int columns) {
    if (columns >= 4) return 2.85;
    if (columns == 3) return 2.75;
    return 2.65; // Mobile 2-column cards: compact 66dp height
  }

  static const double _kGridSpacing = 8.0;
  static const double _kGridEdgeInset = 12.0;

  SliverGridDelegateWithFixedCrossAxisCount _buildChannelGridDelegate(
    BuildContext context,
    double crossAxisExtent,
  ) {
    final int cols;
    if (crossAxisExtent >= 1180) {
      cols = 6;
    } else if (crossAxisExtent >= 880) {
      cols = 5;
    } else if (crossAxisExtent >= 580) {
      cols = 4;
    } else {
      cols = 3;
    }

    final tileWidth = (crossAxisExtent - _kGridSpacing * (cols - 1)) / cols;
    final tileHeight = math.max(tileWidth, ChannelCard.measureHeight(context));

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      childAspectRatio: tileWidth <= 0 ? 1.0 : tileWidth / tileHeight,
      crossAxisSpacing: _kGridSpacing,
      mainAxisSpacing: _kGridSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;
    final categoriesAsync = ref.watch(playzCategoriesProvider);
    final favoriteIds = ref.watch(favoriteChannelIdsProvider);
    final isDark = theme.brightness == Brightness.dark;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: _selectedCategory == null &&
            _categorySearchQuery.isEmpty &&
            !_filterFavoriteCategories &&
            _categorySort == CategorySortOption.defaultOrder,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (_channelSearchQuery.isNotEmpty) {
              _channelSearchController.clear();
            } else if (_filterFavoriteChannels || _channelSort != ChannelSortOption.defaultOrder) {
              setState(() {
                _filterFavoriteChannels = false;
                _channelSort = ChannelSortOption.defaultOrder;
              });
            } else if (_selectedCategory != null) {
              _goBackToCategories();
            } else if (_categorySearchQuery.isNotEmpty) {
              _categorySearchController.clear();
            } else if (_filterFavoriteCategories || _categorySort != CategorySortOption.defaultOrder) {
              setState(() {
                _filterFavoriteCategories = false;
                _categorySort = CategorySortOption.defaultOrder;
              });
            }
          }
        },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0.0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _selectedCategory == null
                ? _buildCategoriesPage(context, categoriesAsync, favoriteIds, headerBg, overlayStyle)
                : _buildChannelsPage(context, _selectedCategory!, favoriteIds, headerBg, overlayStyle),
          ),
        ),
      ),
    );
  }

  // ==========================================
  //         SCREEN 1: CATEGORIES LIST
  // ==========================================
  Widget _buildCategoriesPage(
    BuildContext context,
    AsyncValue<List<Category>> categoriesAsync,
    Set<String> favoriteIds,
    Color headerBg,
    SystemUiOverlayStyle overlayStyle,
  ) {
    final channelsByCategoryAsync = ref.watch(channelsByCategoryMapProvider);
    final channelsMap = channelsByCategoryAsync.value;

    final isFilterActive = _filterFavoriteCategories || _categorySort != CategorySortOption.defaultOrder;

    return Column(
      key: const ValueKey('categories_list_view'),
      children: [
        Container(
          color: headerBg,
          child: SafeArea(
            bottom: false,
            child: _buildCategorySearchHeader(
              context: context,
              controller: _categorySearchController,
              hintText: 'Search categories...',
              isFilterActive: isFilterActive,
              onFilterTap: () => _showCategoryFilterSheet(context),
            ),
          ),
        ),
        Expanded(
          child: categoriesAsync.when(
            data: (categories) {
              var displayList = categories.toList();

              // Text search filter
              if (_categorySearchQuery.isNotEmpty) {
                displayList = displayList
                    .where((c) => c.name.toLowerCase().contains(_categorySearchQuery))
                    .toList();
              }

              // Favorites category filter
              if (_filterFavoriteCategories) {
                displayList = displayList.where((c) {
                  final channels = channelsMap?[c.id] ??
                      channelsMap?[c.name] ??
                      channelsMap?[c.id.toLowerCase()];
                  return channels != null &&
                      channels.any((ch) => favoriteIds.contains(ch.id));
                }).toList();
              }

              // Sorting
              switch (_categorySort) {
                case CategorySortOption.nameAsc:
                  displayList.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  break;
                case CategorySortOption.countDesc:
                  displayList.sort((a, b) {
                    final countA = channelsMap?[a.id]?.length ??
                        channelsMap?[a.name]?.length ??
                        channelsMap?[a.id.toLowerCase()]?.length ??
                        0;
                    final countB = channelsMap?[b.id]?.length ??
                        channelsMap?[b.name]?.length ??
                        channelsMap?[b.id.toLowerCase()]?.length ??
                        0;
                    return countB.compareTo(countA);
                  });
                  break;
                case CategorySortOption.defaultOrder:
                  break;
              }

              if (displayList.isEmpty) {
                final isFav = _filterFavoriteCategories;
                final isSearch = _categorySearchQuery.isNotEmpty;
                return _buildEmptyState(
                  icon: isFav ? Icons.star_border_rounded : Icons.category_outlined,
                  message: isSearch
                      ? 'No categories match "$_categorySearchQuery"'
                      : isFav
                          ? 'No categories contain favorite channels'
                          : 'No categories available',
                  actionLabel: isSearch
                      ? 'Clear Search'
                      : isFav
                          ? 'Show All Categories'
                          : 'Refresh',
                  onAction: () {
                    if (isSearch) {
                      _categorySearchController.clear();
                    } else if (isFav) {
                      setState(() => _filterFavoriteCategories = false);
                    } else {
                      ref.invalidate(playzCategoriesProvider);
                    }
                  },
                );
              }

              final columns = _calculateCategoryColumns(context);
              return GridView.builder(
                key: const PageStorageKey('categories_grid_page_storage'),
                controller: _categoryScrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                cacheExtent: 500.0,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: _calculateCategoryAspectRatio(columns),
                ),
                itemCount: displayList.length,
                itemBuilder: (context, index) {
                  final category = displayList[index];
                  final count = channelsMap?[category.id]?.length ??
                      channelsMap?[category.name]?.length ??
                      channelsMap?[category.id.toLowerCase()]?.length;
                  return _CategoryPillCard(
                    category: category,
                    channelCount: count,
                    focusNode: _getFocusNodeForCategory(category.id),
                    onTap: () => _onCategoryTapped(category),
                  );
                },
              );
            },
            loading: () => _buildCategoriesSkeleton(context),
            error: (err, _) => _buildErrorState(
              'Failed to load categories',
              () => ref.invalidate(playzCategoriesProvider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesSkeleton(BuildContext context) {
    final columns = _calculateCategoryColumns(context);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: _calculateCategoryAspectRatio(columns),
      ),
      itemCount: columns * 6,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,

            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF202226),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 70,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF222428),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 45,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D1F23),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategorySearchHeader({
    required BuildContext context,
    required TextEditingController controller,
    required String hintText,
    required bool isFilterActive,
    required VoidCallback onFilterTap,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(leading != null ? 8 : 16, 6, 16, 8),
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.search_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textInputAction: TextInputAction.search,
                      cursorColor: const Color(0xFFA855F7),
                      cursorWidth: 2,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        tooltip: 'Clear search',
                        icon: Icon(
                          Icons.close_rounded,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          size: 18,
                        ),
                        splashRadius: 18,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          controller.clear();
                        },
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Filter and sort',
                    splashRadius: 20,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 22,
                          color: isFilterActive
                              ? GoPlayTheme.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        if (isFilterActive)
                          Positioned(
                            top: -1,
                            right: -1,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: GoPlayTheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: onFilterTap,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  //         SCREEN 2: CHANNELS GRID
  // ==========================================
  Widget _buildChannelsPage(
    BuildContext context,
    Category category,
    Set<String> favoriteIds,
    Color headerBg,
    SystemUiOverlayStyle overlayStyle,
  ) {
    final channelsAsync = ref.watch(playzCategoryChannelsProvider(category));
    final cs = Theme.of(context).colorScheme;
    final isFilterActive = _filterFavoriteChannels || _channelSort != ChannelSortOption.defaultOrder;

    return Column(
      key: ValueKey('category_channels_${category.id}'),
      children: [
        Container(
          color: headerBg,
          child: SafeArea(
            bottom: false,
            child: _buildCategorySearchHeader(
              context: context,
              controller: _channelSearchController,
              hintText: 'Search in ${category.name}...',
              isFilterActive: isFilterActive,
              onFilterTap: () => _showChannelFilterSheet(context, category),
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
                tooltip: 'Back to Categories',
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: _goBackToCategories,
              ),
            ),
          ),
        ),
        Expanded(
          child: channelsAsync.when(
            data: (channels) {
              var displayList = channels.toList();

              // Search query filter
              if (_channelSearchQuery.isNotEmpty) {
                displayList = displayList
                    .where((c) => c.name.toLowerCase().contains(_channelSearchQuery))
                    .toList();
              }

              // Star Favorites filter
              if (_filterFavoriteChannels) {
                displayList = displayList
                    .where((c) => favoriteIds.contains(c.id))
                    .toList();
              }

              // Sorting
              switch (_channelSort) {
                case ChannelSortOption.nameAsc:
                  displayList.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  break;
                case ChannelSortOption.nameDesc:
                  displayList.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
                  break;
                case ChannelSortOption.defaultOrder:
                  break;
              }

              if (displayList.isEmpty) {
                return _buildEmptyState(
                  icon: _filterFavoriteChannels ? Icons.star_border_rounded : Icons.tv_off_rounded,
                  message: _channelSearchQuery.isNotEmpty
                      ? 'No channels match "$_channelSearchQuery"'
                      : _filterFavoriteChannels
                          ? 'No favorite channels in ${category.name}'
                          : 'No channels available in ${category.name}',
                  actionLabel: _channelSearchQuery.isNotEmpty
                      ? 'Clear Search'
                      : _filterFavoriteChannels
                          ? 'Show All'
                          : 'Retry',
                  onAction: () {
                    if (_channelSearchQuery.isNotEmpty) {
                      _channelSearchController.clear();
                    } else if (_filterFavoriteChannels) {
                      setState(() => _filterFavoriteChannels = false);
                    } else {
                      ref.invalidate(playzCategoryChannelsProvider(category));
                    }
                  },
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth - (_kGridEdgeInset * 2);
                  final gridDelegate = _buildChannelGridDelegate(context, availableWidth);

                  return GridView.builder(
                    key: PageStorageKey('category_channels_${category.id}'),
                    controller: _channelScrollController,
                    padding: const EdgeInsets.fromLTRB(_kGridEdgeInset, 8, _kGridEdgeInset, 88),
                    cacheExtent: 500.0,
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                    gridDelegate: gridDelegate,
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final ch = displayList[index];
                      return RepaintBoundary(
                        child: ChannelCard(
                          key: ValueKey(ch.id),
                          channel: ch,
                          scope: displayList,
                        ),
                      );
                    },
                  );
                },
              );
            },
            loading: () => _buildChannelsSkeleton(context),
            error: (err, _) => _buildErrorState(
              'Failed to load channels for ${category.name}',
              () => ref.invalidate(playzCategoryChannelsProvider(category)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelsSkeleton(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - (_kGridEdgeInset * 2);
        final gridDelegate = _buildChannelGridDelegate(context, availableWidth);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(_kGridEdgeInset, 8, _kGridEdgeInset, 88),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: gridDelegate,
          itemCount: 12,
          itemBuilder: (context, index) => const _ChannelShimmerCard(),
        );
      },
    );
  }

  void _showCategoryFilterSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasActiveFilters = _filterFavoriteCategories ||
                _categorySort != CategorySortOption.defaultOrder;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters & Sorting',
                          style: (Theme.of(context).textTheme.titleMedium ?? GoPlayType.title).copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasActiveFilters)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: GoPlayTheme.primary,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _filterFavoriteCategories = false;
                                _categorySort = CategorySortOption.defaultOrder;
                              });
                              setSheetState(() {});
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Filter Options
                    Text(
                      'FILTER',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202020) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        secondary: Icon(
                          _filterFavoriteCategories ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: _filterFavoriteCategories ? GoPlayTheme.primary : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          'Favorites Only',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Show only categories with favorite channels',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        activeThumbColor: GoPlayTheme.primary,
                        value: _filterFavoriteCategories,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() => _filterFavoriteCategories = val);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sort Options
                    Text(
                      'SORT BY',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202020) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSortTile(
                            context: context,
                            title: 'Default (Original order)',
                            icon: Icons.sort_rounded,
                            isSelected: _categorySort == CategorySortOption.defaultOrder,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _categorySort = CategorySortOption.defaultOrder);
                              setSheetState(() {});
                            },
                          ),
                          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06), indent: 48),
                          _buildSortTile(
                            context: context,
                            title: 'Alphabetical (A to Z)',
                            icon: Icons.sort_by_alpha_rounded,
                            isSelected: _categorySort == CategorySortOption.nameAsc,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _categorySort = CategorySortOption.nameAsc);
                              setSheetState(() {});
                            },
                          ),
                          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06), indent: 48),
                          _buildSortTile(
                            context: context,
                            title: 'Most Channels',
                            icon: Icons.format_list_numbered_rounded,
                            isSelected: _categorySort == CategorySortOption.countDesc,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _categorySort = CategorySortOption.countDesc);
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Actions
                    Text(
                      'QUICK ACTIONS',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.refresh_rounded,
                            label: 'Refresh',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              HapticFeedback.mediumImpact();
                              ref.invalidate(playzCategoriesProvider);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              context.push('/settings');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showChannelFilterSheet(BuildContext context, Category category) {
    HapticFeedback.lightImpact();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161616) : cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final hasActiveFilters = _filterFavoriteChannels ||
                _channelSort != ChannelSortOption.defaultOrder;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Filters & Sorting',
                          style: (Theme.of(context).textTheme.titleMedium ?? GoPlayType.title).copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (hasActiveFilters)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: GoPlayTheme.primary,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _filterFavoriteChannels = false;
                                _channelSort = ChannelSortOption.defaultOrder;
                              });
                              setSheetState(() {});
                            },
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Filter Options
                    Text(
                      'FILTER',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202020) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        secondary: Icon(
                          _filterFavoriteChannels ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: _filterFavoriteChannels ? GoPlayTheme.primary : cs.onSurfaceVariant,
                        ),
                        title: Text(
                          'Favorites Only',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Show only favorite channels in ${category.name}',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        activeThumbColor: GoPlayTheme.primary,
                        value: _filterFavoriteChannels,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() => _filterFavoriteChannels = val);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sort Options
                    Text(
                      'SORT BY',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF202020) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSortTile(
                            context: context,
                            title: 'Default',
                            icon: Icons.sort_rounded,
                            isSelected: _channelSort == ChannelSortOption.defaultOrder,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _channelSort = ChannelSortOption.defaultOrder);
                              setSheetState(() {});
                            },
                          ),
                          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06), indent: 48),
                          _buildSortTile(
                            context: context,
                            title: 'Alphabetical (A to Z)',
                            icon: Icons.sort_by_alpha_rounded,
                            isSelected: _channelSort == ChannelSortOption.nameAsc,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _channelSort = ChannelSortOption.nameAsc);
                              setSheetState(() {});
                            },
                          ),
                          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.06), indent: 48),
                          _buildSortTile(
                            context: context,
                            title: 'Alphabetical (Z to A)',
                            icon: Icons.sort_by_alpha_rounded,
                            isSelected: _channelSort == ChannelSortOption.nameDesc,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _channelSort = ChannelSortOption.nameDesc);
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Actions
                    Text(
                      'QUICK ACTIONS',
                      style: GoPlayType.labelSmall.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.refresh_rounded,
                            label: 'Refresh',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              HapticFeedback.mediumImpact();
                              ref.invalidate(playzCategoryChannelsProvider(category));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionCard(
                            context: context,
                            icon: Icons.settings_outlined,
                            label: 'Settings',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              context.push('/settings');
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? GoPlayTheme.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? GoPlayTheme.primary : cs.onSurface,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                size: 20,
                color: GoPlayTheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF202020) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  //             HELPER WIDGETS
  // ==========================================
  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Icon(icon, size: 36, color: GoPlayTheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xAAFFFFFF),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: GoPlayTheme.primary,
                backgroundColor: const Color(0xFF222416),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontFamily: GoPlayType.family,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40, color: GoPlayTheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: GoPlayTheme.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(fontFamily: GoPlayType.family, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
//    PILL CATEGORY CARD (2-COLUMN GRID)
// ==========================================
class _CategoryPillCard extends ConsumerWidget {
  final Category category;
  final int? channelCount;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  const _CategoryPillCard({
    required this.category,
    this.channelCount,
    required this.onTap,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catConfig = ref.watch(uiConfigProvider).categoriesScreen;
    final visuals = CategoryVisuals.resolve(category);
    final count = channelCount;
    final countText = (count != null && count > 0)
        ? '$count ${count == 1 ? 'channel' : 'channels'}'
        : null;



    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      focusedScale: 1.03,
      semanticLabel: countText != null
          ? '${category.name}, $countText'
          : category.name,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,

          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Avatar plate (40x40)
            if (catConfig.showCategoryEmblems) ...[
              RepaintBoundary(
                child: _buildAvatar(visuals),
              ),
              const SizedBox(width: 10),
            ],

            // Category Name and Channel Count
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF1F1F1),
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  if (catConfig.showCategoryChannelCounts && countText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      countText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0x8AFFFFFF),
                        letterSpacing: -0.1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 4),

            // Subtle chevron indicator
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Color(0x2EFFFFFF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(CategoryVisuals visuals) {
    final hasIconUrl = category.iconUrl != null && category.iconUrl!.isNotEmpty;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: visuals.gradientColors,
        ),
        border: Border.all(
          color: const Color(0x24FFFFFF),
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasIconUrl
          ? CachedNetworkImage(
              imageUrl: category.iconUrl!,
              fit: BoxFit.cover,
              memCacheWidth: 80,
              memCacheHeight: 80,
              fadeInDuration: const Duration(milliseconds: 150),
              placeholder: (context, url) => _buildFallbackVisual(visuals),
              errorWidget: (context, url, error) => _buildFallbackVisual(visuals),
            )
          : _buildFallbackVisual(visuals),
    );
  }

  Widget _buildFallbackVisual(CategoryVisuals visuals) {
    if (visuals.isBangladesh) {
      return Center(
        child: Container(
          width: 17,
          height: 17,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFF42A41),
          ),
        ),
      );
    }

    return Center(
      child: Icon(
        visuals.icon,
        size: 19,
        color: visuals.accentColor,
      ),
    );
  }
}

// ==========================================
//    CATEGORY VISUALS RESOLVER
// ==========================================
class CategoryVisuals {
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;
  final bool isBangladesh;

  const CategoryVisuals({
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
    this.isBangladesh = false,
  });

  static CategoryVisuals resolve(Category category) {
    final key = '${category.id} ${category.name}'.toLowerCase();

    if (key.contains('bangla') || key.contains('bangladesh') || key.contains('bd')) {
      return const CategoryVisuals(
        icon: Icons.flag_rounded,
        gradientColors: [Color(0xFF006A4E), Color(0xFF004D38)],
        accentColor: Color(0xFFF42A41),
        isBangladesh: true,
      );
    }
    if (key.contains('kids') || key.contains('cartoon') || key.contains('child') || key.contains('animation')) {
      return const CategoryVisuals(
        icon: Icons.child_care_rounded,
        gradientColors: [Color(0xFFE65100), Color(0xFFFF6D00)],
        accentColor: Color(0xFFFFD54F),
      );
    }
    if (key.contains('kolkata') || key.contains('calcutta')) {
      return const CategoryVisuals(
        icon: Icons.theater_comedy_rounded,
        gradientColors: [Color(0xFFBF360C), Color(0xFFD84315)],
        accentColor: Color(0xFFFF8A65),
      );
    }
    if (key.contains('sports') || key.contains('sport') || key.contains('cricket') || key.contains('football')) {
      return const CategoryVisuals(
        icon: Icons.sports_soccer_rounded,
        gradientColors: [Color(0xFF1B5E20), Color(0xFF00796B)],
        accentColor: GoPlayTheme.primary,
      );
    }
    if (key.contains('hindi') || key.contains('bollywood')) {
      return const CategoryVisuals(
        icon: Icons.movie_filter_rounded,
        gradientColors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
        accentColor: Color(0xFFFFB300),
      );
    }
    if (key.contains('doc') || key.contains('nature') || key.contains('earth') || key.contains('discovery') || key.contains('geo')) {
      return const CategoryVisuals(
        icon: Icons.public_rounded,
        gradientColors: [Color(0xFF004D40), Color(0xFF00838F)],
        accentColor: Color(0xFF4DD0E1),
      );
    }
    if (key.contains('islam') || key.contains('quran') || key.contains('deen') || key.contains('makkah')) {
      return const CategoryVisuals(
        icon: Icons.brightness_3_rounded,
        gradientColors: [Color(0xFF004D40), Color(0xFF00695C)],
        accentColor: Color(0xFFFFD54F),
      );
    }
    if (key.contains('music') || key.contains('song') || key.contains('audio')) {
      return const CategoryVisuals(
        icon: Icons.music_note_rounded,
        gradientColors: [Color(0xFF880E4F), Color(0xFFC2185B)],
        accentColor: Color(0xFFFF4081),
      );
    }
    if (key.contains('news') || key.contains('khobor') || key.contains('headline')) {
      return const CategoryVisuals(
        icon: Icons.newspaper_rounded,
        gradientColors: [Color(0xFF8E0000), Color(0xFFC62828)],
        accentColor: Color(0xFFFF5252),
      );
    }
    if (key.contains('movie') || key.contains('cinema') || key.contains('film')) {
      return const CategoryVisuals(
        icon: Icons.movie_creation_rounded,
        gradientColors: [Color(0xFFBF360C), Color(0xFFE65100)],
        accentColor: Color(0xFFFFB74D),
      );
    }
    if (key.contains('entertainment') || key.contains('natok') || key.contains('drama')) {
      return const CategoryVisuals(
        icon: Icons.auto_awesome_rounded,
        gradientColors: [Color(0xFF311B92), Color(0xFF512DA8)],
        accentColor: Color(0xFFB388FF),
      );
    }
    if (key.contains('info')) {
      return const CategoryVisuals(
        icon: Icons.lightbulb_rounded,
        gradientColors: [Color(0xFF01579B), Color(0xFF0277BD)],
        accentColor: Color(0xFF40C4FF),
      );
    }
    if (key.contains('radio')) {
      return const CategoryVisuals(
        icon: Icons.radio_rounded,
        gradientColors: [Color(0xFFE64A19), Color(0xFFF57C00)],
        accentColor: Color(0xFFFFAB40),
      );
    }
    if (key.contains('indian') || key.contains('india')) {
      return const CategoryVisuals(
        icon: Icons.live_tv_rounded,
        gradientColors: [Color(0xFFE65100), Color(0xFF1B5E20)],
        accentColor: Color(0xFFFF9933),
      );
    }
    if (key.contains('pakistan') || key.contains('pk')) {
      return const CategoryVisuals(
        icon: Icons.star_rounded,
        gradientColors: [Color(0xFF002811), Color(0xFF01411C)],
        accentColor: Colors.white,
      );
    }
    if (key.contains('nepal')) {
      return const CategoryVisuals(
        icon: Icons.landscape_rounded,
        gradientColors: [Color(0xFF003893), Color(0xFFDC143C)],
        accentColor: Colors.white,
      );
    }
    if (key.contains('ayna') || key.contains('ott') || key.contains('tvlink') || key.contains('iptv')) {
      return const CategoryVisuals(
        icon: Icons.stream_rounded,
        gradientColors: [Color(0xFF192227), Color(0xFF263238)],
        accentColor: GoPlayTheme.primary,
      );
    }

    return const CategoryVisuals(
      icon: Icons.category_rounded,
      gradientColors: [Color(0xFF181A1E), Color(0xFF23252B)],
      accentColor: GoPlayTheme.primary,
    );
  }
}

// ==========================================
//    CHANNEL SHIMMER LOADING SKELETON
// ==========================================
class _ChannelShimmerCard extends StatelessWidget {
  const _ChannelShimmerCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Center(
        child: SizedBox(
          width: 54,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
