/// App-wide constants and configuration
class AppConstants {
  AppConstants._();

  // Supabase
  static const String supabaseUrl = 'https://hqmhuvsjlykrdusfkmeg.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxbWh1dnNqbHlrcmR1c2ZrbWVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4MjI3OTEsImV4cCI6MjA5ODM5ODc5MX0.sfNEW7QG0idyVVRHlDtYjITDfIbsFQQm2u9a3ffoNoA';

  // Hive Box Names
  static const String channelsBox = 'channels_cache';
  static const String eventsBox = 'events_cache';
  static const String categoriesBox = 'categories_cache';
  static const String settingsBox = 'settings';
  static const String watchHistoryBox = 'watch_history_local';
  static const String favoritesBox = 'favorites_local';
  static const String announcementsBox = 'announcements_cache';
  static const String heroBannersBox = 'hero_banners_cache';

  // Player Gesture Settings Keys
  static const String volumeBrightnessGesturesKey = 'volume_brightness_gestures_enabled';
  static const String extraBrightnessKey = 'extra_brightness_enabled';
  static const String doubleTapSeekKey = 'double_tap_seek_enabled';

  // Player Buffering & Layout Settings Keys
  static const String defaultVideoQualityKey = 'default_video_quality';
  static const String defaultBufferModeKey = 'default_buffer_mode';
  static const String defaultAspectRatioKey = 'default_aspect_ratio';

  // Navigation & Startup Settings Keys
  static const String customNavTabsKey = 'custom_nav_tabs';
  static const String defaultLaunchPageKey = 'default_launch_page';
  static const String lastActiveNavTabKey = 'last_active_nav_tab';

  // App Info
  static const String appName = 'GoPlay';
  static const String appVersion = '2.4.1';
  
  // Community & Social Links
  static const String telegramCommunityUrl = 'https://t.me/goplaycommunity';
  static const String facebookCommunityUrl =
      'https://www.facebook.com/people/GoPlay/61591500824688/';
  static const String discordCommunityUrl = 'https://discord.gg/goplay';

  // Updates (Direct from GitHub Releases)
  static const String githubOwner = 'nehalmahamuddev';
  static const String githubRepo = 'goplay-android';
  static const String githubLatestReleaseUrl =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
  static const String githubLatestWebReleaseUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';
}

