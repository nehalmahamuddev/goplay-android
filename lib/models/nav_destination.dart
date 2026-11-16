import 'package:flutter/material.dart';

/// Available primary navigation destinations for GoPlay.
enum NavDestination {
  home(
    id: 'home',
    label: 'Home',
    svgAsset: 'assets/images/home.svg',
    selectedSvgAsset: 'assets/images/home_filled.svg',
    branchIndex: 0,
    route: '/home',
  ),
  categories(
    id: 'categories',
    label: 'Categories',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
    branchIndex: 1,
    route: '/categories',
  ),
  channels(
    id: 'channels',
    label: 'Channels',
    svgAsset: 'assets/images/channels.svg',
    selectedSvgAsset: 'assets/images/channels_filled.svg',
    branchIndex: 2,
    route: '/channels',
  ),
  favorites(
    id: 'favorites',
    label: 'Favorites',
    icon: Icons.favorite_outline_rounded,
    selectedIcon: Icons.favorite_rounded,
    branchIndex: 2,
    route: '/channels',
  ),
  events(
    id: 'events',
    label: 'Events',
    svgAsset: 'assets/images/events.svg',
    selectedSvgAsset: 'assets/images/events_filled.svg',
    branchIndex: 3,
    route: '/upcoming',
  ),
  settings(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    branchIndex: 4,
    route: '/settings',
  );

  final String id;
  final String label;
  final IconData? icon;
  final IconData? selectedIcon;
  final String? svgAsset;
  final String? selectedSvgAsset;
  final int branchIndex;
  final String route;

  const NavDestination({
    required this.id,
    required this.label,
    this.icon,
    this.selectedIcon,
    this.svgAsset,
    this.selectedSvgAsset,
    required this.branchIndex,
    required this.route,
  });

  static NavDestination fromId(String id) {
    return NavDestination.values.firstWhere(
      (d) => d.id == id,
      orElse: () => NavDestination.home,
    );
  }

  static const List<NavDestination> defaultTabs = [
    NavDestination.home,
    NavDestination.categories,
    NavDestination.channels,
    NavDestination.events,
  ];

  static const List<String> defaultTabIds = [
    'home',
    'categories',
    'channels',
    'events',
  ];
}
