# Changelog

All notable changes to the GoPlay application will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.3.3] - 2026-10-30

### Added
- **Player Enhancements**:
  - Redesigned server selection modal into a compact, modern YouTube-style popup card.
  - Replaced top header server actions with streamlined bottom bar server button using `dns_rounded` icon.
  - Added fullscreen server switcher with touch screen lock mode and dynamic theme pill badges.
- **Update System**:
  - Direct GitHub Releases update system featuring web redirect fallback and startup checks.
  - 5-minute safety cooldown for update detection with session dismissal memory.
- **Home & Feed Interactions**:
  - Native pull-to-refresh with Android clamping physics and full data synchronization across home feeds.
  - Dynamic spacing collapse between search input and trending section.
- **Search & Filter Experience**:
  - Upstream-style `SearchPillCard` component for Categories and Channels headers.
  - Channels sorting and filtering bottom sheet with active indicators and responsive grid integration.
- **Community & Settings**:
  - Updated community links in Settings (replaced GitHub link with Facebook and updated official Telegram link).
  - Full Settings hub redesign matching Upstream UI standards with subpages for General, Player, Layout, and Accounts.

### Fixed
- **UI & Theming Polish**:
  - Cleaned up search text field borders across surfaces for a borderless aesthetic.
  - Adapted Settings search bar styling to dynamic theme colors.
  - Resolved text overflow in the Account Info bottom sheet sync status indicator.
  - Fixed mobile status bar visibility with seamless header background blending.
  - Removed borders and outlines across dialog surfaces and action buttons.
- **Build & Packaging**:
  - Configured Gradle to use release signing configuration for debug builds when a release keystore is present.

---

## [2.3.2] - 2026-10-30

### Fixed
- **Categories Active Filter**:
  - Filter categories and channel list strictly by active status.
  - Automatically reset selected category state if deactivated from remote database.
  - Fallback to local cached channels when direct stream fetch is empty.

---

## [2.3.1] - 2026-10-30

### Fixed
- **In-App Updater Auto-Check**:
  - Replaced the 6-hour delay with a 5-minute safety cooldown to detect releases immediately on app launch.
  - Added smooth transition settle delay when displaying the update dialog after navigating away from splash.
  - Implemented session dismissal state for optional updates so users aren't repeatedly interrupted.
  - Linked the "Show app updates" toggle in Settings to persistent storage.

### Changed
- **Update Dialog Theme Integration**:
  - Adapted dialog background to active `AppThemeMode.cardColor` across AMOLED, Cyber Lime, Dracula, and Dark modes.
  - Applied dynamic accent colors (`colorScheme.primary` and `colorScheme.onPrimary`) to the icon badge, headers, progress bars, and buttons.
  - Removed all borders and outline strokes across card surfaces and buttons for a borderless aesthetic.

---

## [2.3.0] - 2026-10-30

### Added
- **Player Enhancements**:
  - Fullscreen stream server switcher bottom sheet with fast multi-source switching.
  - Screen touch lock mode with auto-dimming unlock pill button for uninterrupted viewing.
  - Dynamic theme-aware server pill badges and active playback indicators.
- **Search & Navigation**:
  - Upstream-style `SearchPillCard` integrated across Categories, Channels, and Events headers.
  - Category and channel filters sheet with instant alphabetical, favorite, and channel-count sorting.
- **UI Architecture & Theming**:
  - Comprehensive Settings hub redesign with 6 dedicated subpages (General, Player, Layout, Updates, Sync, Accounts).
  - Openstream pure black AMOLED (`#000000`) and refined Dark (`#111111`) palettes with borderless `#161616` container cards.
  - Unified collapsing header delegate with edge-to-edge system status bar spacing and smooth fade transitions.
  - Modularized `HomeScreen` architecture with responsive sections and dynamic spacing.

### Fixed
- Pinned status bar spacing on Events and Categories headers during scroll collapse.
- Top status bar overlapping issues on devices with camera cutouts and notches.
- Offline service fallbacks and local cache resilience for channel streams.
- Card and component border bleeds in favor of clean borderless surfaces.

---

## [2.2.2] - 2026-10-29

### Added
- In-app auto-updater powered by GitHub Releases API with automated background checks.
- Direct APK download and installation manager with progress tracking.
- TV remote D-Pad navigation focus wrappers across all major interactive cards.

### Fixed
- Stream stability improvements and playback reconnect handling.
- Event card timestamp alignment and UTC/GMT lifecycle evaluation.

---

## [2.2.1] - 2026-10-25

### Added
- New Categories screen with categorized live streams.
- Sport category filter chips on the Home screen.
- Real-time live match indicator badge and countdown timer.
