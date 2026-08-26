import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/src/rust/api/album.dart';
import 'package:flutterustmusic/app.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart';
import 'package:flutterustmusic/src/rust/api/bootstrap.dart';
import 'package:flutterustmusic/src/rust/api/library.dart';
import 'package:flutterustmusic/src/rust/api/lyrics.dart';
import 'package:flutterustmusic/src/rust/api/media.dart';
import 'package:flutterustmusic/src/rust/api/queue.dart';
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
    );
    final replacedQueue = queue.replace(
      tracks: [queueTrack, queueTrack],
      currentIndex: 0,
    );
    expect(replacedQueue.failure, isNull);
    expect(replacedQueue.snapshot?.tracks, hasLength(2));
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
