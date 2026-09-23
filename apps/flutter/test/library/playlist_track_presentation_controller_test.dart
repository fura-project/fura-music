import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_controller.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_track_presentation_controller.dart';

void main() {
  const owned = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'owned',
    title: 'Owned',
    ownership: UserPlaylistOwnership.owned,
  );
  const liked = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'liked',
    title: 'Liked',
    isLikedSongs: true,
    ownership: UserPlaylistOwnership.owned,
  );
  const saved = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'saved',
    title: 'Saved',
    ownership: UserPlaylistOwnership.saved,
  );
  const track = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'track',
    title: 'Track',
    artistNames: ['Artist'],
  );

  test('only owned non-Liked playlists are add targets', () async {
    final library = UserLibraryController(
      _LibraryGateway(
        const UserLibraryResult(playlists: [owned, liked, saved]),
      ),
    );
    await library.load();
    final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
    final controller = PlaylistTrackPresentationController(
      providerId: 'qq-music',
      enabled: true,
      library: library,
      gateway: _DetailGateway(),
      mutations: mutations,
    );

    expect(controller.ownedPlaylists, [same(owned)]);

    controller.dispose();
    mutations.dispose();
    library.dispose();
  });

  test('confirmed add performs one write and authoritative read', () async {
    final library = UserLibraryController(
      _LibraryGateway(const UserLibraryResult(playlists: [owned])),
    );
    await library.load();
    final writeGateway = _TrackMutationGateway();
    final detailGateway = _DetailGateway();
    final mutations = LibraryMutationCoordinator(
      providerId: 'qq-music',
      playlistTrackGateway: writeGateway,
    );
    final controller = PlaylistTrackPresentationController(
      providerId: 'qq-music',
      enabled: true,
      library: library,
      gateway: detailGateway,
      mutations: mutations,
    );

    final outcome = await controller.addTrack(playlist: owned, track: track);

    expect(outcome.status, LibraryMutationStatus.confirmed);
    expect(writeGateway.calls, 1);
    expect(detailGateway.calls, 1);

    controller.dispose();
    mutations.dispose();
    library.dispose();
  });
}

class _LibraryGateway implements UserLibraryGateway {
  const _LibraryGateway(this.result);

  final UserLibraryResult result;

  @override
  UserLibraryLoadOperation beginLoad() => _LibraryOperation(result);
}

class _LibraryOperation implements UserLibraryLoadOperation {
  const _LibraryOperation(this.result);

  final UserLibraryResult result;

  @override
  bool cancel() => true;

  @override
  Future<UserLibraryResult> run() async => result;
}

class _TrackMutationGateway implements PlaylistTrackGateway {
  int calls = 0;

  @override
  PlaylistTrackMutationOperation beginMutation({
    required String providerId,
    required String opaquePlaylistId,
    required String opaqueTrackId,
    required PlaylistTrackState desiredState,
  }) {
    calls += 1;
    return const _TrackMutationOperation();
  }
}

class _TrackMutationOperation implements PlaylistTrackMutationOperation {
  const _TrackMutationOperation();

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackMutationResult> run() async =>
      const PlaylistTrackMutationResult(
        confirmedState: PlaylistTrackState.present,
      );
}

class _DetailGateway implements PlaylistDetailGateway {
  int calls = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    calls += 1;
    return const _DetailOperation();
  }
}

class _DetailOperation implements PlaylistTrackPageLoadOperation {
  const _DetailOperation();

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => const PlaylistTrackPageResult(
    total: 1,
    tracks: [
      PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track',
        title: 'Track',
        artistNames: ['Artist'],
      ),
    ],
  );
}
