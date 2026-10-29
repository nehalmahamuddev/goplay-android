import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/typography.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// Accounts and Security Settings Screen matching Upstream's 'Accounts and Security' subpage.
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  bool _anonymousTelemetry = false;

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
              'Accounts and Security',
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
              // ─── Profile Section ───
              const SettingSectionHeader(title: 'Active Account'),
              SettingTile(
                icon: Icons.account_circle_outlined,
                title: 'Default Profile',
                subtitle: 'Tap to switch profile or edit local identifier',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Default profile is active.'),
                      backgroundColor: const Color(0xFF1E1E1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),

              const SizedBox(height: 12),

              // ─── Device & Security Section ───
              const SettingSectionHeader(title: 'Device & Security'),
              SettingTile(
                icon: Icons.fingerprint_rounded,
                title: 'Client Device ID',
                subtitle: 'Unique installation footprint for Supabase live syncing',
                trailing: Icon(Icons.copy_rounded, size: 18, color: cs.onSurfaceVariant),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'goplay-device-client-id'));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Device ID copied to clipboard!'),
                      backgroundColor: const Color(0xFF1E1E1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              SettingSwitchTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Anonymous Error Telemetry',
                subtitle: 'Send non-identifying crash logs to assist maintainers',
                value: _anonymousTelemetry,
                onChanged: (val) => setState(() => _anonymousTelemetry = val),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

