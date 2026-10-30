import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../models/hero_banner_item.dart';
import '../../../widgets/tv_focus_wrapper.dart';
import '../skeletons/home_skeletons.dart';

const _kInterLeagueBadge = TextStyle(
  fontFamily: GoPlayType.family,
  color: Colors.white,
  fontSize: GoPlayType.xs,
  fontWeight: FontWeight.w600,
  height: GoPlayType.leadingFlat,
  letterSpacing: GoPlayType.trackingMeta,
);

/// Auto-scrolling Hero Banner with app lifecycle awareness and drag gesture safety
class HomeHeroBanner extends ConsumerStatefulWidget {
  const HomeHeroBanner({super.key});

  @override
  ConsumerState<HomeHeroBanner> createState() => _HomeHeroBannerState();
}

class _HomeHeroBannerState extends ConsumerState<HomeHeroBanner> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final ValueNotifier<int> _currentPage = ValueNotifier<int>(0);
  Timer? _autoScrollTimer;
  int _bannerCount = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isDragging) _resumeAutoScroll();
    } else {
      _pauseAutoScroll();
    }
  }

  void _startAutoScroll(int count) {
    _autoScrollTimer?.cancel();
    _bannerCount = count;
    if (count <= 1 || _isDragging) return;

    final speed = ref.read(uiConfigProvider).homeScreen.heroBannerAutoplaySpeed;
    final interval = Duration(seconds: speed > 0 ? speed : 5);

    _autoScrollTimer = Timer.periodic(interval, (timer) {
      if (!_pageController.hasClients || _isDragging) return;
      final nextPage = (_currentPage.value + 1) % _bannerCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseAutoScroll() {
    _autoScrollTimer?.cancel();
  }

  void _resumeAutoScroll() {
    _startAutoScroll(_bannerCount);
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(heroBannersProvider);

    return bannersAsync.when(
      data: (banners) {
        if (banners.isEmpty) return const SizedBox.shrink();

        if (_bannerCount != banners.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startAutoScroll(banners.length);
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _isDragging = true;
                    _pauseAutoScroll();
                  } else if (notification is ScrollEndNotification) {
                    _isDragging = false;
                    _resumeAutoScroll();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    _currentPage.value = index;
                  },
                  itemCount: banners.length,
                  itemBuilder: (context, index) {
                    final banner = banners[index];
                    return _HeroBannerCard(
                      banner: banner,
                      autoFocus: index == 0,
                      onFocusChange: (focused) {
                        if (focused) {
                          _pauseAutoScroll();
                        } else {
                          _resumeAutoScroll();
                        }
                      },
                    );
                  },
                ),
              ),
            ),
            if (banners.length > 1) ...[
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: _currentPage,
                builder: (context, currentPage, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(banners.length, (index) {
                      final bool active = currentPage == index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(3),
                          ),
                          color: active
                              ? GoPlayTheme.primary
                              : const Color(0x50C8FF00),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ],
        );
      },
      loading: () => const HeroBannerSkeleton(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

/// Individual hero banner card
class _HeroBannerCard extends ConsumerWidget {
  final HeroBannerItem banner;
  final bool autoFocus;
  final ValueChanged<bool>? onFocusChange;

  const _HeroBannerCard({
    required this.banner,
    this.autoFocus = false,
    this.onFocusChange,
  });

  static const _cardRadius = BorderRadius.all(Radius.circular(20));
  static const _cardDecoration = BoxDecoration(
    borderRadius: _cardRadius,
    border: Border.fromBorderSide(
      BorderSide(color: GoPlayTheme.cardBorder, width: 0.8),
    ),
    boxShadow: [
      BoxShadow(
        color: Color(0x26000000),
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  );

  Future<void> _handleTap(BuildContext context) async {
    if (banner.isExternalUrl) {
      final uri = Uri.tryParse(banner.actionValue!);
      if (uri != null) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('Error launching banner URL: $e');
        }
      }
    } else if (banner.isChannelAction) {
      if (context.mounted) {
        context.push('/player/${banner.actionValue}');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Dynamically calculate memory cache width for sharp TV / high-DPI rendering, capped at 1920
    final targetCacheWidth = ((screenWidth > 600 ? screenWidth : 600) * dpr).round().clamp(600, 1920);

    return TvFocusable(
      autoFocus: autoFocus,
      borderRadius: BorderRadius.circular(20),
      onFocusChange: onFocusChange,
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
        child: DecoratedBox(
          decoration: _cardDecoration,
          child: ClipRRect(
            borderRadius: _cardRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Artwork Image
                if (banner.imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: banner.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: targetCacheWidth,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (context, url) => const ColoredBox(
                      color: GoPlayTheme.surfaceContainerHigh,
                    ),
                    errorWidget: (context, url, error) => const ColoredBox(
                      color: GoPlayTheme.surfaceContainerHigh,
                    ),
                  )
                else
                  const ColoredBox(
                    color: GoPlayTheme.surfaceContainerHigh,
                  ),

                // Top & bottom gradient overlays for contrast
                if (banner.hasOverlay)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x60000000),
                          Colors.transparent,
                          Color(0x85000000),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),

                // Top badge
                if (banner.showBadge && banner.badgeText != null && banner.badgeText!.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x30FFFFFF), width: 0.5),
                      ),
                      child: Text(
                        banner.badgeText!.toUpperCase(),
                        style: _kInterLeagueBadge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                // Bottom Title Overlay
                if (banner.showTitle && banner.title != null && banner.title!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                      child: Text(
                        banner.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

