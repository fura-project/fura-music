import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';
import 'package:flutterustmusic/playback/expanded_now_playing_page.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'palette and visible cover share one HTTP response and remount warm',
    (tester) async {
      const coverKey = ValueKey('network-cover');
      const placeholder = ColoredBox(
        key: ValueKey('network-cover-placeholder'),
        color: Colors.grey,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final uri = 'http://127.0.0.1:${server.port}/fixture.png';
      final requested = Completer<void>();
      final releaseResponse = Completer<void>();
      var requests = 0;
      var bodies = 0;
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final subscription = server.listen((request) async {
        requests++;
        if (!requested.isCompleted) requested.complete();
        await releaseResponse.future;
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..headers.set(HttpHeaders.cacheControlHeader, 'public, max-age=3600')
          ..add(bytes);
        bodies++;
        await request.response.close();
      });
      final imageProvider = musicArtworkImageProvider(uri);
      final palette = ArtworkColorSchemeCache();
      addTearDown(() async {
        if (!releaseResponse.isCompleted) releaseResponse.complete();
        await subscription.cancel();
        await server.close(force: true);
        await imageProvider.evict();
      });
      final paletteFuture = palette.resolve(
        artworkUri: uri,
        brightness: Brightness.light,
      );
      await requested.future.timeout(const Duration(seconds: 5));

      Widget cover() => MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 64,
            child: Image.network(
              uri,
              key: coverKey,
              frameBuilder: musicArtworkFrameBuilder(placeholder),
            ),
          ),
        ),
      );
      await tester.pumpWidget(cover());
      final coverFinder = find.byKey(coverKey);
      final reveal = find.descendant(
        of: coverFinder,
        matching: find.byType(FadeTransition),
      );
      expect(find.byWidget(placeholder), findsOneWidget);
      final pending = await imageProvider.obtainCacheStatus(
        configuration: ImageConfiguration.empty,
      );
      expect(pending?.pending, isTrue);
      releaseResponse.complete();
      expect(
        await paletteFuture.timeout(const Duration(seconds: 10)),
        isNotNull,
      );

      // The palette may complete ahead of the visible Image's next build.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(RawImage).evaluate().isNotEmpty) break;
      }
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(cover());
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.byWidget(placeholder), findsNothing);
      expect(reveal, findsNothing);
      expect((requests, bodies), (1, 1));
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isLinux,
  );
}
