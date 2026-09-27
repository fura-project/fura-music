import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authenticated_dependencies.dart';

void main() {
  const qqCore = [
    'Search',
    'Catalog',
    'Recommendations',
    'Authentication',
    'UserLibrary',
    'RecentHistoryRead',
    'TrackLikeMutation',
    'AlbumFavoriteMutation',
    'PlaylistTrackMutation',
    'PlaylistCreation',
    'PlaylistDeletion',
    'Lyrics',
  ];
  const netEaseCore = [
    'Search',
    'Catalog',
    'Recommendations',
    'Authentication',
    'UserLibrary',
    'RecentHistoryRead',
    'TrackLikeMutation',
    'PlaylistTrackMutation',
    'PlaylistCreation',
    'Lyrics',
  ];

  test('QQ production actions require both product and Core capability', () {
    final capabilities = MusicProviderCapabilities.qqMusic.constrainedByCore(
      qqCore,
    );
    expect(capabilities.trackLike, isTrue);
    expect(capabilities.albumFavorite, isTrue);
    expect(capabilities.playlistTrackMutation, isTrue);
    expect(capabilities.playlistCreate, isTrue);
    expect(capabilities.playlistDelete, isTrue);
    expect(capabilities.recentHistory, isTrue);
    expect(capabilities.supportedNewAlbumRegions, isNotEmpty);

    final withoutLike = MusicProviderCapabilities.qqMusic.constrainedByCore(
      qqCore.where((capability) => capability != 'TrackLikeMutation'),
    );
    expect(withoutLike.trackLike, isFalse);
    expect(withoutLike.albumFavorite, isTrue);
  });

  test('NetEase offline foundations cannot opt themselves into Flutter', () {
    final capabilities = MusicProviderCapabilities.netEaseCloudMusic
        .constrainedByCore([
          ...netEaseCore,
          'AlbumFavoriteMutation',
          'ArtistFavoriteMutation',
          'PlaylistDeletion',
        ]);

    expect(capabilities.trackLike, isTrue);
    expect(capabilities.albumFavorite, isFalse);
    expect(capabilities.artistFavorite, isFalse);
    expect(capabilities.playlistDelete, isFalse);
  });

  test('missing descriptor fails every affected Flutter surface closed', () {
    final capabilities = MusicProviderCapabilities.qqMusic.constrainedByCore(
      const [],
    );

    expect(capabilities.libraryMutations, isFalse);
    expect(capabilities.recentHistory, isFalse);
    expect(capabilities.radar, isFalse);
    expect(capabilities.dailyPlaylist, isFalse);
    expect(capabilities.supportedNewAlbumRegions, isEmpty);
    expect(capabilities.supportedNewSongCategories, isEmpty);
  });
}
