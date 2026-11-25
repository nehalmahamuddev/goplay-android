# Backdrop Liquid Glass Clean Card & IPTV Playlist Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the physics-based Liquid Glass aesthetic from Kyant's Backdrop library (`https://kyant.gitbook.io/backdrop`), creating a reusable `CleanCard` widget from scratch and overhauling the `IptvPlaylistCard` and channel card into pristine, modern liquid glass components.

**Architecture:** 
1. Build a core `CleanCard` / `BackdropCard` widget with custom `CleanLiquidGlassPainter` rendering multi-layer glass optics: directional specular rim gradient, optical caustic inner bevel, top-left specular gleam, Gaussian backdrop blur, and ambient/contact shadows.
2. Completely rebuild `IptvPlaylistCard` discarding the outdated decompiled APK layout, featuring radiant glass emblems, crisp typographic hierarchy, glass metadata chips (channel count, EPG status, source type), streamlined action buttons (browse, quick-sync, copy URL, menu), and sleek reordering/multi-select modes.
3. Provide Backdrop-styled enhancements to `ChannelCard` for full visual cohesion across the application.

**Tech Stack:** Flutter, Dart, Riverpod, Canvas `CustomPainter`, `ImageFilter.blur`, SVG icons.

**Spec:** Kyant's Backdrop library specifications (`https://kyant.gitbook.io/backdrop`) and modern liquid glass design standards.

## Global Constraints
- Must run cleanly on Flutter 3.29+ / Dart 3.7+ with zero compile or analysis errors.
- All SVG icons must use existing `IptvSvgIcon` / standard icons with zero missing asset warnings.
- Haptics and interactions must be smooth, non-blocking, and follow project theme conventions (`activeThemeModeProvider`, `activeAccentColorProvider`).
- No regression on existing playlist actions: browse channels, edit source, rename, export M3U, EPG manager, playlist info, and delete.

## Review Focus
1. Non-dark theme brightness: Ensure multi-stop specular highlights maintain high contrast and legibility in light mode.
2. Reorderable list interactions: Ensure dragging in reorderable mode doesn't conflict with tap-to-browse or action buttons.
3. Multi-select toggle responsiveness: Ensure selection checkboxes respond immediately with haptic feedback.
4. Long playlist names and overflowing URLs: Ellipsize gracefully without render overflow on narrow viewports (320px).
5. Background transparency: Backdrop blur must gracefully sample any underlying canvas, animated mesh, or solid surface.

---

### Task 1: Create Reusable `CleanCard` with Kyant Backdrop Liquid Glass Physics

**Files:**
- Create: `lib/widgets/cards/clean_card.dart`
- Test: `test/clean_card_test.dart`

**Interfaces:**
- Produces: `CleanCard`, `CleanLiquidGlassPainter`
- Consumes: `Theme.of(context)`, `ImageFilter.blur`

- [ ] **Step 1: Write widget test for `CleanCard`**
Create `test/clean_card_test.dart` asserting that `CleanCard` renders child content, executes `onTap`, renders `BackdropFilter`, and handles custom border/surface properties.

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/clean_card_test.dart`
Expected: FAIL (file does not exist)

- [ ] **Step 3: Implement `CleanCard` and `CleanLiquidGlassPainter` in `lib/widgets/cards/clean_card.dart`**
Implement:
- `CleanLiquidGlassPainter`:
  1. Outer rim gradient stroke (inside alignment) with diagonal light angle (72% -> 18% -> 35% white).
  2. Inner lens caustic refraction bevel (0.9px stroke simulating physical glass edge curvature).
  3. Specular peak radial glint at top-left corner (`dot(grad, normal)^falloff`).
  4. Subtle chromatic dispersion hint.
- `CleanCard`:
  - `BackdropFilter` with `sigmaX: 20`, `sigmaY: 20` (customizable).
  - Multi-stop translucent surface wash gradient (dark/light mode aware).
  - Ambient elevation shadow + tight contact shadow.
  - Interactive micro-scale feedback on press with haptics.
  - Optional header/footer slots or direct child rendering.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/clean_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/widgets/cards/clean_card.dart test/clean_card_test.dart
git commit -m "feat(ui): add reusable CleanCard with Kyant Backdrop liquid glass styling"
```

---

### Task 2: Redesign and Overhaul `IptvPlaylistCard` from Scratch

**Files:**
- Modify: `lib/screens/iptv/widgets/iptv_playlist_card.dart`
- Modify: `test/iptv_feature_test.dart`

**Interfaces:**
- Consumes: `IptvPlaylist`, `CleanCard` or `IptvLiquidGlassPainter`, `iptvPlaylistsProvider`, `IptvSvgIcon`
- Produces: `IptvPlaylistCard`

- [ ] **Step 1: Add widget tests in `test/iptv_feature_test.dart` for new `IptvPlaylistCard` visual elements**
Verify rendering of:
- Radiant glowing emblem with playlist initials
- Playlist title & source type badge
- Channel count chip & EPG badge
- Quick action buttons (Browse pill, Link copy, 3-dots popup menu)
- Multi-select checkbox and reorder handle

- [ ] **Step 2: Run test to verify current state**
Run: `flutter test test/iptv_feature_test.dart`

- [ ] **Step 3: Completely rebuild `IptvPlaylistCard` in `lib/screens/iptv/widgets/iptv_playlist_card.dart`**
Replace the old cramped APK layout with the new design:
1. Liquid Glass container using `BackdropFilter` and `IptvLiquidGlassPainter`.
2. Radiant avatar emblem:
   - Subtle outer glow matching the playlist accent color.
   - Glass pill or circle container with bold typography initials.
3. Clean content column:
   - Top row: Source type chip (e.g. `M3U LINK`, `XTREAM`, `LOCAL FILE`) + EPG indicator pill.
   - Middle row: Bold, modern playlist name.
   - Bottom row: Channel count with TV icon (`76 channels`), last synced relative timestamp (`Synced 2h ago` or formatted date), and masked stream domain.
4. Action area:
   - "Browse" quick action button with glass pill style.
   - Secondary icon buttons: Copy URL, Re-sync with haptic confirmation.
   - 3-dots overflow menu for advanced actions (Edit, Rename, Export M3U, EPG, Info, Delete).
5. Drag handle & selection support:
   - Smooth reorder grabber on the left when reorderable.
   - High-contrast liquid glass selection checkmark in multi-select mode.
6. Responsive grid card layout (`isGrid: true`):
   - Vertical proportional layout with top glowing avatar, centered title, bottom metadata and play action.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/iptv_feature_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/screens/iptv/widgets/iptv_playlist_card.dart test/iptv_feature_test.dart
git commit -m "feat(iptv): redesign IptvPlaylistCard with Kyant Backdrop liquid glass style"
```

---

### Task 3: Modernize `ChannelCard` with Backdrop Liquid Glass Styling

**Files:**
- Modify: `lib/widgets/cards/channel_card.dart`
- Test: `test/channels_screen_test.dart`

**Interfaces:**
- Consumes: `Channel`, `CleanLiquidGlassPainter`, `TvFocusable`
- Produces: `ChannelCard`

- [ ] **Step 1: Check existing `channels_screen_test.dart`**
Run: `flutter test test/channels_screen_test.dart`

- [ ] **Step 2: Update `ChannelCard` in `lib/widgets/cards/channel_card.dart`**
Enhance `ChannelCard` with optional or integrated liquid glass backdrop effects:
- Subtle backdrop blur and translucent glass gradient when over dynamic backgrounds.
- Refined refraction border and specular highlight.
- Smooth elevation shadow and glowing badge styling.

- [ ] **Step 3: Run test to verify it passes**
Run: `flutter test test/channels_screen_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**
```bash
git add lib/widgets/cards/channel_card.dart
git commit -m "feat(channels): add Kyant Backdrop liquid glass styling to ChannelCard"
```

---

### Task 4: Final Verification & Analyzer Check

**Files:**
- All touched files

- [ ] **Step 1: Run Flutter analyze to ensure zero warnings or errors**
Run: `flutter analyze`
Expected: 0 issues found

- [ ] **Step 2: Run all IPTV and channel tests**
Run: `flutter test test/iptv_feature_test.dart test/channels_screen_test.dart test/clean_card_test.dart`
Expected: All tests pass

- [ ] **Step 3: Final Git status check**
Verify working tree is clean.
