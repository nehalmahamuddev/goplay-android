# Player Volume & Brightness Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul GoPlay's video player volume and brightness controls inspired by CloudStream: direct Android system stream volume manipulation, 200% audio boost via `LoudnessEnhancer`, real-time screen brightness sync with minimum clamp `0.004f`, 200% Extra Brightness filter overlay, "slide up again" safety threshold, fullscreen hardware volume button interception, dual-stage visual OSDs, and user settings toggles to enable/disable gestures and extra brightness.

**Architecture:** 
- **Native Android (`NativePlayerView.kt` & `MainActivity.kt`)**: Implements `AudioManager.STREAM_MUSIC` control, audio session `LoudnessEnhancer` gain calculation for 101%–200%, window brightness adjustment with `0.004f` threshold, initial volume & brightness retrieval, and fullscreen hardware volume key interception.
- **Flutter Player (`channel_video_player_stub.dart`)**: Coordinates swipe gesture detection in fullscreen, dual-stage swipe limits with "slide up again to exceed 100%" safety lock, Extra Brightness video overlay filter, MethodChannel calls, and renders responsive dual-stage vertical OSD widgets. Respects the "Swipe for Volume & Brightness" user setting.
- **Settings & Persistence (`player_settings_screen.dart`)**: Adds a "Gestures & Controls" section in Player Settings with toggles for "Swipe for Volume & Brightness" (default: true) and "Extra Brightness" (default: false), persisted in Hive `settingsBox`.

**Tech Stack:** Flutter, Dart, Kotlin, Android Media3 / ExoPlayer, `android.media.AudioManager`, `android.media.audiofx.LoudnessEnhancer`, Hive.

---

## Global Constraints
- Target platform: Android mobile devices (phone & tablet).
- TV Leanback mode: Volume buttons & swipe gestures remain bypassed/handled by TV remote and TV system UI.
- Volume boost safety: Must NOT jump straight past 100% on a single swipe starting below 1.0; user must release and swipe up again to enter 101%–200%.
- Minimum brightness floor: `0.004f` to prevent OEM Android display manager auto-override bugs.
- Gesture toggle: When "Swipe for Volume & Brightness" is disabled, vertical swipes are completely ignored (no-op), while single tap, double tap, and hardware volume keys remain fully functional.

---

## Review Focus
1. **LoudnessEnhancer lifecycle**: Ensure `LoudnessEnhancer` is released safely when volume drops <= 1.0 or when player is paused/disposed/navigated away to prevent audio memory leaks or device audio server crashes.
2. **Hardware volume key suppression**: Ensure `KEYCODE_VOLUME_UP` and `KEYCODE_VOLUME_DOWN` are only intercepted when player is active and fullscreen on non-TV devices; otherwise, pass through to default OS handling.
3. **Brightness sync on player open**: Avoid the sudden jump to 50% brightness by querying the actual device window/system brightness when the player is initialized.
4. **Extra Brightness visual fidelity**: The white overlay must sit directly above the video and below the UI controls, with pointer events ignored (`IgnorePointer`).
5. **State recovery on orientation/PiP switch**: When exiting PiP or rotating screen, brightness and volume states must remain stable and consistent.
6. **Gesture disable check**: Verify that toggling off "Swipe for Volume & Brightness" immediately disables vertical drag detection in the player without requiring an app restart.

---

### Task 1: Native Android Volume Engine & LoudnessEnhancer Boost
**Files:**
- Modify: `android/app/src/main/kotlin/com/goplay/goplay/NativePlayerView.kt`
- Test: Verify MethodChannel methods `setVolume`, `getInitialState` via native logging and test invocation.

- [ ] **Step 1: Add AudioManager and LoudnessEnhancer management in `NativePlayerView.kt`**
  - Obtain `AudioManager` from `Context.AUDIO_SERVICE`.
  - Maintain `currentRequestedVolume: Float` and `loudnessEnhancer: LoudnessEnhancer?`.
  - Implement volume adjustment:
    - For values 0.0 to 1.0: map to `audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, step, 0)`.
    - For values 1.0 to 2.0: clamp stream volume to max step, and calculate boost gain: `((volume - 1.0f) * 1000).toInt()`.
    - Attach or update `LoudnessEnhancer(exoPlayer.audioSessionId)` with target gain and enabled state.
    - If volume drops <= 1.0, release and nullify `loudnessEnhancer`.
  - Clean up `loudnessEnhancer` in `dispose()`.

- [ ] **Step 2: Implement initial state query via MethodChannel**
  - In `onMethodCall`, add handler for `"getInitialState"`:
    - Query current stream volume ratio `curVolume = curStep.toFloat() / maxStep.toFloat()`.
    - Query current window brightness `curBrightness` (falling back to `Settings.System.SCREEN_BRIGHTNESS` or `0.5f`).
    - Return `mapOf("volume" to curVolume, "brightness" to curBrightness)`.
  - Update `setBrightness` to clamp between `0.004f` and `1.0f`.

---

### Task 2: Fullscreen Hardware Volume Key Interception
**Files:**
- Modify: `android/app/src/main/kotlin/com/goplay/goplay/MainActivity.kt`
- Modify: `android/app/src/main/kotlin/com/goplay/goplay/NativePlayerView.kt`
- Test: Run on Android device/emulator, toggle fullscreen, press Volume Up/Down, verify custom volume event triggers and system dialog is suppressed.

- [ ] **Step 1: Add fullscreen player state tracking in `MainActivity.kt`**
  - Add `isPlayerFullscreen: Boolean = false` in `MainActivity`.
  - Expose MethodChannel handler `"setPlayerFullscreen"` on `com.goplay/pip` or player channel so Flutter tells MainActivity when player is in fullscreen mode.

- [ ] **Step 2: Override `onKeyDown` in `MainActivity.kt`**
  - If `isPlayerFullscreen && !isTvDevice()`:
    - When `keyCode == KeyEvent.KEYCODE_VOLUME_UP` or `KeyEvent.KEYCODE_VOLUME_DOWN`:
      - Calculate delta: `+0.05f` for UP, `-0.05f` for DOWN.
      - Dispatch event to Flutter/Native player channel (`"onVolumeKeyDelta"`).
      - Return `true` to consume the key event and suppress Android OS volume slider.
  - Otherwise, return `super.onKeyDown(keyCode, event)`.

---

### Task 3: Flutter Extra Brightness Overlay & Gestures Overhaul
**Files:**
- Modify: `lib/widgets/player/channel_video_player_stub.dart`
- Modify: `lib/widgets/player/channel_video_player.dart`
- Test: Widget tests and device verification of swipe gesture physics.

- [ ] **Step 1: Wire initial state fetching and hardware volume listeners**
  - On `_methodChannel` established, call `"getInitialState"`:
    - Set `_volume = initialVolume.clamp(0.0, 1.0)`.
    - Set `_brightness = initialBrightness.clamp(0.01, 1.0)`.
  - Listen for `"onVolumeKeyDelta"` method call from native:
    - Increment/decrement `_volume` by delta.
    - Check safety threshold or allow boost.
    - Invoke `setVolume` on native player.
    - Update `_volumeOsdNotifier` and trigger auto-hide timer.

- [ ] **Step 2: Respect "Swipe for Volume & Brightness" setting and "Slide Up Again" safety threshold**
  - Read `swipeGesturesEnabled` preference from Hive `settingsBox` (key: `AppConstants.volumeBrightnessGesturesKey`, default `true`).
  - In `_handlePanUpdate`:
    - If `!swipeGesturesEnabled`: do not enter `_DragType.brightness` or `_DragType.volume`; ignore vertical drag.
    - If enabled:
      - Track `_isVolumeLocked` (true if drag started when `_volume < 1.0`).
      - Track `_isBrightnessLocked` (true if drag started when `_brightness < 1.0`).
      - For Volume: clamp to `1.0` if `_isVolumeLocked`, and show "Slide up again to exceed 100%" hint if user continues dragging up. If `!_isVolumeLocked`, allow dragging up to `2.0` (200%).
      - For Brightness: check if `extraBrightnessEnabled` is true in settings. If enabled and `!_isBrightnessLocked`, allow dragging up to `2.0` (200%).

- [ ] **Step 3: Implement Extra Brightness Overlay Widget**
  - Read `extraBrightnessEnabled` preference from Hive `settingsBox`.
  - Add an `IgnorePointer` white overlay container over the video player view in the stack:
    - Color: `Colors.white`.
    - Opacity: `(_brightness > 1.0 && extraBrightnessEnabled) ? (_brightness - 1.0).clamp(0.0, 0.45) : 0.0`.

---

### Task 4: Dual-Stage Vertical OSD Design & Animation
**Files:**
- Modify: `lib/widgets/player/channel_video_player_stub.dart` (`_BrightnessOsd`, `_VolumeOsd`)
- Test: Visual verification of Level 1 (white 0–100%) and Level 2 (amber/orange 101–200%) bars.

- [ ] **Step 1: Build dual-stage vertical progress bar for `_VolumeOsd`**
  - Height: 110dp, Width: 6dp.
  - Level 1 bar (0–100%): White fill.
  - Level 2 bar (101–200%): Stacked vibrant amber/orange fill (`Color(0xFFFFA726)`).
  - Dynamic Volume icons:
    - `0%`: `Icons.volume_off_rounded`
    - `1–49%`: `Icons.volume_down_rounded`
    - `50–100%`: `Icons.volume_up_rounded`
    - `101–200%`: `Icons.volume_up_rounded` with amber boost glow/badge.
  - Text label: Display percentage (e.g., `120%`, `150%`, `200%`).
  - "Slide up again to exceed 100%" pill hint when clamped at 100%.

- [ ] **Step 2: Build dual-stage vertical progress bar for `_BrightnessOsd`**
  - Height: 110dp, Width: 6dp.
  - Level 1 bar (0–100%): White fill.
  - Level 2 bar (101–200%): Amber/orange fill for extra brightness.
  - Multi-stage sun icons:
    - `< 30%`: `Icons.brightness_3_rounded` (night/dim)
    - `30–60%`: `Icons.wb_sunny_outlined`
    - `61–100%`: `Icons.wb_sunny_rounded`
    - `101–200%`: `Icons.wb_sunny_rounded` with warm amber tint.
  - Text label: Display percentage (e.g. `100%`, `150%`).

---

### Task 5: Player Settings Screen & Hive Configuration
**Files:**
- Modify: `lib/screens/settings/subpages/player_settings_screen.dart`
- Modify: `lib/core/constants.dart`
- Test: Verify toggles persist in Hive and update player behavior in real-time.

- [ ] **Step 1: Add setting keys in `AppConstants`**
  - Define `static const String volumeBrightnessGesturesKey = 'volume_brightness_gestures_enabled';`.
  - Define `static const String extraBrightnessKey = 'extra_brightness_enabled';`.

- [ ] **Step 2: Add "Gestures & Controls" section in `PlayerSettingsScreen`**
  - Add section header: "Gestures & Controls".
  - Add switch tile: **"Swipe for Volume & Brightness"** (Default: `true`, Subtitle: "Slide up/down on screen edges in fullscreen to adjust volume and brightness").
  - Add switch tile: **"Extra Brightness"** (Default: `false`, Subtitle: "Allows brightening the screen beyond 100% with a display filter").
  - Both wired directly to Hive `settingsBox`.
