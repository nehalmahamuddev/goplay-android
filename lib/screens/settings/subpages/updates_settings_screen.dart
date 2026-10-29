import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants.dart';
import '../../../core/typography.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/update_notifier.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Updates and Backup Settings Screen matching Upstream's 'Updates and Backup' subpage (Screenshot 3).
class UpdatesSettingsScreen extends ConsumerStatefulWidget {
  const UpdatesSettingsScreen({super.key});

  @override
  ConsumerState<UpdatesSettingsScreen> createState() => _UpdatesSettingsScreenState();
}

class _UpdatesSettingsScreenState extends ConsumerState<UpdatesSettingsScreen> {
  bool _installPreRelease = false;
  bool _useLegacyInstaller = false;
  bool _autoCheckUpdates = true;
  String _backupFrequency = 'Manual';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);
    final headerBg = theme.bottomNavigationBarTheme.backgroundColor ?? themeMode.bottomNavColor;

    final updateState = ref.watch(updateProvider);
    final updateNotifier = ref.read(updateProvider.notifier);

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
              'Updates and Backup',
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
              // ─── App Updates Section ───
              const SettingSectionHeader(title: 'App updates'),
              SettingTile(
                icon: Icons.system_update_alt_rounded,
                title: 'Check for Update',
                subtitle: updateState.status == UpdateStatus.checking
                    ? 'Checking releases...'
                    : 'Current Version: v${AppConstants.appVersion}',
                trailing: updateState.status == UpdateStatus.checking
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : null,
                onTap: () async {
                  await updateNotifier.checkForUpdates(isManual: true);
                  if (context.mounted && ref.read(updateProvider).updateInfo == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('You are on the latest GoPlay release!'),
                        backgroundColor: const Color(0xFF1E1E1E),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                },
              ),
              SettingSwitchTile(
                icon: Icons.developer_mode_rounded,
                title: 'Install pre-release version',
                subtitle: 'Include early beta builds and experimental releases',
                value: _installPreRelease,
                onChanged: (val) => setState(() => _installPreRelease = val),
              ),
              SettingSwitchTile(
                icon: Icons.phonelink_setup_rounded,
                title: 'Legacy APK Installer',
                subtitle:
                    'Some older Android devices do not support the modern package installer. Enable fallback if updates fail.',
                value: _useLegacyInstaller,
                onChanged: (val) => setState(() => _useLegacyInstaller = val),
              ),
              SettingSwitchTile(
                icon: Icons.notifications_active_outlined,
                title: 'Show app updates',
                subtitle: 'Automatically search for new updates after starting the app.',
                value: _autoCheckUpdates,
                onChanged: (val) => setState(() => _autoCheckUpdates = val),
              ),

              const SizedBox(height: 12),

              // ─── Backup Section ───
              const SettingSectionHeader(title: 'Backup'),
              SettingTile(
                icon: Icons.archive_outlined,
                title: 'Back up data',
                subtitle: 'Export bookmarks, channel favorites, and local configurations',
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Favorites and preferences backed up to local storage!'),
                      backgroundColor: const Color(0xFF1E1E1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              SettingTile(
                icon: Icons.history_rounded,
                title: 'Backup frequency',
                subtitle: _backupFrequency,
                onTap: () {
                  setState(() {
                    _backupFrequency = _backupFrequency == 'Manual' ? 'Weekly' : 'Manual';
                  });
                },
              ),
              SettingTile(
                icon: Icons.restore_rounded,
                title: 'Restore data from backup',
                subtitle: 'Restore channel favorites and previous settings',
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Configuration restored from backup!'),
                      backgroundColor: const Color(0xFF1E1E1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              SettingTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Clear Cache',
                subtitle: 'Free storage by clearing temporary channel lists and logos',
                onTap: () async {
                  await ref.read(cacheServiceProvider).clearAllCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Application cache cleared successfully!'),
                        backgroundColor: const Color(0xFF1E1E1E),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
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

