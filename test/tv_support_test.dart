import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/services/tv_service.dart';
import 'package:goplay/widgets/tv_focus_wrapper.dart';
import 'package:goplay/widgets/tv_modal.dart';

void main() {
  group('TvDeviceInfo & TvScope', () {
    test('resolveIsTv respects explicit on/off overrides', () {
      expect(TvDeviceInfo.instance.resolveIsTv(null, override: 'on'), isTrue);
      expect(TvDeviceInfo.instance.resolveIsTv(null, override: 'off'), isFalse);
    });

    testWidgets('TvScope propagates isTv and overscan padding', (tester) async {
      late bool capturedTv;
      late EdgeInsets capturedPadding;

      await tester.pumpWidget(
        MaterialApp(
          home: TvScope(
            isTv: true,
            overscanEnabled: true,
            child: Builder(
              builder: (context) {
                capturedTv = TvScope.isTvOf(context);
                capturedPadding = TvScope.overscanPaddingOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(capturedTv, isTrue);
      expect(
        capturedPadding,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      );
    });

    testWidgets('TvScope returns zero overscan padding when disabled', (tester) async {
      late EdgeInsets capturedPadding;

      await tester.pumpWidget(
        MaterialApp(
          home: TvScope(
            isTv: true,
            overscanEnabled: false,
            child: Builder(
              builder: (context) {
                capturedPadding = TvScope.overscanPaddingOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(capturedPadding, EdgeInsets.zero);
    });
  });

  group('TvFocusable on TV', () {
    testWidgets('provisions Focus and responds to Enter/Select in TvScope', (tester) async {
      int tapped = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: TvScope(
            isTv: true,
            overscanEnabled: true,
            child: Scaffold(
              body: Center(
                child: TvFocusable(
                  autoFocus: true,
                  onTap: () => tapped++,
                  child: const SizedBox(
                    width: 120,
                    height: 48,
                    child: Text('Play'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tapped, 1);
    });
  });

  group('showAdaptiveSheet', () {
    testWidgets('renders centered Dialog when TvScope.isTv is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TvScope(
            isTv: true,
            overscanEnabled: true,
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showAdaptiveSheet<void>(
                        context: context,
                        builder: (_) => const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('TV Modal Content'),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('TV Modal Content'), findsOneWidget);
    });
  });
}
