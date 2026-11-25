import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goplay/widgets/cards/clean_card.dart';

void main() {
  group('CleanCard Widget Tests', () {
    testWidgets('renders child content and executes onTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CleanCard(
              onTap: () => tapped = true,
              child: const Text('Hello Clean Liquid Glass'),
            ),
          ),
        ),
      );

      expect(find.text('Hello Clean Liquid Glass'), findsOneWidget);

      await tester.tap(find.text('Hello Clean Liquid Glass'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('renders BackdropFilter with custom blur sigma', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CleanCard(
              blurSigma: 24.0,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      final backdropFinder = find.byType(BackdropFilter);
      expect(backdropFinder, findsOneWidget);

      final backdropFilter = tester.widget<BackdropFilter>(backdropFinder);
      expect(backdropFilter.filter, ImageFilter.blur(sigmaX: 24.0, sigmaY: 24.0));
    });

    testWidgets('renders structured layout with leading, title, subtitle, and trailing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CleanCard(
              leading: const Icon(Icons.tv_rounded),
              title: const Text('Glass Channel'),
              subtitle: const Text('1080p Full HD'),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.tv_rounded), findsOneWidget);
      expect(find.text('Glass Channel'), findsOneWidget);
      expect(find.text('1080p Full HD'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });
}
