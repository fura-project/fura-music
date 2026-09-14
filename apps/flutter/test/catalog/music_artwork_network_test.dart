import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/music_artwork_network.dart';

void main() {
  group('musicArtworkRequestHeaders', () {
    test('adds browser headers only for NetEase HTTPS artwork hosts', () {
      for (final uri in <String>[
        'https://music.126.net/image.jpg',
        'https://p1.music.126.net/image.jpg',
        'https://p2.music.126.net/image.jpg?param=320y320',
      ]) {
        expect(musicArtworkRequestHeaders(uri), <String, String>{
          'Referer': 'https://music.163.com/',
        }, reason: uri);
      }
    });

    test('does not alter other providers or untrusted URL variants', () {
      for (final uri in <String>[
        'https://y.gtimg.cn/music/photo_new/T002R300x300M000.jpg',
        'https://evil-music.126.net/image.jpg',
        'https://music.126.net.example.com/image.jpg',
        'http://p1.music.126.net/image.jpg',
        'https://user@p1.music.126.net/image.jpg',
        'not a url',
      ]) {
        expect(musicArtworkRequestHeaders(uri), isNull, reason: uri);
      }
    });

    test('network provider carries the same scoped headers', () {
      final netease = musicArtworkImageProvider(
        'https://p2.music.126.net/image.jpg',
      );
      final qq = musicArtworkImageProvider(
        'https://y.gtimg.cn/music/photo_new/image.jpg',
      );

      expect(netease, isA<NetworkImage>());
      expect(
        (netease as NetworkImage).headers,
        containsPair('Referer', 'https://music.163.com/'),
      );
      expect(netease.headers, isNot(contains('User-Agent')));
      expect(qq, isA<NetworkImage>());
      expect((qq as NetworkImage).headers, isNull);
    });

    test('installs one NetEase-compatible HttpClient user agent', () {
      final previous = HttpOverrides.current;
      addTearDown(() => HttpOverrides.global = previous);

      installMusicNetworkHttpPolicy();
      final overrides = HttpOverrides.current;
      expect(overrides, isNotNull);
      final client = overrides!.createHttpClient(null);
      addTearDown(client.close);

      expect(client.userAgent, 'Mozilla/5.0');
    });

    test('failure diagnostic exposes transport shape but not URL identity', () {
      const artwork =
          'https://p2.music.126.net/private-track-id.jpg?param=320y320';
      final diagnostic = musicArtworkFailureDiagnostic(
        artwork,
        NetworkImageLoadException(statusCode: 403, uri: Uri.parse(artwork)),
      );

      expect(diagnostic, contains('host=p2.music.126.net'));
      expect(diagnostic, contains('scheme=https'));
      expect(diagnostic, contains('status=403'));
      expect(diagnostic, contains('error=NetworkImageLoadException'));
      expect(diagnostic, isNot(contains('private-track-id')));
      expect(diagnostic, isNot(contains('320y320')));
    });

    testWidgets('error builder preserves the supplied artwork fallback', (
      tester,
    ) async {
      const fallback = SizedBox(key: ValueKey('fallback'));
      const host = Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: ValueKey('host')),
      );
      await tester.pumpWidget(host);
      final builder = musicArtworkErrorBuilder(
        'https://p2.music.126.net/art.jpg',
        fallback,
      );

      expect(
        builder(
          tester.element(find.byKey(const ValueKey('host'))),
          StateError('decode'),
          null,
        ),
        same(fallback),
      );
    });
  });
}
