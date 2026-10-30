import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/models/app_theme_options.dart';
import 'package:goplay/models/update_info.dart';
import 'package:goplay/providers/theme_provider.dart';
import 'package:goplay/providers/update_notifier.dart';
import 'package:goplay/widgets/update_dialog.dart';

void main() {
  testWidgets('UpdateDialog adapts to active theme mode and accent color with zero borders', (tester) async {
    final cyberLimeTheme = AppThemeMode.cyberLime;
    final limeAccent = AppAccentColor.lime;

    final fakeUpdateState = UpdateState(
      status: UpdateStatus.updateAvailable,
      currentVersion: '2.3.0',
      updateInfo: UpdateInfo(
        latestVersion: '2.4.0',
        minimumVersion: '1.0.0',
        forceUpdate: false,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: ['Great new features', 'Performance boosts'],
        publishedAt: DateTime(2026, 10, 30),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeSettingsProvider.overrideWith(
            () => _FakeThemeSettingsNotifier(
              ThemeSettingsState(
                themeMode: cyberLimeTheme,
                accentColor: limeAccent,
                isUsingCustomTheme: true,
              ),
            ),
          ),
          updateProvider.overrideWith(
            () => _FakeUpdateNotifier(fakeUpdateState),
          ),
        ],
        child: MaterialApp(
          theme: cyberLimeTheme.toThemeData(limeAccent),
          home: const Scaffold(
            body: UpdateDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Dialog card container uses cyberLime cardColor and has NO borders
    final containerFinder = find.byType(Container).first;
    final container = tester.widget<Container>(containerFinder);
    final boxDecoration = container.decoration as BoxDecoration;

    expect(boxDecoration.color, equals(cyberLimeTheme.cardColor));
    expect(boxDecoration.border, isNull, reason: 'Must have no border colors');

    // 2. Verify 'UPDATE NOW' primary button uses lime accent color with no border
    final updateButtonFinder = find.widgetWithText(ElevatedButton, 'UPDATE NOW');
    expect(updateButtonFinder, findsOneWidget);
    final updateButton = tester.widget<ElevatedButton>(updateButtonFinder);
    final buttonStyle = updateButton.style!;
    expect(buttonStyle.backgroundColor?.resolve({}), equals(limeAccent.color));
    expect(buttonStyle.foregroundColor?.resolve({}), equals(limeAccent.onAccentColor));
    expect(buttonStyle.side?.resolve({}), equals(BorderSide.none));

    // 3. Verify 'LATER' button uses surfaceContainerHigh without any borders
    final laterButtonFinder = find.widgetWithText(ElevatedButton, 'LATER');
    expect(laterButtonFinder, findsOneWidget);
    final laterButton = tester.widget<ElevatedButton>(laterButtonFinder);
    final laterStyle = laterButton.style!;
    expect(laterStyle.backgroundColor?.resolve({}), equals(cyberLimeTheme.surfaceContainerHigh));
    expect(laterStyle.side?.resolve({}), equals(BorderSide.none));

    // 4. Verify text content
    expect(find.text('UPDATE AVAILABLE'), findsOneWidget);
    expect(find.text('2.4.0'), findsOneWidget);
    expect(find.text('Great new features'), findsOneWidget);
  });

  testWidgets('UpdateDialog critical update renders error semantic color without borders', (tester) async {
    final darkTheme = AppThemeMode.dark;
    final royalBlue = AppAccentColor.royalBlue;

    final fakeForceUpdateState = UpdateState(
      status: UpdateStatus.updateAvailable,
      isForceUpdate: true,
      currentVersion: '1.0.0',
      updateInfo: UpdateInfo(
        latestVersion: '2.4.0',
        minimumVersion: '2.0.0',
        forceUpdate: true,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: ['Security hotfix'],
        publishedAt: DateTime(2026, 10, 30),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeSettingsProvider.overrideWith(
            () => _FakeThemeSettingsNotifier(
              ThemeSettingsState(
                themeMode: darkTheme,
                accentColor: royalBlue,
                isUsingCustomTheme: true,
              ),
            ),
          ),
          updateProvider.overrideWith(
            () => _FakeUpdateNotifier(fakeForceUpdateState),
          ),
        ],
        child: MaterialApp(
          theme: darkTheme.toThemeData(royalBlue),
          home: const Scaffold(
            body: UpdateDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('CRITICAL UPDATE'), findsOneWidget);
    // On force update, LATER button must not be rendered
    expect(find.text('LATER'), findsNothing);
    expect(find.text('UPDATE NOW'), findsOneWidget);
  });
}

class _FakeThemeSettingsNotifier extends ThemeSettingsNotifier {
  final ThemeSettingsState _initial;
  _FakeThemeSettingsNotifier(this._initial);

  @override
  ThemeSettingsState build() => _initial;
}

class _FakeUpdateNotifier extends UpdateNotifier {
  final UpdateState _initial;
  _FakeUpdateNotifier(this._initial);

  @override
  UpdateState build() => _initial;
}
