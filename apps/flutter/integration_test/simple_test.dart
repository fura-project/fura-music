import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/src/rust/api/album.dart';
import 'package:flutterustmusic/src/rust/api/artist.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/api/favorite_albums.dart';
import 'package:flutterustmusic/src/rust/api/library.dart';
import 'package:flutterustmusic/src/rust/api/lyrics.dart';
import 'package:flutterustmusic/src/rust/api/media.dart';
import 'package:flutterustmusic/src/rust/api/new_albums.dart';
import 'package:flutterustmusic/src/rust/api/queue.dart';
import 'package:flutterustmusic/src/rust/api/rankings.dart';
import 'package:flutterustmusic/src/rust/api/recommendations.dart';
import 'package:flutterustmusic/src/rust/api/search.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('loads typed provider status from Rust', (tester) async {
    final status = bootstrapStatus();

    expect(status.provider.id, 'qq-music');
    expect(status.provider.implementedCapabilities, [
      'Search',
      'Catalog',
      'Recommendations',
      'Authentication',
      'UserLibrary',
      'Lyrics',
      'MediaResolution',
    ]);
    final restore = restoreQqMusicCredentialFromSecureStorage();
    expect(restore.state, QqMusicCredentialRestoreState.signedOut);
    expect(restore.failure, isNull);
    expect(qqMusicHasAuthenticatedCredential(), isFalse);
    final unusedStart = reserveQqMusicWechatQrLoginStart();
    expect(cancelQqMusicWechatQrLoginStart(attemptId: unusedStart), isFalse);
    final unusedLibraryLoad = beginQqMusicUserPlaylistLoad();
    expect(unusedLibraryLoad.isActive, isTrue);
    expect(unusedLibraryLoad.cancel(), isTrue);
    final cancelledLibraryLoad = await unusedLibraryLoad.run();
    expect(
      cancelledLibraryLoad.failure,
      QqMusicUserPlaylistLoadFailure.cancelled,
    );
    final unusedTrackPageLoad = beginQqMusicPlaylistTrackPageLoad(
      providerId: 'qq-music',
      opaquePlaylistId: 'favorite:8001',
      offset: 0,
      size: 100,
    );
    expect(unusedTrackPageLoad.isActive, isTrue);
    expect(unusedTrackPageLoad.cancel(), isTrue);
    final cancelledTrackPageLoad = await unusedTrackPageLoad.run();
    expect(
      cancelledTrackPageLoad.failure,
      QqMusicPlaylistTrackPageLoadFailure.cancelled,
    );
    final unusedSearchLoad = beginQqMusicTrackSearchPageLoad(
      query: 'synthetic query',
      page: 1,
      size: 30,
    );
    expect(unusedSearchLoad.isActive, isTrue);
    expect(unusedSearchLoad.cancel(), isTrue);
    final cancelledSearchLoad = await unusedSearchLoad.run();
    expect(
      cancelledSearchLoad.failure,
      QqMusicTrackSearchPageLoadFailure.cancelled,
    );
    final unusedArtistSearchLoad = beginQqMusicArtistSearchPageLoad(
      query: 'synthetic query',
      page: 1,
      size: 30,
    );
    expect(unusedArtistSearchLoad.isActive, isTrue);
    expect(unusedArtistSearchLoad.cancel(), isTrue);
    final cancelledArtistSearchLoad = await unusedArtistSearchLoad.run();
    expect(
      cancelledArtistSearchLoad.failure,
      QqMusicArtistSearchPageLoadFailure.cancelled,
    );
    final unusedAlbumSearchLoad = beginQqMusicAlbumSearchPageLoad(
      query: 'synthetic query',
      page: 1,
      size: 30,
    );
    expect(unusedAlbumSearchLoad.isActive, isTrue);
    expect(unusedAlbumSearchLoad.cancel(), isTrue);
    final cancelledAlbumSearchLoad = await unusedAlbumSearchLoad.run();
    expect(
      cancelledAlbumSearchLoad.failure,
      QqMusicAlbumSearchPageLoadFailure.cancelled,
    );
    final unusedPlaylistSearchLoad = beginQqMusicPlaylistSearchPageLoad(
      query: 'synthetic query',
      page: 1,
      size: 30,
    );
    expect(unusedPlaylistSearchLoad.isActive, isTrue);
    expect(unusedPlaylistSearchLoad.cancel(), isTrue);
    final cancelledPlaylistSearchLoad = await unusedPlaylistSearchLoad.run();
    expect(
      cancelledPlaylistSearchLoad.failure,
      QqMusicPlaylistSearchPageLoadFailure.cancelled,
    );
    final unusedAlbumLoad = beginQqMusicAlbumTrackPageLoad(
      providerId: 'qq-music',
      opaqueAlbumId: 'album:43001:fixtureAlbumMid',
      offset: 0,
      size: 30,
    );
    expect(unusedAlbumLoad.isActive, isTrue);
    expect(unusedAlbumLoad.cancel(), isTrue);
    final cancelledAlbumLoad = await unusedAlbumLoad.run();
    expect(
      cancelledAlbumLoad.failure,
      QqMusicAlbumTrackPageLoadFailure.cancelled,
    );
    final unusedAlbumDetailsLoad = beginQqMusicAlbumDetailsLoad(
      providerId: 'qq-music',
      opaqueAlbumId: 'album:43001:fixtureAlbumMid',
    );
    expect(unusedAlbumDetailsLoad.isActive, isTrue);
    expect(unusedAlbumDetailsLoad.cancel(), isTrue);
    final cancelledAlbumDetailsLoad = await unusedAlbumDetailsLoad.run();
    expect(
      cancelledAlbumDetailsLoad.failure,
      QqMusicAlbumDetailsLoadFailure.cancelled,
    );
    final unusedArtistLoad = beginQqMusicArtistTrackPageLoad(
      providerId: 'qq-music',
      opaqueArtistId: 'artist:61001:fixtureArtistMid',
      offset: 0,
      size: 30,
    );
    expect(unusedArtistLoad.isActive, isTrue);
    expect(unusedArtistLoad.cancel(), isTrue);
    final cancelledArtistLoad = await unusedArtistLoad.run();
    expect(
      cancelledArtistLoad.failure,
      QqMusicArtistTrackPageLoadFailure.cancelled,
    );
    final unusedArtistAlbumLoad = beginQqMusicArtistAlbumPageLoad(
      providerId: 'qq-music',
      opaqueArtistId: 'artist:61001:fixtureArtistMid',
      offset: 0,
      size: 30,
    );
    expect(unusedArtistAlbumLoad.isActive, isTrue);
    expect(unusedArtistAlbumLoad.cancel(), isTrue);
    final cancelledArtistAlbumLoad = await unusedArtistAlbumLoad.run();
    expect(
      cancelledArtistAlbumLoad.failure,
      QqMusicArtistAlbumPageLoadFailure.cancelled,
    );
    final unusedNewAlbumLoad = beginQqMusicNewAlbumPageLoad(
      region: QqMusicNewAlbumRegion.western,
      offset: 0,
      size: 20,
    );
    expect(unusedNewAlbumLoad.isActive, isTrue);
    expect(unusedNewAlbumLoad.cancel(), isTrue);
    final cancelledNewAlbumLoad = await unusedNewAlbumLoad.run();
    expect(cancelledNewAlbumLoad.region, QqMusicNewAlbumRegion.western);
    expect(
      cancelledNewAlbumLoad.failure,
      QqMusicNewAlbumPageLoadFailure.cancelled,
    );
    final unusedFavoriteAlbumLoad = beginQqMusicFavoriteAlbumPageLoad(
      offset: 0,
      size: 20,
    );
    expect(unusedFavoriteAlbumLoad.isActive, isTrue);
    expect(unusedFavoriteAlbumLoad.cancel(), isTrue);
    final cancelledFavoriteAlbumLoad = await unusedFavoriteAlbumLoad.run();
    expect(
      cancelledFavoriteAlbumLoad.failure,
      QqMusicFavoriteAlbumPageLoadFailure.cancelled,
    );
    final unusedRecommendationLoad = beginQqMusicRecommendedPlaylistPageLoad(
      offset: 0,
      size: 20,
    );
    expect(unusedRecommendationLoad.isActive, isTrue);
    expect(unusedRecommendationLoad.cancel(), isTrue);
    final cancelledRecommendationLoad = await unusedRecommendationLoad.run();
    expect(
      cancelledRecommendationLoad.failure,
      QqMusicRecommendedPlaylistPageLoadFailure.cancelled,
    );
    final unusedRadarLoad = beginQqMusicRadarTrackPageLoad(page: 1);
    expect(unusedRadarLoad.isActive, isTrue);
    expect(unusedRadarLoad.cancel(), isTrue);
    final cancelledRadarLoad = await unusedRadarLoad.run();
    expect(
      cancelledRadarLoad.failure,
      QqMusicRadarTrackPageLoadFailure.cancelled,
    );
    final unusedRankingGroupLoad = beginQqMusicRankingGroupLoad();
    expect(unusedRankingGroupLoad.isActive, isTrue);
    expect(unusedRankingGroupLoad.cancel(), isTrue);
    final cancelledRankingGroupLoad = await unusedRankingGroupLoad.run();
    expect(
      cancelledRankingGroupLoad.failure,
      QqMusicRankingLoadFailure.cancelled,
    );
    final unusedRankingTrackLoad = beginQqMusicRankingTrackPageLoad(
      providerId: 'qq-music',
      opaqueRankingId: 'ranking:62001',
      offset: 0,
      size: 30,
    );
    expect(unusedRankingTrackLoad.isActive, isTrue);
    expect(unusedRankingTrackLoad.cancel(), isTrue);
    final cancelledRankingTrackLoad = await unusedRankingTrackLoad.run();
    expect(
      cancelledRankingTrackLoad.failure,
      QqMusicRankingLoadFailure.cancelled,
    );
    final unusedMediaResolution = beginQqMusicMediaResolution(
      providerId: 'qq-music',
      opaqueTrackId: 'track:41001:0:1:fixtureTrackMid1',
    );
    expect(unusedMediaResolution.isActive, isTrue);
    expect(unusedMediaResolution.cancel(), isTrue);
    final cancelledMediaResolution = await unusedMediaResolution.run();
    expect(
      cancelledMediaResolution.failure,
      QqMusicMediaResolutionFailure.cancelled,
    );
    final unusedLyricLoad = beginQqMusicLyricLoad(
      providerId: 'qq-music',
      opaqueTrackId: 'track:41001:0:1:fixtureTrackMid1',
    );
    expect(unusedLyricLoad.isActive, isTrue);
    expect(unusedLyricLoad.cancel(), isTrue);
    final cancelledLyricLoad = await unusedLyricLoad.run();
    expect(cancelledLyricLoad.failure, QqMusicLyricLoadFailure.cancelled);
    final queue = createPlaybackQueue();
    final queueTrack = LibraryTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'track:41001:0:1:fixtureTrackMid1',
      title: 'Synthetic queue track',
      artistNames: const ['Fixture artist'],
      artists: const [
        CatalogArtistSummary(
          providerId: 'qq-music',
          opaqueId: 'artist:42001:fixtureArtistMid',
          name: 'Fixture artist',
        ),
      ],
      album: const CatalogAlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureAlbumMid',
        title: 'Synthetic Album',
      ),
    );
    final replacedQueue = queue.replace(
      tracks: [queueTrack, queueTrack],
      currentIndex: 0,
    );
    expect(replacedQueue.failure, isNull);
    expect(replacedQueue.snapshot?.tracks, hasLength(2));
    expect(
      replacedQueue.snapshot?.tracks.first.artists.first.opaqueId,
      'artist:42001:fixtureArtistMid',
    );
    expect(
      replacedQueue.snapshot?.tracks.first.album?.opaqueId,
      'album:43001:fixtureAlbumMid',
    );
    expect(replacedQueue.snapshot?.currentIndex, 0);
    final advancedQueue = queue.advance();
    expect(advancedQueue.currentChanged, isTrue);
    expect(advancedQueue.snapshot?.currentIndex, 1);
    expect(advancedQueue.snapshot?.hasNext, isFalse);
    expect(
      queue.select(index: 9).failure,
      PlaybackQueueFailure.invalidPosition,
    );
    expect(queue.snapshot().snapshot?.currentIndex, 1);
    expect(queue.clear().snapshot?.tracks, isEmpty);

    await tester.pumpWidget(MusicApp(bootstrap: status));
    expect(find.text('QQ Music connected'), findsOneWidget);
  });
}
