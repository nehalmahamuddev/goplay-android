import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../core/typography.dart';
import '../../main.dart' show appInitFuture;
import '../../providers/app_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _logoScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _animController.forward();

    // Check if we have cached channels on disk
    final cache = ref.read(cacheServiceProvider);
    final hasInitialData = cache.getLocalChannels().isNotEmpty;

    final List<Future<dynamic>> waitList = [
      appInitFuture.catchError((e) {
        debugPrint('appInitFuture error in Splash: $e');
      }),
      Future.delayed(const Duration(milliseconds: 750)),
    ];

    // First install: download initial database while splash animates so Home is never empty
    if (!hasInitialData) {
      waitList.add(
        ref.read(syncServiceProvider).sync().catchError((e) {
          debugPrint('Initial sync in splash error: $e');
        }),
      );
    }

    Future.wait(waitList).then((_) {
      if (!mounted) return;

      ref.invalidate(uiConfigProvider);

      // Returning user: trigger silent background sync without blocking Home
      if (hasInitialData) {
        unawaited(ref.read(syncServiceProvider).sync().catchError((e) {
          debugPrint('Silent background sync error: $e');
        }));
      }

      unawaited(ref.read(analyticsServiceProvider).initialize().catchError((e) {
        debugPrint('Analytics init error: $e');
      }));

      context.go('/home');
    }).catchError((_) {
      if (mounted) {
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // Clean Frameless Logo (Zero borders, modern subtle elevation)
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x38000000),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 50,
                            color: cs.onPrimary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Clean Branding Title
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/images/title.svg',
                      height: 28,
                      fit: BoxFit.contain,
                      semanticsLabel: 'GoPlay',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'LIVE SPORTS STREAMING',
                      style: GoPlayType.tagline.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        letterSpacing: 2.0,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Clean Lightweight Progress Indicator
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
