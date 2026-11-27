import '../../core/constants.dart';
import '../../models/nav_destination.dart';

/// Persistence seam for local user preferences (favorites, layout flags, tabs).
///
/// Kept separate from [CatalogStore] so user customizations are never wiped
/// when cached server catalog data is cleared.
abstract interface class PreferencesStore {
  Set<String> getFavoriteChannelIds();
  Future<void> saveFavoriteChannelIds(Set<String> ids);

  bool getShowTrendingTabUserPref();
  Future<void> saveShowTrendingTabUserPref(bool enabled);

  bool getShowLiveTabCounterUserPref();
  Future<void> saveShowLiveTabCounterUserPref(bool enabled);

  bool getShowSportCategoryIconsUserPref();
  Future<void> saveShowSportCategoryIconsUserPref(bool enabled);

  List<String> getCustomNavTabsUserPref();
  Future<void> saveCustomNavTabsUserPref(List<String> tabs);

  String getDefaultLaunchPageUserPref();
  Future<void> saveDefaultLaunchPageUserPref(String page);

  String getLastActiveNavTabUserPref();
  Future<void> saveLastActiveNavTabUserPref(String tab);
}

/// Pure in-memory [PreferencesStore] implementation for headless tests.
class InMemoryPreferencesStore implements PreferencesStore {
  Set<String> _favoriteChannelIds = const {};
  bool _showTrendingTab = true;
  bool _showLiveTabCounter = false;
  bool _showSportCategoryIcons = true;
  List<String> _customNavTabs = List<String>.from(NavDestination.defaultTabIds);
  String _defaultLaunchPage = 'home';
  String _lastActiveNavTab = 'home';

  @override
  Set<String> getFavoriteChannelIds() => _favoriteChannelIds;

  @override
  Future<void> saveFavoriteChannelIds(Set<String> ids) async {
    _favoriteChannelIds = Set<String>.unmodifiable(ids);
  }

  @override
  bool getShowTrendingTabUserPref() => _showTrendingTab;

  @override
  Future<void> saveShowTrendingTabUserPref(bool enabled) async {
    _showTrendingTab = enabled;
  }

  @override
  bool getShowLiveTabCounterUserPref() => _showLiveTabCounter;

  @override
  Future<void> saveShowLiveTabCounterUserPref(bool enabled) async {
    _showLiveTabCounter = enabled;
  }

  @override
  bool getShowSportCategoryIconsUserPref() => _showSportCategoryIcons;

  @override
  Future<void> saveShowSportCategoryIconsUserPref(bool enabled) async {
    _showSportCategoryIcons = enabled;
  }

  @override
  List<String> getCustomNavTabsUserPref() => List<String>.from(_customNavTabs);

  @override
  Future<void> saveCustomNavTabsUserPref(List<String> tabs) async {
    final valid = tabs
        .where((id) => NavDestination.values.any((d) => d.id == id))
        .toList(growable: false);
    if (valid.length >= 3 && valid.length <= 5) {
      _customNavTabs = valid;
    }
  }

  @override
  String getDefaultLaunchPageUserPref() =>
      _defaultLaunchPage.isNotEmpty ? _defaultLaunchPage : 'home';

  @override
  Future<void> saveDefaultLaunchPageUserPref(String page) async {
    _defaultLaunchPage = page.isNotEmpty ? page : 'home';
  }

  @override
  String getLastActiveNavTabUserPref() =>
      _lastActiveNavTab.isNotEmpty ? _lastActiveNavTab : 'home';

  @override
  Future<void> saveLastActiveNavTabUserPref(String tab) async {
    if (tab.isEmpty) return;
    _lastActiveNavTab = tab;
    // Reference constant so key contract stays imported cleanly.
    assert(AppConstants.lastActiveNavTabKey.isNotEmpty);
  }
}
