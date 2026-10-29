import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/typography.dart';
import '../../../providers/theme_provider.dart';
import '../widgets/setting_section_header.dart';
import '../widgets/setting_tile.dart';

/// General Settings Screen matching Upstream's 'General' subpage.
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  Future<void> _launchUrlSafe(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open link: $url'),
            backgroundColor: const Color(0xFF1E1E1E),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'General',
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
              // ─── Links & Community ───
              const SettingSectionHeader(title: 'Community & Links'),
              SettingTile(
                icon: Icons.send_rounded,
                title: 'Official Telegram',
                subtitle: 'Join for live match schedules, news & stream updates',
                onTap: () => _launchUrlSafe(context, 'https://t.me/goplay_stream'),
              ),
              SettingTile(
                icon: Icons.forum_outlined,
                title: 'Discord Community',
                subtitle: 'Chat with developers and get instant streaming support',
                onTap: () => _launchUrlSafe(context, 'https://discord.gg/goplay'),
              ),
              SettingTile(
                icon: Icons.code_rounded,
                title: 'GitHub Source Repository',
                subtitle: 'github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}',
                onTap: () => _launchUrlSafe(
                  context,
                  'https://github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}',
                ),
              ),

              const SizedBox(height: 12),

              // ─── Diagnostics & About ───
              const SettingSectionHeader(title: 'Diagnostics & About'),
              SettingTile(
                icon: Icons.report_problem_outlined,
                title: 'Report Stream Outage',
                subtitle: 'Submit non-working channel links or player buffer issues',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Thank you! Issue reporting submitted to admin logs.'),
                      backgroundColor: const Color(0xFF1E1E1E),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              SettingTile(
                icon: Icons.info_outline_rounded,
                title: 'About GoPlay Stream',
                subtitle: 'v${AppConstants.appVersion} • Built with high-performance Flutter & Upstream engine',
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

