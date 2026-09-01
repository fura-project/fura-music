import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/artist_artwork.dart';

void main() {
  testWidgets('binds an available Artist artwork URI to a network image', (
    tester,
  ) async {
    const uri = 'https://example.invalid/artist.jpg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 100,
            child: ArtistArtwork(uri: uri),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, uri);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('keeps a Material fallback when Artist artwork is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 100,
            child: ArtistArtwork(uri: null),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
