import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';

/// Bottom sheet replicating `R.layout.layout_view_settings` (`res/qr.xml`, `context.md` §6.2).
/// Allows switching List / Grid / Poster / Square modes, tuning Columns & Poster Aspect Ratio,
/// and resetting settings for either the current playlist or all playlists.
class IptvViewSettingsSheet extends ConsumerWidget {
  final String playlistId;

  const IptvViewSettingsSheet({super.key, required this.playlistId});

  static Future<void> show(BuildContext context, String playlistId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IptvViewSettingsSheet(playlistId: playlistId),
    );
  }

  int _maxColumnsForWidth(double widthDp) {
    final base = (widthDp / 120.0).floor().clamp(1, 10);
    return base + 3; // Matches `context.md` §6.2: (screenWidthDp / 120).coerceAtLeast(1) + 3
  }

  Future<void> _confirmReset(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16171B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF282B36)),
        ),
        title: const Text(
          'Reset View Settings',
          style: TextStyle(
            fontFamily: GoPlayType.family,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'Reset layout customization for only this playlist or across all saved playlists?',
          style: TextStyle(
            fontFamily: GoPlayType.family,
            color: Color(0xFF9EA2B0),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('this'),
            child: const Text(
              'RESET THIS ONLY',
              style: TextStyle(
                color: Color(0xFFA8C7FA),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA8C7FA),
              foregroundColor: const Color(0xFF0A1C36),
            ),
            child: const Text(
              'RESET ALL',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (action == 'this') {
      await ref.read(iptvViewConfigsProvider.notifier).resetPlaylist(playlistId);
    } else if (action == 'all') {
      await ref.read(iptvViewConfigsProvider.notifier).resetAll();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(iptvViewConfigsProvider);
    final config = configs[playlistId] ?? const IptvViewConfig();
    final widthDp = MediaQuery.sizeOf(context).width;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final maxCols = _maxColumnsForWidth(widthDp);
    final clampedSpan = config.spanCount.clamp(1, maxCols);
    final ratioPreset = IptvPosterRatioPreset.byIndex(config.posterRatioIndex);

    final columnsEnabled = config.mode == IptvDisplayMode.poster ||
        config.mode == IptvDisplayMode.square;
    final ratioEnabled = config.mode == IptvDisplayMode.poster;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141519),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF282B36), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF383B46),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'View Settings',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _confirmReset(context, ref),
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  size: 17,
                  color: Color(0xFFA8C7FA),
                ),
                label: const Text(
                  'Reset',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFA8C7FA),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Text(
            'DISPLAY MODE',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8E9099),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              _ModeChip(
                icon: Icons.view_list_rounded,
                label: 'List',
                selected: config.mode == IptvDisplayMode.list,
                onTap: () => _updateMode(ref, config, IptvDisplayMode.list),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.grid_view_rounded,
                label: 'Grid',
                selected: config.mode == IptvDisplayMode.grid,
                onTap: () => _updateMode(ref, config, IptvDisplayMode.grid),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.stay_current_portrait_rounded,
                label: 'Poster',
                selected: config.mode == IptvDisplayMode.poster,
                onTap: () => _updateMode(ref, config, IptvDisplayMode.poster),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                icon: Icons.crop_square_rounded,
                label: 'Square',
                selected: config.mode == IptvDisplayMode.square,
                onTap: () => _updateMode(ref, config, IptvDisplayMode.square),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Columns Slider (active for Poster & Square)
          Opacity(
            opacity: columnsEnabled ? 1.0 : 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Columns',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      columnsEnabled
                          ? '$clampedSpan columns'
                          : (config.mode == IptvDisplayMode.list ? '1 (List)' : '2 (Fixed)'),
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA8C7FA),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFA8C7FA),
                    inactiveTrackColor: const Color(0xFF282B36),
                    thumbColor: const Color(0xFFA8C7FA),
                    overlayColor: const Color(0x33A8C7FA),
                  ),
                  child: Slider(
                    min: 1.0,
                    max: maxCols.toDouble(),
                    divisions: (maxCols - 1).clamp(1, 20),
                    value: clampedSpan.toDouble(),
                    onChanged: columnsEnabled
                        ? (v) {
                            HapticFeedback.selectionClick();
                            ref.read(iptvViewConfigsProvider.notifier).setConfig(
                                  playlistId,
                                  config.copyWith(spanCount: v.round()),
                                );
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),

          // Aspect Ratio Slider (active for Poster only)
          Opacity(
            opacity: ratioEnabled ? 1.0 : 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Poster Aspect Ratio',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      ratioPreset.label,
                      style: const TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFA8C7FA),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFA8C7FA),
                    inactiveTrackColor: const Color(0xFF282B36),
                    thumbColor: const Color(0xFFA8C7FA),
                    overlayColor: const Color(0x33A8C7FA),
                  ),
                  child: Slider(
                    min: 0.0,
                    max: 8.0,
                    divisions: 8,
                    value: config.posterRatioIndex.clamp(0, 8).toDouble(),
                    onChanged: ratioEnabled
                        ? (v) {
                            HapticFeedback.selectionClick();
                            ref.read(iptvViewConfigsProvider.notifier).setConfig(
                                  playlistId,
                                  config.copyWith(posterRatioIndex: v.round()),
                                );
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateMode(
    WidgetRef ref,
    IptvViewConfig current,
    IptvDisplayMode mode,
  ) {
    HapticFeedback.selectionClick();
    final defaultSpan = switch (mode) {
      IptvDisplayMode.list => 1,
      IptvDisplayMode.grid => 2,
      IptvDisplayMode.poster => current.spanCount < 2 ? 2 : current.spanCount,
      IptvDisplayMode.square => current.spanCount < 3 ? 3 : current.spanCount,
    };
    ref.read(iptvViewConfigsProvider.notifier).setConfig(
          playlistId,
          current.copyWith(mode: mode, spanCount: defaultSpan),
        );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1F2B3D)
                : const Color(0xFF1A1C22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA8C7FA)
                  : const Color(0xFF282B36),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? const Color(0xFFA8C7FA) : Colors.white70,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : const Color(0xFF9EA2B0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
