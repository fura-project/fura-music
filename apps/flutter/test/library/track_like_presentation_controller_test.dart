import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/track_like_presentation_controller.dart';

void main() {
  const likedPlaylist = UserPlaylistSummary(
    providerId: 'qq-music',
    opaqueId: 'liked',
    title: 'Liked Songs',
    isLikedSongs: true,
    ownership: UserPlaylistOwnership.owned,
  );
  const liked = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'liked-track',
    title: 'Liked',
    artistNames: ['Artist'],
  );
  const other = PlaylistTrackSummary(
    providerId: 'qq-music',
    opaqueId: 'other-track',
    title: 'Other',
    artistNames: ['Artist'],
  );

  test('positive match is known before a complete collection', () async {
    final gateway = _FakePlaylistGateway([
      const PlaylistTrackPageResult(
        nextOffset: 1,
        total: 2,
        hasMore: true,
        tracks: [liked],
      ),
      const PlaylistTrackPageResult(offset: 1, nextOffset: 2, total: 2),
    ]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    expect(await controller.resolve(liked), AuthoritativeTrackLikeState.liked);
    expect(controller.stateFor(other), AuthoritativeTrackLikeState.unknown);
    expect(gateway.requests, [(0, 100)]);
    controller.dispose();
  });

  test('omitted rows prevent an authoritative negative state', () async {
    final gateway = _FakePlaylistGateway([
      const PlaylistTrackPageResult(
        nextOffset: 1,
        total: 1,
        omittedTrackCount: 1,
      ),
    ]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    expect(
      await controller.resolve(other),
      AuthoritativeTrackLikeState.unknown,
    );
    controller.dispose();
  });

  test('complete exact collection proves a negative state', () async {
    final gateway = _FakePlaylistGateway([
      const PlaylistTrackPageResult(total: 1, tracks: [liked]),
    ]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    expect(
      await controller.resolve(other),
      AuthoritativeTrackLikeState.notLiked,
    );
    controller.dispose();
  });

  test('rebinding playlist cancels an old account-generation scan', () async {
    final pending = Completer<PlaylistTrackPageResult>();
    final operation = _PendingOperation(pending);
    final gateway = _FakePlaylistGateway([], operation: operation);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);
    final resolution = controller.resolve(other);

    controller.bindLikedPlaylist(null);
    pending.complete(const PlaylistTrackPageResult());

    expect(await resolution, AuthoritativeTrackLikeState.unavailable);
    expect(operation.cancelled, isTrue);
    controller.dispose();
  });
}

TrackLikePresentationController _controller(PlaylistDetailGateway gateway) {
  final mutations = LibraryMutationCoordinator(providerId: 'qq-music');
  addTearDown(mutations.dispose);
  return TrackLikePresentationController(
    providerId: 'qq-music',
    enabled: true,
    playlistGateway: gateway,
    mutations: mutations,
  );
}

class _FakePlaylistGateway implements PlaylistDetailGateway {
  _FakePlaylistGateway(this.results, {this.operation});

  final List<PlaylistTrackPageResult> results;
  final PlaylistTrackPageLoadOperation? operation;
  final List<(int, int)> requests = [];
  int _index = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operation ?? _ImmediateOperation(results[_index++]);
  }
}

class _ImmediateOperation implements PlaylistTrackPageLoadOperation {
  const _ImmediateOperation(this.result);

  final PlaylistTrackPageResult result;

  @override
  bool cancel() => true;

  @override
  Future<PlaylistTrackPageResult> run() async => result;
}

class _PendingOperation implements PlaylistTrackPageLoadOperation {
  _PendingOperation(this.completer);

  final Completer<PlaylistTrackPageResult> completer;
  bool cancelled = false;

  @override
  bool cancel() {
    cancelled = true;
    return true;
  }

  @override
  Future<PlaylistTrackPageResult> run() => completer.future;
}
