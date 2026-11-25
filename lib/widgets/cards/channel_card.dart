import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/typography.dart';
import '../../models/channel.dart';
import '../../providers/app_providers.dart';
import '../../services/channel_stream_launcher.dart';
import '../tv_focus_wrapper.dart';
import 'clean_card.dart';

/// Logical height of the card's fixed (non-text) content: vertical padding,
/// the logo avatar, and the gap beneath it.
///
/// [ChannelCard.measureHeight] uses this so the grid can pick a
/// `childAspectRatio` that always fits, at any text scale and tile width.
const double _kCardVerticalPadding = 8.0;
const double _kAvatarSize = 54.0;
const double _kAvatarGap = 8.0;
const double _kNameFontSize = GoPlayType.xs;
const double _kNameLineHeight = GoPlayType.leadingSnug;
const int _kNameMaxLines = 2;

/// Channel grid card.
///
/// A [ConsumerWidget] so it can watch *only its own* favorite flag. The parent
/// grid previously watched the whole `Set<String>` and passed `isFavorite` down,
/// which rebuilt every visible card on any toggle — and the card ignored the
/// value anyway, so no favorite affordance ever rendered.
class ChannelCard extends ConsumerWidget {
  final Channel channel;

  /// The list this card was rendered from — favorites, a category, a filtered
  /// search result.
  ///
  /// Passed to the player so switching channels there stays inside the list the
  /// user was actually looking at. When null the player falls back to "every
  /// channel in this channel's category", which is wrong for any curated or
  /// filtered grid: opening a favorite would drop the user into the whole
  /// category on the first channel switch.
  ///
  /// Held as the caller's own list and only mapped to IDs on tap, so a grid of
  /// several thousand cards costs nothing until one is opened.
  final List<Channel>? scope;

  const ChannelCard({super.key, required this.channel, this.scope});

  /// Minimum tile height needed to render this card without overflowing at the
  /// caller's current text scale.
  static double measureHeight(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(_kNameFontSize);
    final nameBlock = scaled * _kNameLineHeight * _kNameMaxLines;
    return (_kCardVerticalPadding * 2) +
        _kAvatarSize +
        _kAvatarGap +
        nameBlock;
  }

  void _toggleFavorite(WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(favoriteChannelIdsProvider.notifier).toggle(channel.id);
  }

  void _open(BuildContext context) {
    ChannelStreamLauncher.launch(context, channel, scope: scope);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    // Narrow selector: rebuilds this card only when *this* channel's favorite
    // state flips.
    final isFavorite = ref.watch(
      favoriteChannelIdsProvider.select((ids) => ids.contains(channel.id)),
    );
    final uiConfig = ref.watch(uiConfigProvider);
    final tabConfig = uiConfig.channelsTab;
    final channelCardStyle = uiConfig.componentStyles.channelCard;

    final quality = channel.quality?.trim();
    final hasQuality = quality != null && quality.isNotEmpty;
    final is4K = quality == '4K';

    final badgeBase = channelCardStyle.useCustomOverride
        ? GoPlayTheme.parseHex(channelCardStyle.qualityBadgeColor)
        : (is4K ? const Color(0xFF3B82F6) : GoPlayTheme.primary);
    final badgeText =
        isDark ? badgeBase : Color.lerp(badgeBase, Colors.black, 0.35)!;

    final initials = Center(
      child: Text(
        channel.initials,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: GoPlayType.base,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );

    final cardBg = Theme.of(context).cardColor;
    final cardRadius = channelCardStyle.borderRadius;
    final cardBorder = (channelCardStyle.useCustomOverride && channelCardStyle.borderWidth > 0)
        ? Border.all(
            color: GoPlayTheme.parseHex(channelCardStyle.borderColor),
            width: channelCardStyle.borderWidth,
          )
        : null;

    final useCustomOverride = channelCardStyle.useCustomOverride &&
        (channelCardStyle.backgroundColor.isNotEmpty || channelCardStyle.borderWidth > 0);

    final borderGradient = LinearGradient(
      begin: const Alignment(-0.85, -0.65),
      end: const Alignment(0.85, 0.55),
      stops: const [0.0, 0.45, 1.0],
      colors: [
        Colors.white.withValues(alpha: isDark ? 0.72 : 0.85),
        Colors.white.withValues(alpha: isDark ? 0.18 : 0.25),
        Colors.white.withValues(alpha: isDark ? 0.35 : 0.45),
      ],
    );

    final surfaceGradient = isDark
        ? const LinearGradient(
            begin: Alignment(-0.85, -0.9),
            end: Alignment(0.85, 0.9),
            stops: [0.0, 0.45, 1.0],
            colors: [
              Color(0x3BFFFFFF),
              Color(0x24FFFFFF),
              Color(0x1AFFFFFF),
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
          );

    return TvFocusable(
      borderRadius: BorderRadius.circular(cardRadius),
      onTap: () => _open(context),
      onLongPress: () => _toggleFavorite(ref),
      // Restores accessibility: the grid used to be wrapped in
      // ExcludeSemantics, hiding every channel from screen readers. One
      // container node per card keeps the tree small without hiding content.
      semanticLabel: hasQuality
          ? '${channel.displayName}, $quality${isFavorite ? ', favorite' : ''}'
          : '${channel.displayName}${isFavorite ? ', favorite' : ''}',
      child: SizedBox.expand(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: CustomPaint(
                foregroundPainter: useCustomOverride
                    ? null
                    : CleanLiquidGlassPainter(
                        strokeWidth: 1.0,
                        radius: cardRadius,
                        borderGradient: borderGradient,
                        isDark: isDark,
                      ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: useCustomOverride ? cardBg : null,
                    gradient: useCustomOverride ? null : surfaceGradient,
                    borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
                    border: useCustomOverride ? cardBorder : null,
                  ),
                  child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Main content ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: _kCardVerticalPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (tabConfig.showCardLogos) ...[
                      Center(
                        child: SizedBox(
                          width: _kAvatarSize,
                          height: _kAvatarSize,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: channel.logo != null && channel.logo!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: channel.logo!,
                                    fit: BoxFit.cover,
                                    width: _kAvatarSize,
                                    height: _kAvatarSize,
                                    memCacheWidth: 108,
                                    memCacheHeight: 108,
                                    fadeInDuration:
                                        const Duration(milliseconds: 150),
                                    imageBuilder: (context, imageProvider) =>
                                        DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        image: DecorationImage(
                                          image: imageProvider,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    placeholder: (context, url) => initials,
                                    errorWidget: (context, url, err) => initials,
                                  )
                                : initials,
                          ),
                        ),
                      ),
                      const SizedBox(height: _kAvatarGap),
                    ],
                    // Flexible so the name can never push the column past the
                    // tile height — the old fixed layout overflowed on 320dp
                    // widths and at any text scale above ~1.15.
                    if (tabConfig.showCardNames)
                      Flexible(
                        child: Text(
                          channel.displayName,
                          style: GoPlayType.inter(
                            color: cs.onSurface,
                            fontSize: _kNameFontSize,
                            fontWeight: FontWeight.w600,
                            height: _kNameLineHeight,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: _kNameMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),

              // ── Quality badge ─────────────────────────────────
              if (hasQuality && tabConfig.showQualityBadge)
                Positioned(
                  top: 6,
                  left: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: badgeBase.withValues(alpha: isDark ? 0.12 : 0.14),
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: badgeBase.withValues(alpha: 0.22),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      child: Text(
                        quality,
                        style: GoPlayType.meta.copyWith(color: badgeText),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),

              // ── Favorite indicator ────────────────────────────
              // Long-press toggles. Deliberately not a button: a second tap
              // target on a ~100dp tile competes with "open channel" and would
              // be below the minimum touch-target size.
              if (isFavorite && tabConfig.showCardFavorites)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 14,
                    color: cs.primary,
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
    );
  }
}
