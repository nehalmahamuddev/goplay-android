import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/nav_destination.dart';
import '../providers/app_providers.dart';

/// Shared navigation-selection invariant for ShellScreen rail and MainBottomNavBar.
bool isNavDestinationSelected(
  NavDestination destination, {
  required int currentIndex,
  required String selectedCategory,
  required bool hasFavoritesTab,
}) {
  if (destination == NavDestination.favorites) {
    return currentIndex == 2 && selectedCategory == 'favorite';
  }
  if (destination == NavDestination.channels) {
    if (hasFavoritesTab) {
      return currentIndex == 2 && selectedCategory != 'favorite';
    }
    return currentIndex == 2;
  }
  return currentIndex == destination.branchIndex;
}

/// Synchronizes [selectedCategoryProvider], [lastActiveNavTabProvider], and
/// screen telemetry whenever navigating to a top-level [NavDestination].
void applyDestinationState(WidgetRef ref, NavDestination dest) {
  if (dest == NavDestination.favorites) {
    ref.read(selectedCategoryProvider.notifier).select('favorite');
  } else if (dest == NavDestination.channels) {
    if (ref.read(selectedCategoryProvider) == 'favorite') {
      ref.read(selectedCategoryProvider.notifier).select('all');
    }
  }
  ref.read(lastActiveNavTabProvider.notifier).setActiveTab(dest.id);
  ref.read(analyticsServiceProvider).trackScreenView(dest.id);
}

/// Canonical top-level navigation coordinator eliminating per-caller drift.
void navigateToDestination(
  BuildContext context,
  WidgetRef ref,
  NavDestination dest,
) {
  applyDestinationState(ref, dest);
  context.go(dest.route);
}
