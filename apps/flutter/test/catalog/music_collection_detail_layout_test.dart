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
}
