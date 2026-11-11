import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/typography.dart';
import '../../models/event.dart';
import '../team_flag.dart';
import '../tv_focus_wrapper.dart';

/// Modern Event Card for GoPlay
///
/// Pixel-perfect 1:1 implementation of the Figma "Live match card" design:
/// - Exact card dimensions: 91dp nominal height with 12dp rounded corners
/// - Dual-stop vertical gradient (#1A1E23 -> #080A0D)
/// - Hot event support: bottom border & 12dp bottom corners highlighted in neon volt (#D4ED41)
/// - Bottom-docked 52x18.2 neon volt "HOT" badge sitting at Y = 72.8 -> 91.0 flush with bottom border
/// - Centered trio: LIVE badge (top 32), Match timer (top 53.5), and HOT badge (bottom 0)
/// - Top centered league header: small 13x13 category/league icon + 10.4sp league title
/// - Clean 40x40 circular team logos with centered names underneath
/// - Proportional match dividers (#30323B) framing the center column
/// - 52x18 red gradient LIVE badge with animated pulsing dot and elapsed ticker (hh:mm:ss)
/// - Upcoming match layout with kickoff time and clean date pill
/// - Clean dark gradient container with subtle glow and dividers
/// - Android TV D-Pad focus & navigation support via [TvFocusable]
class ModernEventCard extends ConsumerStatefulWidget {
  final SportEvent event;
  final VoidCallback? onTap;

  const ModernEventCard({
    super.key,
    required this.event,
    this.onTap,
  });

  /// Painted nominal height of the card matching Figma (91dp).
  static double tileHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return (91.0 * scale).clamp(91.0, 105.0);
  }

  /// Total extent including 8dp vertical gap for SliverFixedExtentList / Grid.
  static double tileExtent(BuildContext context) => tileHeight(context) + 8.0;

  @override
  ConsumerState<ModernEventCard> createState() => _ModernEventCardState();
}

class _ModernEventCardState extends ConsumerState<ModernEventCard>
    with SingleTickerProviderStateMixin {
  Timer? _liveTimer;
  late AnimationController _pulseController;
  late Animation<double> _dotFade;

  static const _kMonths = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _dotFade = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ModernEventCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.isLive != widget.event.isLive) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    if (widget.event.isLive) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      _liveTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _liveTimer?.cancel();
      _liveTimer = null;
      if (_pulseController.isAnimating) {
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  static String _formatTime(DateTime time) {
    final t = time.toLocal();
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display:$m $period';
  }

  static String _formatTimeInfo(SportEvent event) {
    final t = event.startTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final eventDay = DateTime(t.year, t.month, t.day);

    if (eventDay == today) return 'TODAY';
    if (eventDay == tomorrow) return 'TOMORROW';
    return '${_kMonths[t.month - 1]} ${t.day.toString().padLeft(2, '0')}';
  }

  String _formatElapsed(DateTime startTime) {
    final now = DateTime.now();
    final elapsed = now.difference(startTime);
    if (elapsed.isNegative) return '00:00:00';
    final h = elapsed.inHours.toString().padLeft(2, '0');
    final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Widget _buildLeagueIcon(SportEvent event) {
    final logoUrl = event.banner ?? event.categoryLogo;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.network(
          logoUrl,
          width: 13.0,
          height: 13.0,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _buildSportIconFallback(event.sport),
        ),
      );
    }
    return _buildSportIconFallback(event.sport);
  }

  Widget _buildSportIconFallback(String sport) {
    final s = sport.toLowerCase().trim();
    Color bg = const Color(0xFF1E88E5);
    IconData icon = Icons.sports_soccer;

    if (s.contains('tennis')) {
      bg = const Color(0xFF3234FF);
      icon = Icons.sports_tennis;
    } else if (s.contains('cricket')) {
      bg = const Color(0xFFE65100);
      icon = Icons.sports_cricket;
    } else if (s.contains('dart')) {
      bg = const Color(0xFF8D6E63);
      icon = Icons.adjust;
    } else if (s.contains('basket')) {
      bg = const Color(0xFFFF8A00);
      icon = Icons.sports_basketball;
    } else if (s.contains('racing') || s.contains('motor')) {
      bg = const Color(0xFFFF1818);
      icon = Icons.sports_motorsports;
    }

    return Container(
      width: 13.0,
      height: 13.0,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          icon,
          size: 8.5,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final isLive = event.isLive;
    final isFeatured = event.isFeatured;
    final cardHeight = ModernEventCard.tileHeight(context);

    final leagueText = event.league.isNotEmpty
        ? (event.sport.isNotEmpty
            ? '${event.sport.toUpperCase()} || ${event.league.toUpperCase()}'
            : event.league.toUpperCase())
        : (event.sport.isNotEmpty ? event.sport.toUpperCase() : 'LIVE MATCH');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RepaintBoundary(
        child: TvFocusable(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: SizedBox(
            height: cardHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // --- 1. CARD CONTAINER (Gradient background, glow, rounded corners) ---
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(Radius.circular(12)),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF1A1E23),
                              Color(0xFF080A0D),
                            ],
                          ),
                          boxShadow: isFeatured
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFD4ED41).withValues(alpha: 0.16),
                                    blurRadius: 6,
                                    spreadRadius: 0.0,
                                    offset: const Offset(0, 2.5),
                                  ),
                                ]
                              : const [
                                  BoxShadow(
                                    color: Color(0x1A000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              // --- TOP HEADER: Small 13x13 Logo + League Title ---
                              Positioned(
                                top: 6.0,
                                left: 16.0,
                                right: 16.0,
                                height: 15.0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildLeagueIcon(event),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        leagueText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: Color(0xFFBFC0D0),
                                          fontSize: 10.4,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.3,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // --- LEFT: HOME TEAM (Exact Figma 3px margin, 90px width, 40x40 logo + 2px gap + name) ---
                              Positioned(
                                top: isFeatured ? 22.0 : 20.0,
                                left: w * (3.0 / 380.0),
                                width: w * (90.0 / 380.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TeamFlagWidget(
                                      flag: event.homeTeam.flag,
                                      size: 33.3, // size 33.3 * 1.2 = 40.0dp
                                      showBorder: false,
                                    ),
                                    const SizedBox(height: 2.0),
                                    Text(
                                      event.homeTeam.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: GoPlayType.family,
                                        color: Color(0xFFD2D2DC),
                                        fontSize: 10.2,
                                        fontWeight: FontWeight.w500,
                                        height: 1.15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // --- RIGHT: AWAY TEAM (Exact Figma 3px margin, 90px width, 40x40 logo + 2px gap + name) ---
                              Positioned(
                                top: isFeatured ? 22.0 : 20.0,
                                right: w * (3.0 / 380.0),
                                width: w * (90.0 / 380.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TeamFlagWidget(
                                      flag: event.awayTeam.flag,
                                      size: 33.3, // size 33.3 * 1.2 = 40.0dp
                                      showBorder: false,
                                    ),
                                    const SizedBox(height: 2.0),
                                    Text(
                                      event.awayTeam.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: GoPlayType.family,
                                        color: Color(0xFFD2D2DC),
                                        fontSize: 10.2,
                                        fontWeight: FontWeight.w500,
                                        height: 1.15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // --- MATCH DIVIDER (LEFT) ---
                              Positioned(
                                top: isFeatured ? 37.0 : 34.0,
                                left: w * (119.0 / 380.0),
                                width: 1.0,
                                height: 21.0,
                                child: Container(color: const Color(0xFF30323B)),
                              ),

                              // --- MATCH DIVIDER (RIGHT) ---
                              Positioned(
                                top: isFeatured ? 37.0 : 34.0,
                                left: w * (261.0 / 380.0),
                                width: 1.0,
                                height: 21.0,
                                child: Container(color: const Color(0xFF30323B)),
                              ),

                              // --- CENTER ELEMENTS (Exact Figma vertical placement) ---
                              if (isLive) ...[
                                // LIVE Badge (52x18)
                                Positioned(
                                  top: isFeatured ? 32.0 : 29.0,
                                  left: (w - 52.0) / 2.0,
                                  width: 52.0,
                                  height: 18.0,
                                  child: _buildLiveBadge(),
                                ),
                                // Match timer (02:58:44)
                                Positioned(
                                  top: isFeatured ? 53.5 : 51.0,
                                  left: 0,
                                  right: 0,
                                  child: Text(
                                    _formatElapsed(event.startTime),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: GoPlayType.family,
                                      color: Color(0xFFC9C9DC),
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                // Upcoming match time
                                Positioned(
                                  top: isFeatured ? 32.0 : 34.0,
                                  left: 0,
                                  right: 0,
                                  child: Text(
                                    _formatTime(event.startTime),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFamily: GoPlayType.family,
                                      color: Color(0xFFF1F1F1),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                // Date pill
                                Positioned(
                                  top: isFeatured ? 52.0 : 55.0,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7.0,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4.0),
                                      ),
                                      child: Text(
                                        _formatTimeInfo(event),
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontFamily: GoPlayType.family,
                                          color: Color(0xFFBFC0D0),
                                          fontSize: 9.2,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              // --- DOCKED "HOT" BADGE (Pinned to bottom: 0, 80x16 curved tab) ---
                              if (isFeatured)
                                Positioned(
                                  bottom: 0.0,
                                  left: (w - 80.0) / 2.0,
                                  width: 80.0,
                                  height: 16.0,
                                  child: _buildHotBadge(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // --- 2. CARD BORDER (Subtle perimeter with volt highlight at bottom for HOT events) ---
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CardBorderPainter(
                            isFeatured: isFeatured,
                            radius: 12.0,
                            strokeWidth: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Exact 52x18 Figma LIVE badge with red gradient and pulsing dot.
  Widget _buildLiveBadge() {
    return Container(
      width: 52.0,
      height: 18.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9.0),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE22745),
            Color(0xFFBE1430),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33E22745),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: _dotFade,
            child: Container(
              width: 4.0,
              height: 4.0,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 4.5),
          const Text(
            'LIVE',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              color: Colors.white,
              fontSize: 10.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Exact 80x16 Figma "Hot badge · curved tab" (node-id=29:36)
  /// Features reverse-curve shoulders, vector flame icon, and bold "HOT" typography.
  Widget _buildHotBadge() {
    return const SizedBox(
      width: 80.0,
      height: 16.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Curved shoulder lime tab background (#D4FF00)
          Positioned.fill(
            child: CustomPaint(
              painter: _CurvedTabPainter(color: Color(0xFFD4FF00)),
            ),
          ),

          // 2. Centered content: flame icon (9.05x11) + 4px gap + HOT text (11.2sp)
          Positioned(
            top: 2.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 9.05,
                  height: 11.0,
                  child: CustomPaint(
                    painter: _FlameIconPainter(),
                  ),
                ),
                SizedBox(width: 4.0),
                Text(
                  'HOT',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    color: Colors.black,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for Figma "Lime tab with curved shoulders" (node-id=29:37)
/// Bezier path: M0 16 C7 16 9 13 12 6 C14 1 18 0 23 0 H57 C62 0 66 1 68 6 C71 13 73 16 80 16 H0 Z
class _CurvedTabPainter extends CustomPainter {
  final Color color;

  const _CurvedTabPainter({this.color = const Color(0xFFD4FF00)});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 80.0;
    final scaleY = size.height / 16.0;

    final path = Path()
      ..moveTo(0.0 * scaleX, 16.0 * scaleY)
      ..cubicTo(
        7.0 * scaleX,
        16.0 * scaleY,
        9.0 * scaleX,
        13.0 * scaleY,
        12.0 * scaleX,
        6.0 * scaleY,
      )
      ..cubicTo(
        14.0 * scaleX,
        1.0 * scaleY,
        18.0 * scaleX,
        0.0 * scaleY,
        23.0 * scaleX,
        0.0 * scaleY,
      )
      ..lineTo(57.0 * scaleX, 0.0 * scaleY)
      ..cubicTo(
        62.0 * scaleX,
        0.0 * scaleY,
        66.0 * scaleX,
        1.0 * scaleY,
        68.0 * scaleX,
        6.0 * scaleY,
      )
      ..cubicTo(
        71.0 * scaleX,
        13.0 * scaleY,
        73.0 * scaleX,
        16.0 * scaleY,
        80.0 * scaleX,
        16.0 * scaleY,
      )
      ..lineTo(0.0 * scaleX, 16.0 * scaleY)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CurvedTabPainter oldDelegate) => oldDelegate.color != color;
}

/// Exact vector flame icon painter from Figma (node-id=29:38)
/// Path dimensions: 9.05 x 11.0
class _FlameIconPainter extends CustomPainter {
  const _FlameIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 9.05;
    final scaleY = size.height / 11.0;

    final path = Path()
      ..moveTo(4.6 * scaleX, 0.0 * scaleY)
      ..cubicTo(
        4.5 * scaleX,
        2.0 * scaleY,
        7.0 * scaleX,
        2.8 * scaleY,
        6.8 * scaleX,
        5.1 * scaleY,
      )
      ..cubicTo(
        7.6 * scaleX,
        4.9 * scaleY,
        7.8 * scaleX,
        4.0 * scaleY,
        7.7 * scaleX,
        3.3 * scaleY,
      )
      ..cubicTo(
        8.9 * scaleX,
        4.7 * scaleY,
        9.3 * scaleX,
        6.2 * scaleY,
        8.9 * scaleX,
        7.8 * scaleY,
      )
      ..cubicTo(
        8.4 * scaleX,
        9.8 * scaleY,
        6.7 * scaleX,
        11.0 * scaleY,
        4.5 * scaleX,
        11.0 * scaleY,
      )
      ..cubicTo(
        1.8 * scaleX,
        11.0 * scaleY,
        0.0 * scaleX,
        9.3 * scaleY,
        0.0 * scaleX,
        6.8 * scaleY,
      )
      ..cubicTo(
        0.0 * scaleX,
        5.2 * scaleY,
        0.8 * scaleX,
        3.7 * scaleY,
        1.8 * scaleX,
        2.9 * scaleY,
      )
      ..cubicTo(
        1.6 * scaleX,
        4.5 * scaleY,
        2.2 * scaleX,
        5.0 * scaleY,
        2.8 * scaleX,
        5.1 * scaleY,
      )
      ..cubicTo(
        2.4 * scaleX,
        3.1 * scaleY,
        3.3 * scaleX,
        1.6 * scaleY,
        4.6 * scaleX,
        0.0 * scaleY,
      )
      ..close();

    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlameIconPainter oldDelegate) => false;
}

/// Custom painter for card border:
/// Base border is a clean subtle grey perimeter (#526073).
/// When isFeatured is true, the bottom border is highlighted in bright neon volt (#D4FF00)
/// and smoothly blends through the bottom-left and bottom-right 12dp corner radii,
/// leaving the vertical side borders clean without yellow climbing up the walls.
class _CardBorderPainter extends CustomPainter {
  final bool isFeatured;
  final double radius;
  final double strokeWidth;

  const _CardBorderPainter({
    required this.isFeatured,
    this.radius = 12.0,
    this.strokeWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final halfStroke = strokeWidth / 2.0;
    final cornerRadius = (radius - halfStroke).clamp(1.0, radius);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        halfStroke,
        halfStroke,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(cornerRadius),
    );

    // 1. Base clean border around the entire card
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xB3526073);

    canvas.drawRRect(rrect, basePaint);

    if (isFeatured) {
      // 2. Featured highlight along the bottom edge and bottom 2 corners
      // Smoothly blends from 0% alpha at the top of the corner to 100% neon volt at the bottom edge.
      final bottomPath = Path()
        ..moveTo(halfStroke, size.height - radius)
        ..arcToPoint(
          Offset(radius, size.height - halfStroke),
          radius: Radius.circular(cornerRadius),
          clockwise: false,
        )
        ..lineTo(size.width - radius, size.height - halfStroke)
        ..arcToPoint(
          Offset(size.width - halfStroke, size.height - radius),
          radius: Radius.circular(cornerRadius),
          clockwise: false,
        );

      final cornerTopRatio = ((size.height - radius) / size.height).clamp(0.0, 1.0);

      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00D4FF00),
            Color(0x00D4FF00),
            Color(0xFFD4FF00),
          ],
          stops: [
            0.0,
            cornerTopRatio,
            1.0,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(bottomPath, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CardBorderPainter oldDelegate) =>
      oldDelegate.isFeatured != isFeatured ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}
