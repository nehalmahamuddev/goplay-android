import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Player and Video Playback Settings Screen matching Upstream's 'Player' subpage.
class PlayerSettingsScreen extends ConsumerStatefulWidget {
  const PlayerSettingsScreen({super.key});

  @override
  ConsumerState<PlayerSettingsScreen> createState() => _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends ConsumerState<PlayerSettingsScreen> {
  bool _hwAcceleration = true;
  bool _autoPlay = true;
  bool _backgroundAudio = false;
  String _selectedBufferMode = 'Balanced';
  String _selectedAspectRatio = '16:9 (Fit)';

  final List<String> _bufferModes = ['Fast Load', 'Balanced', 'High Stability'];
  final List<String> _aspectRatios = ['16:9 (Fit)', 'Stretch', 'Original'];

  void _showSingleChoiceDialog({
    required String title,
    required List<String> options,
    required String currentValue,
    required ValueChanged<String> onSelected,
  }) {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: GoPlayType.family,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: RadioGroup<String>(
          groupValue: currentValue,
          onChanged: (val) {
            if (val != null) {
              onSelected(val);
              Navigator.of(context).pop();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              final isSelected = opt == currentValue;
              return InkWell(
                onTap: () {
                  onSelected(opt);
                  Navigator.of(context).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? cs.primary : cs.onSurface,
                          ),
                        ),
                      ),
                      Radio<String>(
                        value: opt,
                        activeColor: cs.primary,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Pinned App Bar
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: headerBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 24),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Player',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -0.3,
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildListDelegate([
              // ─── Playback Engine Section ───
              const SettingSectionHeader(title: 'Playback Engine'),
              SettingSwitchTile(
                icon: Icons.memory_rounded,
                title: 'Hardware Acceleration',
                subtitle: 'Leverages GPU hardware decoding for ultra-low latency & cooler device',
                value: _hwAcceleration,
                onChanged: (val) => setState(() => _hwAcceleration = val),
              ),
              SettingSwitchTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'Auto-play Stream on Open',
                subtitle: 'Automatically start live broadcast upon entering the player view',
                value: _autoPlay,
                onChanged: (val) => setState(() => _autoPlay = val),
              ),
              SettingSwitchTile(
                icon: Icons.headphones_outlined,
                title: 'Background Audio Playback',
                subtitle: 'Keep audio active when screen is turned off or navigating away',
                value: _backgroundAudio,
                onChanged: (val) => setState(() => _backgroundAudio = val),
              ),

              const SizedBox(height: 12),

              // ─── Buffering & Video Layout Section ───
              const SettingSectionHeader(title: 'Buffering & Layout'),
              SettingTile(
                icon: Icons.speed_rounded,
                title: 'Buffer Profile',
                subtitle: _selectedBufferMode,
                onTap: () {
                  _showSingleChoiceDialog(
                    title: 'Select Buffer Profile',
                    options: _bufferModes,
                    currentValue: _selectedBufferMode,
                    onSelected: (val) => setState(() => _selectedBufferMode = val),
                  );
                },
              ),
              SettingTile(
                icon: Icons.aspect_ratio_rounded,
                title: 'Default Aspect Ratio',
                subtitle: _selectedAspectRatio,
                onTap: () {
                  _showSingleChoiceDialog(
                    title: 'Select Default Aspect Ratio',
                    options: _aspectRatios,
                    currentValue: _selectedAspectRatio,
                    onSelected: (val) => setState(() => _selectedAspectRatio = val),
                  );
                },
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

