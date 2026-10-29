import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Data and Cloud Sync Settings Screen matching Upstream's clean subpage layout.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  bool _isSyncing = false;
  String _syncRate = '6 Hours';
  final List<String> _syncRates = ['1 Hour', '6 Hours', 'Manual'];

  Future<void> _handleForceSync() async {
    setState(() => _isSyncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncServiceProvider).sync();
      ref.invalidate(channelsProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(categoriesProvider);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Channels and live events synced successfully!'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
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
              'Data & Cloud Sync',
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
              // ─── Sync Section ───
              const SettingSectionHeader(title: 'Cloud Synchronization'),
              SettingTile(
                icon: Icons.sync_rounded,
                title: 'Force Sync Now',
                subtitle: _isSyncing
                    ? 'Synchronizing channels and live broadcasts...'
                    : 'Download latest channels and match fixtures from database',
                trailing: _isSyncing
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      )
                    : null,
                onTap: _isSyncing ? null : _handleForceSync,
              ),
              SettingTile(
                icon: Icons.timer_outlined,
                title: 'Background Sync Rate',
                subtitle: _syncRate,
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF161616),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0x1AFFFFFF), width: 1),
                      ),
                      title: Text(
                        'Background Sync Rate',
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _syncRates.map((rate) {
                          return ListTile(
                            title: Text(rate, style: TextStyle(color: cs.onSurface)),
                            trailing: rate == _syncRate
                                ? Icon(Icons.check, color: cs.primary)
                                : null,
                            onTap: () {
                              setState(() => _syncRate = rate);
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // ─── Storage Section ───
              const SettingSectionHeader(title: 'Storage & UI State'),
              SettingTile(
                icon: Icons.delete_outline_rounded,
                title: 'Clear Cache',
                subtitle: 'Purge locally cached playlists, channel icons, and logos',
                onTap: () async {
                  await ref.read(cacheServiceProvider).clearAllCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Local application cache cleared!'),
                        backgroundColor: const Color(0xFF1E1E1E),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                },
              ),
              SettingTile(
                icon: Icons.restart_alt_rounded,
                title: 'Reset UI to Defaults',
                subtitle: 'Reset cached styling, tab layout, and theme colors',
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF161616),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: const Text('Reset UI to Defaults?', style: TextStyle(color: Colors.white)),
                      content: const Text(
                        'This will reset your local cached colors and layout back to default Upstream styling.',
                        style: TextStyle(color: Color(0xFFA0A0A0)),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel', style: TextStyle(color: Color(0xFFA0A0A0))),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await ref.read(cacheServiceProvider).resetLocalUiConfigToDefaults();
                    ref.invalidate(uiConfigProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('UI reset to defaults!'),
                          backgroundColor: const Color(0xFF1E1E1E),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  }
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

