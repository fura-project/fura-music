import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_catalog_header.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  testWidgets('keeps compact title hierarchy within 360 px', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.light(),
        home: const Scaffold(
          body: MusicCatalogHeader(
            artwork: ColoredBox(
              key: ValueKey('catalog-artwork'),
              color: Colors.green,
            ),
            eyebrow: 'ALBUM',
            title: 'A deliberately long catalog title for compact layouts',
            titleKey: ValueKey('catalog-title'),
            desktop: false,
            children: [SizedBox(height: 8), Text('12 Tracks')],
          ),
        ),
      ),
    );

    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-title')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('catalog-artwork'))),
      const Size.square(92),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('uses the bounded desktop row and dark Material hierarchy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: MusicMaterialTheme.dark(),
        home: const Scaffold(
          body: MusicCatalogHeader(
            artwork: ColoredBox(
              key: ValueKey('desktop-artwork'),
              color: Colors.green,
            ),
            eyebrow: 'ARTIST',
            title: 'Fixture Artist',
            titleKey: ValueKey('desktop-title'),
            desktop: true,
            children: [SizedBox(height: 8), Text('24 Albums')],
          ),
        ),
      ),
    );

    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.text('Fixture Artist'), findsOneWidget);
    expect(find.text('24 Albums'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('desktop-artwork'))),
      const Size.square(132),
    );
    expect(
      find.descendant(of: find.byType(Center), matching: find.byType(Row)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
