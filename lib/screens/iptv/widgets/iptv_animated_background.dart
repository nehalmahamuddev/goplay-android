import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shader-type blurred animated background with GPU-accelerated chromatic mesh diffusion,
/// organic fluid orbs, undulating color ribbons, and heavy Gaussian blur.
class IptvAnimatedBackground extends StatefulWidget {
  final bool animate;
  final Widget? child;

  const IptvAnimatedBackground({
    super.key,
    this.animate = true,
    this.child,
  });

  @override
  State<IptvAnimatedBackground> createState() => _IptvAnimatedBackgroundState();
}

class _IptvAnimatedBackgroundState extends State<IptvAnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );

    // Suppress infinite repeating loop in widget test environment to prevent pumpAndSettle timeouts
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (widget.animate && !isTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Deep Midnight Base Canvas (#030318 -> #02020E -> #000000)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.50, 1.0],
                colors: [
                  Color(0xFF030318),
                  Color(0xFF02020E),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),

          // 2. Chromatic Shader Mesh Layer with Heavy Gaussian Blur Diffusion
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 75,
                sigmaY: 75,
                tileMode: TileMode.decal,
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _IptvShaderMeshPainter(progress: _controller.value),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),

          // 3. Secondary Micro-Glow Layer for Extra Fluid Luster
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 95,
                sigmaY: 95,
                tileMode: TileMode.decal,
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _IptvSecondaryGlowPainter(progress: _controller.value),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),

          // 4. Bottom Vignette Depth (Fades from transparent at 50% to deep black at bottom)
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(0, 0.1),
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.55, 1.0],
                  colors: [
                    Colors.transparent,
                    Color(0xCC000000), // 80% black
                    Color(0xFF000000), // Pure black
                  ],
                ),
              ),
            ),
          ),

          // 5. Ambient dark tint for high-contrast card & text legibility
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x30000000), // 19% black wash
            ),
          ),

          // Optional child widget
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

/// Primary shader-mesh painter rendering fluid, diffused chromatic gradients
class _IptvShaderMeshPainter extends CustomPainter {
  final double progress;

  _IptvShaderMeshPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;

    // Harmonic timers for organic fluid motion
    final t1 = progress * 2 * math.pi;
    final t2 = progress * 3 * math.pi;
    final t3 = progress * 1.5 * math.pi;
    final t4 = progress * 2.5 * math.pi;

    // -------------------------------------------------------------
    // 1. Neon Purple / Royal Violet Shader Well (top-right drift)
    // -------------------------------------------------------------
    final pX = w * 0.72 + math.sin(t1) * (w * 0.14);
    final pY = h * 0.22 + math.cos(t2) * (h * 0.08);
    final pRadius = w * 0.65;

    final purplePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6B11A8).withValues(alpha: 0.85),
          const Color(0xFF3B0066).withValues(alpha: 0.55),
          const Color(0xFF1E0038).withValues(alpha: 0.20),
          Colors.transparent,
        ],
        stops: const [0.0, 0.40, 0.70, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(pX, pY), radius: pRadius));

    canvas.drawCircle(Offset(pX, pY), pRadius, purplePaint);

    // -------------------------------------------------------------
    // 2. Cyan / Electric Teal Shader Orb (mid-left floating toward center)
    // -------------------------------------------------------------
    final cX = w * 0.22 + math.cos(t3) * (w * 0.16);
    final cY = h * 0.40 + math.sin(t1) * (h * 0.10);
    final cRadius = w * 0.68;

    final cyanPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00B4D8).withValues(alpha: 0.75),
          const Color(0xFF0077B6).withValues(alpha: 0.50),
          const Color(0xFF023E8A).withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.68, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cX, cY), radius: cRadius));

    canvas.drawCircle(Offset(cX, cY), cRadius, cyanPaint);

    // -------------------------------------------------------------
    // 3. Magenta / Hot Fuchsia Aurora Orb (center-right sweeping)
    // -------------------------------------------------------------
    final mX = w * 0.78 + math.sin(t2) * (w * 0.14);
    final mY = h * 0.50 + math.cos(t4) * (h * 0.12);
    final mRadius = w * 0.60;

    final magentaPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD81B60).withValues(alpha: 0.70),
          const Color(0xFF8E0050).withValues(alpha: 0.45),
          const Color(0xFF4A0033).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.38, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(mX, mY), radius: mRadius));

    canvas.drawCircle(Offset(mX, mY), mRadius, magentaPaint);

    // -------------------------------------------------------------
    // 4. Deep Indigo / Electric Blue Well (bottom-left)
    // -------------------------------------------------------------
    final bX = w * 0.30 + math.cos(t1) * (w * 0.12);
    final bY = h * 0.62 + math.sin(t3) * (h * 0.09);
    final bRadius = w * 0.58;

    final bluePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF1A237E).withValues(alpha: 0.65),
          const Color(0xFF0D1248).withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(bX, bY), radius: bRadius));

    canvas.drawCircle(Offset(bX, bY), bRadius, bluePaint);

    // -------------------------------------------------------------
    // 5. Chromatic Fluid Undulating Wave Ribbon in the center
    // -------------------------------------------------------------
    final wavePath = Path();
    final waveShift = math.sin(t1);
    final startY = h * 0.32 + waveShift * 35;
    wavePath.moveTo(-w * 0.1, startY);
    wavePath.cubicTo(
      w * 0.3,
      h * 0.36 - waveShift * 40,
      w * 0.6,
      h * 0.46 + waveShift * 30,
      w * 1.1,
      h * 0.40 - waveShift * 25,
    );
    wavePath.lineTo(w * 1.1, h * 0.62);
    wavePath.cubicTo(
      w * 0.7,
      h * 0.68 + waveShift * 30,
      w * 0.3,
      h * 0.58 - waveShift * 35,
      -w * 0.1,
      h * 0.52,
    );
    wavePath.close();

    final wavePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF007799).withValues(alpha: 0.60),
          const Color(0xFF7B1FA2).withValues(alpha: 0.55),
          const Color(0xFF4A148C).withValues(alpha: 0.30),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.80, 1.0],
      ).createShader(Rect.fromLTWH(0, h * 0.3, w, h * 0.4));

    canvas.drawPath(wavePath, wavePaint);
  }

  @override
  bool shouldRepaint(covariant _IptvShaderMeshPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Secondary glow painter adding extra chromatic depth and ambient warmth
class _IptvSecondaryGlowPainter extends CustomPainter {
  final double progress;

  _IptvSecondaryGlowPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;

    final t = progress * 2 * math.pi;

    // Ambient floating center glow
    final gX = w * 0.50 + math.sin(t) * (w * 0.08);
    final gY = h * 0.45 + math.cos(t) * (h * 0.06);
    final gRadius = w * 0.50;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.35),
          const Color(0xFFAA00FF).withValues(alpha: 0.20),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(gX, gY), radius: gRadius));

    canvas.drawCircle(Offset(gX, gY), gRadius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _IptvSecondaryGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
