import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:goplay/core/constants.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_player_settings_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Player Gesture Settings Tests', () {
    test('AppConstants contains correct gesture setting keys', () {
      expect(AppConstants.volumeBrightnessGesturesKey, 'volume_brightness_gestures_enabled');
      expect(AppConstants.extraBrightnessKey, 'extra_brightness_enabled');
      expect(AppConstants.doubleTapSeekKey, 'double_tap_seek_enabled');
    });

    test('Gesture settings persist and read correctly in Hive settings box', () async {
      final box = await Hive.openBox(AppConstants.settingsBox);

      // Defaults check before any write
      final defaultGestures = box.get(AppConstants.volumeBrightnessGesturesKey) as bool? ?? true;
      final defaultExtraBri = box.get(AppConstants.extraBrightnessKey) as bool? ?? false;
      final defaultDoubleTap = box.get(AppConstants.doubleTapSeekKey) as bool? ?? false;

      expect(defaultGestures, isTrue);
      expect(defaultExtraBri, isFalse);
      expect(defaultDoubleTap, isFalse);

      // Persist user-disabled gestures
      await box.put(AppConstants.volumeBrightnessGesturesKey, false);
      await box.put(AppConstants.extraBrightnessKey, true);
      await box.put(AppConstants.doubleTapSeekKey, true);

      expect(box.get(AppConstants.volumeBrightnessGesturesKey), isFalse);
      expect(box.get(AppConstants.extraBrightnessKey), isTrue);
      expect(box.get(AppConstants.doubleTapSeekKey), isTrue);
    });
  });
}
