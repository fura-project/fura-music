import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/fura_toast.dart';

void main() {
  testWidgets(
    'showFuraToast renders a floating capsule pill and animates within the visible M3 fade window',
    (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: FuraToastScope(
            resolveMargin: (_) => const EdgeInsets.fromLTRB(16, 0, 16, 108),
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  pageContext = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );

      showFuraToast(
        pageContext,
        '音乐库已更新。',
        surfaceKey: const ValueKey('test-toast-surface'),
      );
      await tester.pump();
      // Advance into the visible M3 SnackBar fade-in window (raw ~ 0.48 at 120ms/250ms).
      await tester.pump(const Duration(milliseconds: 120));

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.clipBehavior, Clip.none);
      expect(snackBar.backgroundColor, Colors.transparent);
      expect(snackBar.elevation, 0);
      expect(snackBar.shape, const StadiumBorder());
      expect(snackBar.margin, const EdgeInsets.fromLTRB(16, 0, 16, 108));

      final surfaceFinder = find.byKey(const ValueKey('test-toast-surface'));
      expect(surfaceFinder, findsOneWidget);
      final surface = tester.widget<Material>(surfaceFinder);
      expect(surface.elevation, 3);
      expect(surface.shape, const StadiumBorder());

      final midRect = tester.getRect(surfaceFinder);
      await tester.pumpAndSettle();
      final settledRect = tester.getRect(surfaceFinder);

      // Verify perceptible upward slide and scale expansion during the visible window.
      expect(midRect.center.dy, greaterThan(settledRect.center.dy + 6.0));
      expect(midRect.width, lessThan(settledRect.width * 0.97));
    },
  );

  testWidgets(
    'FuraDialogTransition adds scale and vertical lift entrance motion to showDialog',
    (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      showDialog<void>(
        context: pageContext,
        animationStyle: furaDialogAnimationStyle(pageContext),
        builder: (context) => const FuraDialogTransition(
          child: AlertDialog(
            key: ValueKey('test-animated-dialog'),
            title: Text('Dialog Title'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final dialogFinder = find.byKey(const ValueKey('test-animated-dialog'));
      final earlyRect = tester.getRect(dialogFinder);

      await tester.pumpAndSettle();
      final settledRect = tester.getRect(dialogFinder);

      expect(earlyRect.center.dy, greaterThan(settledRect.center.dy + 4.0));
      expect(earlyRect.width, lessThan(settledRect.width));
    },
  );
}
