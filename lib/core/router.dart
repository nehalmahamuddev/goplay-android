import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_providers.dart';
import '../services/analytics_service.dart';
import '../services/playback/playback_session.dart';
import '../screens/shell_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/channels/channels_screen.dart';
import '../screens/upcoming/upcoming_screen.dart';
import '../screens/player/player_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/subpages/layout_settings_screen.dart';
import '../screens/settings/subpages/player_settings_screen.dart';
import '../screens/settings/subpages/updates_settings_screen.dart';
import '../screens/settings/subpages/sync_settings_screen.dart';
import '../screens/settings/subpages/general_settings_screen.dart';
import '../screens/settings/subpages/account_settings_screen.dart';
import '../screens/settings/subpages/navigation_tabs_settings_screen.dart';
import '../screens/settings/subpages/primary_color_settings_screen.dart';
import '../screens/settings/subpages/app_theme_settings_screen.dart';
import '../screens/settings/subpages/launch_screen_settings_screen.dart';
import '../screens/settings/subpages/iptv_settings_screen.dart';
import '../screens/iptv/iptv_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

class _SafeFirebaseScreenObserver extends NavigatorObserver {
  final AnalyticsService? _analytics;

  _SafeFirebaseScreenObserver({AnalyticsService? analytics}) : _analytics = analytics;

  void _track(Route<dynamic>? route) {
    if (route == null) return;
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    _analytics?.trackScreenView(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final analytics = ref.read(analyticsServiceProvider);
  return createAppRouter(analyticsService: analytics);
});

GoRouter createAppRouter({AnalyticsService? analyticsService}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  observers: [_SafeFirebaseScreenObserver(analytics: analyticsService)],
  routes: [
    GoRoute(
      path: '/',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ShellScreen(navigationShell: navigationShell);
      },
      // No navigatorContainerBuilder on purpose: go_router's default container
      // already wraps each branch in Offstage + TickerMode(enabled: isActive),
      // so off-screen branches are painted-out and ticker-muted for free.
      // Overriding it means reimplementing both, and losing either one silently
      // regresses battery use.
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/categories',
              name: 'categories',
              builder: (context, state) => const CategoriesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/channels',
              name: 'channels',
              builder: (context, state) => const ChannelsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/upcoming',
              name: 'upcoming',
              builder: (context, state) => const UpcomingScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsScreen(isShellTab: true),
              routes: [
                GoRoute(
                  path: 'general',
                  name: 'settings_general',
                  builder: (context, state) => const GeneralSettingsScreen(),
                ),
                GoRoute(
                  path: 'player',
                  name: 'settings_player',
                  builder: (context, state) => const PlayerSettingsScreen(),
                ),
                GoRoute(
                  path: 'layout',
                  name: 'settings_layout',
                  builder: (context, state) => const LayoutSettingsScreen(),
                  routes: [
                    GoRoute(
                      path: 'navigation',
                      name: 'settings_layout_navigation',
                      builder: (context, state) => const NavigationTabsSettingsScreen(),
                    ),
                    GoRoute(
                      path: 'primary-color',
                      name: 'settings_layout_primary_color',
                      builder: (context, state) => const PrimaryColorSettingsScreen(),
                    ),
                    GoRoute(
                      path: 'app-theme',
                      name: 'settings_layout_app_theme',
                      builder: (context, state) => const AppThemeSettingsScreen(),
                    ),
                    GoRoute(
                      path: 'launch-screen',
                      name: 'settings_layout_launch_screen',
                      builder: (context, state) => const LaunchScreenSettingsScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'updates',
                  name: 'settings_updates',
                  builder: (context, state) => const UpdatesSettingsScreen(),
                ),
                GoRoute(
                  path: 'sync',
                  name: 'settings_sync',
                  builder: (context, state) => const SyncSettingsScreen(),
                ),
                GoRoute(
                  path: 'account',
                  name: 'settings_account',
                  builder: (context, state) => const AccountSettingsScreen(),
                ),
                GoRoute(
                  path: 'iptv',
                  name: 'settings_iptv',
                  builder: (context, state) => const IptvSettingsScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/iptv',
              name: 'iptv',
              builder: (context, state) => const IptvScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/player/:channelId',
      name: 'player',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final rawId = state.pathParameters['channelId'] ?? '';
        final channelId = Uri.decodeComponent(rawId);
        final args = PlaybackLaunchArgs.fromExtra(state.extra, channelId);

        return PlayerScreen(
          channelId: args.channelId,
          eventChannels: args.eventChannels,
          dynamicChannels: args.dynamicChannels,
          sportEvent: args.sportEvent,
          forceFullscreen: args.forceFullscreen,
        );
      },
    ),
    GoRoute(
      path: '/search',
      name: 'search',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SearchScreen(),
    ),
  ],
);
