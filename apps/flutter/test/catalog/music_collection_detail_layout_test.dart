import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_collection_detail_layout.dart';

void main() {
  testWidgets('collection hero continuously shrinks and hands title to Shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handoffs = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicCollectionDetailLayout(
            onHeaderCollapsedChanged: handoffs.add,
            headerBuilder: (context, desktop, progress) =>
                MusicCollectionDetailHeader(
                  collapseProgress: progress,
                  desktop: desktop,
                  embedded: true,
                  artwork: const ColoredBox(color: Colors.green),
                  eyebrow: 'PLAYLIST',
                  title: 'Adaptive collection',
                  titleKey: const ValueKey('adaptive-title'),
                  summary: '40 Tracks',
                  onBack: () {},
                  backKey: const ValueKey('adaptive-back'),
                  backTooltip: 'Back',
                ),
            bodyBuilder: (context, desktop) => ListView.builder(
              key: const ValueKey('adaptive-track-list'),
              itemCount: 40,
              itemBuilder: (context, index) =>
                  SizedBox(height: 56, child: Text('Track $index')),
            ),
          ),
        ),
      ),
    );

    final expandedArtwork = tester.getSize(
      find.byKey(const ValueKey('collection-detail-artwork')),
    );
    expect(expandedArtwork.width, 156);

    await tester.drag(
      find.byKey(const ValueKey('adaptive-track-list')),
      const Offset(0, -66),
    );
    await tester.pump();
    final intermediateArtwork = tester.getSize(
      find.byKey(const ValueKey('collection-detail-artwork')),
    );
    expect(intermediateArtwork.width, closeTo(110, 2));

    await tester.drag(
      find.byKey(const ValueKey('adaptive-track-list')),
      const Offset(0, -80),
    );
    await tester.pump();
    final collapsedArtwork = tester.getSize(
      find.byKey(const ValueKey('collection-detail-artwork')),
    );
    expect(collapsedArtwork.width, 64);
    expect(handoffs, contains(true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact collection keeps Back and toolbar action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicCollectionDetailLayout(
            headerBuilder: (context, desktop, progress) =>
                MusicCollectionDetailHeader(
                  collapseProgress: progress,
                  desktop: desktop,
                  embedded: true,
                  artwork: const ColoredBox(color: Colors.green),
                  eyebrow: 'PLAYLIST',
                  title: 'Compact collection',
                  titleKey: const ValueKey('compact-title'),
                  summary: '40 Tracks',
                  onBack: () {},
                  backKey: const ValueKey('compact-back'),
                  backTooltip: 'Back',
                  toolbarAction: IconButton(
                    key: const ValueKey('compact-refresh'),
                    onPressed: () {},
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
            bodyBuilder: (context, desktop) => ListView.builder(
              key: const ValueKey('compact-track-list'),
              itemCount: 40,
              itemBuilder: (context, index) =>
                  SizedBox(height: 56, child: Text('Track $index')),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('compact-track-list')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collection-detail-local-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compact-back')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compact-refresh')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored offset beyond shortened content does not rebuild during layout',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController(initialScrollOffset: 1562);
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicCollectionDetailLayout(
              headerBuilder: (context, desktop, progress) => SizedBox(
                key: const ValueKey('restored-offset-header'),
                height: 120 - (56 * progress),
              ),
              bodyBuilder: (context, desktop) => ListView.builder(
                key: const ValueKey('restored-offset-list'),
                controller: scroll,
                itemCount: 7,
                itemBuilder: (context, index) => const SizedBox(height: 56),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(scroll.offset, lessThanOrEqualTo(scroll.position.maxScrollExtent));
      expect(tester.takeException(), isNull);
    },
  );
}
