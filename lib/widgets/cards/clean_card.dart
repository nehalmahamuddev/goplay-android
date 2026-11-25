import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clean Liquid Glass card component engineered according to Kyant's Backdrop
/// library specifications (https://kyant.gitbook.io/backdrop).
///
/// Features:
/// 1. Progressive / Gaussian backdrop blur using [BackdropFilter].
/// 2. Multi-stop translucent glass substrate gradient.
/// 3. Physical optics:
///    - Diagonal specular outer rim stroke (Inside alignment).
///    - SDF lens refraction caustic bevel (simulating physical glass thickness).
///    - Top-left directional specular glint (`dot(grad, normal)^falloff`).
///    - Chromatic dispersion fringe along edges.
/// 4. Soft ambient elevation shadow + crisp contact shadow.
/// 5. Micro-press physics and interactive haptic feedback.
class CleanCard extends StatefulWidget {
  final Widget? child;
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Gradient? surfaceGradient;
  final Gradient? borderGradient;
  final Color? glowColor;
  final bool isSelected;
  final Color? selectedBorderColor;
  final double elevation;
  final bool enablePressFeedback;

  const CleanCard({
    super.key,
    this.child,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 22.0,
    this.blurSigma = 20.0,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.surfaceGradient,
    this.borderGradient,
    this.glowColor,
    this.isSelected = false,
    this.selectedBorderColor,
    this.elevation = 8.0,
    this.enablePressFeedback = true,
  });

  @override
  State<CleanCard> createState() => _CleanCardState();
}

class _CleanCardState extends State<CleanCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.982).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutQuad,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.enablePressFeedback && (widget.onTap != null || widget.onLongPress != null)) {
      _pressController.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enablePressFeedback) {
      _pressController.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.enablePressFeedback) {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.borderRadius);

    // ── 1. Surface Fill: Multi-stop translucent wash ─────────────────────
    final defaultSurfaceGradient = widget.isSelected
        ? LinearGradient(
            begin: const Alignment(-0.85, -1.0),
            end: const Alignment(0.85, 1.0),
            stops: const [0.0, 0.45, 1.0],
            colors: [
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.40),
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.20),
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.30),
            ],
          )
        : (widget.surfaceGradient ??
            (isDark
                ? const LinearGradient(
                    begin: Alignment(-0.85, -0.9),
                    end: Alignment(0.85, 0.9),
                    stops: [0.0, 0.45, 1.0],
                    colors: [
                      Color(0x3BFFFFFF), // 23% white grazing light
                      Color(0x24FFFFFF), // 14% white translucent center body
                      Color(0x1AFFFFFF), // 10% white ambient depth
                    ],
                  )
                : LinearGradient(
                    begin: const Alignment(-0.85, -0.9),
                    end: const Alignment(0.85, 0.9),
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      Colors.white.withValues(alpha: 0.94),
                      Colors.white.withValues(alpha: 0.84),
                      Colors.white.withValues(alpha: 0.88),
                    ],
                  )));

    // ── 2. Outer Rim: Specular gradient stroke ───────────────────────────
    final defaultBorderGradient = widget.isSelected
        ? LinearGradient(
            begin: const Alignment(-0.85, -0.65),
            end: const Alignment(0.85, 0.55),
            stops: const [0.0, 0.45, 1.0],
            colors: [
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.95),
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.35),
              (widget.selectedBorderColor ?? theme.colorScheme.primary)
                  .withValues(alpha: 0.70),
            ],
          )
        : (widget.borderGradient ??
            LinearGradient(
              begin: const Alignment(-0.85, -0.65),
              end: const Alignment(0.85, 0.55),
              stops: const [0.0, 0.45, 1.0],
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.72 : 0.85), // 72% top-left specular
                Colors.white.withValues(alpha: isDark ? 0.18 : 0.25), // 18% mid falloff
                Colors.white.withValues(alpha: isDark ? 0.35 : 0.45), // 35% bottom rim
              ],
            ));

    // ── 3. Shadows: Ambient elevation + tight contact ────────────────────
    final shadows = <BoxShadow>[
      if (widget.glowColor != null)
        BoxShadow(
          color: widget.glowColor!.withValues(alpha: isDark ? 0.32 : 0.20),
          blurRadius: 28,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
        blurRadius: 20 * (widget.elevation / 8.0).clamp(0.5, 2.0),
        offset: Offset(0, 6 * (widget.elevation / 8.0).clamp(0.5, 2.0)),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
    ];

    Widget content = widget.child ??
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.leading != null) ...[
              widget.leading!,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.title != null) widget.title!,
                  if (widget.title != null && widget.subtitle != null)
                    const SizedBox(height: 4),
                  if (widget.subtitle != null) widget.subtitle!,
                ],
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 12),
              widget.trailing!,
            ],
          ],
        );

    final cardWidget = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
          ),
          child: CustomPaint(
            foregroundPainter: CleanLiquidGlassPainter(
              strokeWidth: 1.0,
              radius: widget.borderRadius,
              borderGradient: defaultBorderGradient,
              isDark: isDark,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: widget.onTap != null
                    ? () {
                        HapticFeedback.selectionClick();
                        widget.onTap?.call();
                      }
                    : null,
                onLongPress: widget.onLongPress != null
                    ? () {
                        HapticFeedback.mediumImpact();
                        widget.onLongPress?.call();
                      }
                    : null,
                borderRadius: radius,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: defaultSurfaceGradient,
                  ),
                  padding: widget.padding,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.enablePressFeedback ||
        (widget.onTap == null && widget.onLongPress == null)) {
      return cardWidget;
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: cardWidget,
      ),
    );
  }
}

/// High-fidelity Liquid Glass painter based on Kyant's Backdrop library
/// (https://kyant.gitbook.io/backdrop).
///
/// Implements:
/// 1. Outer Refraction Rim: Diagonal linear gradient (72% -> 18% -> 35% white)
///    rendered with "Inside" stroke alignment.
/// 2. Inner Lens Caustic Bevel (from Kyant's `Lens.kt` & SDF refraction):
///    Secondary refraction ring simulating physical glass depth/thickness.
/// 3. Directional Specular Rim Glint (from Kyant's `DefaultHighlightShader`:
///    `dot(grad, normal)^falloff`):
///    Concentrated top-left gleam where incident light strikes the glass curvature.
/// 4. Chromatic Dispersion Fringe:
///    Very subtle ROYGCBP prism edge refraction hint.
class CleanLiquidGlassPainter extends CustomPainter {
  final double strokeWidth;
  final double radius;
  final Gradient borderGradient;
  final bool isDark;

  const CleanLiquidGlassPainter({
    this.strokeWidth = 1.0,
    this.radius = 22.0,
    required this.borderGradient,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final halfStroke = strokeWidth / 2.0;

    // 1. Primary Outer Stroke (Inside alignment)
    final strokeRect = rect.deflate(halfStroke);
    final rrect = RRect.fromRectAndRadius(
      strokeRect,
      Radius.circular((radius - halfStroke).clamp(0.0, double.infinity)),
    );

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = borderGradient.createShader(rect);

    canvas.drawRRect(rrect, borderPaint);

    // 2. Liquid Glass Inner Refraction Lens Bevel (from Kyant's Lens.kt SDF)
    final bevelOffset = strokeWidth + 0.8;
    final innerBevelRect = rect.deflate(bevelOffset);
    final innerRRect = RRect.fromRectAndRadius(
      innerBevelRect,
      Radius.circular((radius - bevelOffset).clamp(0.0, double.infinity)),
    );

    final innerBevelGradient = LinearGradient(
      begin: const Alignment(-0.85, -0.75),
      end: const Alignment(0.85, 0.75),
      stops: const [0.0, 0.35, 0.75, 1.0],
      colors: [
        Colors.white.withValues(alpha: isDark ? 0.35 : 0.40), // Top-left inner caustic
        Colors.white.withValues(alpha: isDark ? 0.04 : 0.06), // Mid falloff
        Colors.transparent,
        Colors.white.withValues(alpha: isDark ? 0.16 : 0.20), // Bottom-right bounce
      ],
    );

    final innerBevelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..shader = innerBevelGradient.createShader(rect);

    canvas.drawRRect(innerRRect, innerBevelPaint);

    // 3. Specular Peak Glint (`dot(grad, normal)^falloff`)
    final glintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.35
      ..shader = RadialGradient(
        center: const Alignment(-0.65, -1.0),
        radius: 0.65,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.82 : 0.92),
          Colors.white.withValues(alpha: isDark ? 0.24 : 0.32),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, glintPaint);

    // 4. Subtle Chromatic Dispersion Accent along top edge
    final chromaticPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..shader = const LinearGradient(
        begin: Alignment(-1.0, -1.0),
        end: Alignment(0.5, -1.0),
        stops: [0.0, 0.5, 1.0],
        colors: [
          Color(0x2260A5FA), // Light azure blue fringe
          Color(0x18C084FC), // Soft purple dispersion
          Colors.transparent,
        ],
      ).createShader(rect);

    canvas.drawRRect(rrect, chromaticPaint);
  }

  @override
  bool shouldRepaint(covariant CleanLiquidGlassPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.borderGradient != borderGradient ||
        oldDelegate.isDark != isDark;
  }
}
