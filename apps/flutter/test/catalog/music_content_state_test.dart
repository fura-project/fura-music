import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_content_state.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  testWidgets('labels a compact loading state without visual overflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: const Scaffold(
          body: MusicLoadingPanel(
            key: ValueKey('loading-panel'),
            label: 'Loading Album Tracks',
          ),
        ),
      ),
    );

    expect(find.text('Loading Album Tracks'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading Album Tracks'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('keeps one explicit error live region and retry action', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: Scaffold(
          body: MusicContentStatePanel(
            key: const ValueKey('error-panel'),
            icon: Icons.cloud_off_rounded,
            title: 'Couldn’t load this Album',
            detail: 'Check your connection and try again.',
            liveRegion: true,
            action: FilledButton.tonal(
              onPressed: () => retryCount++,
              child: const Text('Try again'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Couldn’t load this Album'), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });
}
