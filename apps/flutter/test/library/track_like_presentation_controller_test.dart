import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';
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

  test(
    '1032 identities preload once and route resolves reuse snapshot',
    () async {
      final results = <PlaylistTrackPageResult>[];
      for (var offset = 0; offset < 1032; offset += 100) {
        final next = (offset + 100).clamp(0, 1032);
        results.add(
          PlaylistTrackPageResult(
            offset: offset,
            nextOffset: next,
            total: 1032,
            hasMore: next < 1032,
            membershipTrackOpaqueIds: [
              for (var index = offset; index < next; index++) 'track-$index',
            ],
          ),
        );
      }
      final gateway = _FakePlaylistGateway.fromResults(results);
      final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

      await controller.preload();

      const member = PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'track-1031',
        title: 'Member',
        artistNames: ['Artist'],
      );
      expect(controller.stateFor(member), AuthoritativeTrackLikeState.liked);
      expect(controller.stateFor(other), AuthoritativeTrackLikeState.notLiked);
      expect(gateway.requests, [
        for (var offset = 0; offset < 1032; offset += 100) (offset, 100),
      ]);

      for (var index = 0; index < 20; index++) {
        expect(
          await controller.resolve(member),
          AuthoritativeTrackLikeState.liked,
        );
        expect(
          await controller.resolve(other),
          AuthoritativeTrackLikeState.notLiked,
        );
      }
      expect(gateway.requests.length, 11);
      controller.dispose();
    },
  );

  test(
    'presentation omission does not poison provider identity membership',
    () async {
      final gateway = _FakePlaylistGateway.fromResults([
        const PlaylistTrackPageResult(
          nextOffset: 1,
          total: 1,
          omittedTrackCount: 1,
          membershipTrackOpaqueIds: ['liked-track'],
        ),
      ]);
      final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

      await controller.preload();

      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);
      expect(controller.stateFor(other), AuthoritativeTrackLikeState.notLiked);
      controller.dispose();
    },
  );

  test('identity-incomplete collection never fabricates a negative', () async {
    final gateway = _FakePlaylistGateway.fromResults([
      const PlaylistTrackPageResult(
        nextOffset: 1,
        total: 1,
        membershipIsExact: false,
        omittedTrackCount: 1,
      ),
    ]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    await controller.preload();

    expect(controller.stateFor(other), AuthoritativeTrackLikeState.unknown);
    controller.dispose();
  });

  test('page UI and membership preload join the same page future', () async {
    final pending = Completer<PlaylistTrackPageResult>();
    final source = _PendingOperation(pending);
    final gateway = _FakePlaylistGateway([source]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    final pageOperation = controller.sessionGateway.beginLoad(
      playlist: likedPlaylist,
      offset: 0,
      size: 100,
    );
    final pageResult = pageOperation.run();
    expect(gateway.requests, [(0, 100)]);

    pending.complete(
      const PlaylistTrackPageResult(
        nextOffset: 1,
        total: 1,
        membershipTrackOpaqueIds: ['liked-track'],
        tracks: [liked],
      ),
    );
    await pageResult;
    await controller.preload();

    expect(gateway.requests, [(0, 100)]);
    expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);
    controller.dispose();
  });

  test(
    'positive state is available before the remaining scan completes',
    () async {
      final tail = Completer<PlaylistTrackPageResult>();
      final gateway = _FakePlaylistGateway([
        const _ImmediateOperation(
          PlaylistTrackPageResult(
            nextOffset: 1,
            total: 2,
            hasMore: true,
            membershipTrackOpaqueIds: ['liked-track'],
          ),
        ),
        _PendingOperation(tail),
      ]);
      final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

      await Future<void>.delayed(Duration.zero);

      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);
      expect(gateway.requests, [(0, 100), (1, 100)]);
      tail.complete(
        const PlaylistTrackPageResult(offset: 1, nextOffset: 2, total: 2),
      );
      await controller.preload();
      controller.dispose();
    },
  );

  test(
    'paused scan resumes from retained continuation, never offset zero',
    () async {
      final gateway = _FakePlaylistGateway.fromResults([
        const PlaylistTrackPageResult(
          nextOffset: 100,
          total: 200,
          hasMore: true,
          membershipTrackOpaqueIds: ['liked-track'],
        ),
        const PlaylistTrackPageResult(failure: UserLibraryFailure.network),
        const PlaylistTrackPageResult(offset: 100, nextOffset: 200, total: 200),
      ]);
      final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

      await controller.preload();
      await controller.preload();

      expect(gateway.requests, [(0, 100), (100, 100), (100, 100)]);
      expect(controller.stateFor(other), AuthoritativeTrackLikeState.notLiked);
      controller.dispose();
    },
  );

  test('rebinding playlist cancels an old account-generation scan', () async {
    final pending = Completer<PlaylistTrackPageResult>();
    final operation = _PendingOperation(pending);
    final gateway = _FakePlaylistGateway([operation]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);
    final resolution = controller.resolve(other);

    controller.bindLikedPlaylist(null);
    pending.complete(const PlaylistTrackPageResult());

    expect(await resolution, AuthoritativeTrackLikeState.unavailable);
    expect(operation.cancelled, isTrue);
    controller.dispose();
  });

  test(
    'account generation replacement and logout discard the old snapshot',
    () async {
      const replacementPlaylist = UserPlaylistSummary(
        providerId: 'qq-music',
        opaqueId: 'liked-replacement-account',
        title: 'Liked Songs',
        isLikedSongs: true,
        ownership: UserPlaylistOwnership.owned,
      );
      final gateway = _FakePlaylistGateway.fromResults([
        const PlaylistTrackPageResult(
          nextOffset: 1,
          total: 1,
          membershipTrackOpaqueIds: ['liked-track'],
        ),
        const PlaylistTrackPageResult(),
      ]);
      final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);
      await controller.preload();
      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);

      controller.bindLikedPlaylist(replacementPlaylist);
      await controller.preload();
      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.notLiked);
      expect(gateway.requests, [(0, 100), (0, 100)]);

      controller.bindLikedPlaylist(null);
      expect(
        controller.stateFor(liked),
        AuthoritativeTrackLikeState.unavailable,
      );
      controller.dispose();
    },
  );

  test('credential rejection invalidates the Track account session', () async {
    final gateway = _FakePlaylistGateway.fromResults([
      const PlaylistTrackPageResult(
        failure: UserLibraryFailure.credentialRejected,
      ),
    ]);
    final controller = _controller(gateway)..bindLikedPlaylist(likedPlaylist);

    await controller.preload();

    expect(controller.stateFor(liked), AuthoritativeTrackLikeState.unavailable);
    controller.dispose();
  });

  test(
    'confirmed mutation applies a local delta without full invalidation',
    () async {
      final refresh = Completer<PlaylistTrackPageResult>();
      final gateway = _FakePlaylistGateway([
        const _ImmediateOperation(PlaylistTrackPageResult()),
        _PendingOperation(refresh),
      ]);
      final mutationGateway = _TrackMutationGateway(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.liked),
      );
      final controller = _controller(gateway, trackLikeGateway: mutationGateway)
        ..bindLikedPlaylist(likedPlaylist);
      await controller.preload();

      final outcome = await controller.setLiked(track: other, liked: true);

      expect(outcome.status, LibraryMutationStatus.confirmed);
      expect(controller.stateFor(other), AuthoritativeTrackLikeState.liked);
      expect(gateway.requests, [(0, 100), (0, 100)]);
      expect(mutationGateway.runCount, 1);
      controller.dispose();
    },
  );

  test(
    'outcome unknown targets one identity and keeps unrelated state',
    () async {
      final refresh = Completer<PlaylistTrackPageResult>();
      final gateway = _FakePlaylistGateway([
        const _ImmediateOperation(
          PlaylistTrackPageResult(
            nextOffset: 1,
            total: 1,
            membershipTrackOpaqueIds: ['liked-track'],
          ),
        ),
        _PendingOperation(refresh),
      ]);
      final controller = _controller(
        gateway,
        trackLikeGateway: _TrackMutationGateway(
          const TrackLikeMutationResult(
            failure: TrackLikeMutationFailure.networkOutcomeUnknown,
          ),
        ),
      )..bindLikedPlaylist(likedPlaylist);
      await controller.preload();

      final outcome = await controller.setLiked(track: other, liked: true);

      expect(outcome.status, LibraryMutationStatus.outcomeUnknown);
      expect(controller.stateFor(other), AuthoritativeTrackLikeState.unknown);
      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);
      controller.dispose();
    },
  );

  test('confirmed unlike applies an immediate negative delta', () async {
    final refresh = Completer<PlaylistTrackPageResult>();
    final gateway = _FakePlaylistGateway([
      const _ImmediateOperation(
        PlaylistTrackPageResult(
          nextOffset: 1,
          total: 1,
          membershipTrackOpaqueIds: ['liked-track'],
        ),
      ),
      _PendingOperation(refresh),
    ]);
    final controller = _controller(
      gateway,
      trackLikeGateway: _TrackMutationGateway(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.notLiked),
      ),
    )..bindLikedPlaylist(likedPlaylist);
    await controller.preload();

    final outcome = await controller.setLiked(track: liked, liked: false);

    expect(outcome.status, LibraryMutationStatus.confirmed);
    expect(controller.stateFor(liked), AuthoritativeTrackLikeState.notLiked);
    expect(gateway.requests, [(0, 100), (0, 100)]);
    controller.dispose();
  });

  test(
    'definitive failure preserves authoritative state and does not refresh',
    () async {
      final gateway = _FakePlaylistGateway.fromResults([
        const PlaylistTrackPageResult(
          nextOffset: 1,
          total: 1,
          membershipTrackOpaqueIds: ['liked-track'],
        ),
      ]);
      final controller = _controller(
        gateway,
        trackLikeGateway: _TrackMutationGateway(
          const TrackLikeMutationResult(
            failure: TrackLikeMutationFailure.invalidRequest,
          ),
        ),
      )..bindLikedPlaylist(likedPlaylist);
      await controller.preload();

      final outcome = await controller.setLiked(track: liked, liked: false);

      expect(outcome.status, LibraryMutationStatus.definitiveFailure);
      expect(controller.stateFor(liked), AuthoritativeTrackLikeState.liked);
      expect(gateway.requests, [(0, 100)]);
      controller.dispose();
    },
  );
}

TrackLikePresentationController _controller(
  PlaylistDetailGateway gateway, {
  TrackLikeGateway? trackLikeGateway,
}) {
  final mutations = LibraryMutationCoordinator(
    providerId: 'qq-music',
    trackLikeGateway: trackLikeGateway,
  );
  addTearDown(mutations.dispose);
  return TrackLikePresentationController(
    providerId: 'qq-music',
    enabled: true,
    playlistGateway: gateway,
    mutations: mutations,
  );
}

class _FakePlaylistGateway implements PlaylistDetailGateway {
  _FakePlaylistGateway(this.operations);

  _FakePlaylistGateway.fromResults(List<PlaylistTrackPageResult> results)
    : operations = results
          .map<PlaylistTrackPageLoadOperation>(_ImmediateOperation.new)
          .toList();

  final List<PlaylistTrackPageLoadOperation> operations;
  final List<(int, int)> requests = [];
  int _index = 0;

  @override
  PlaylistTrackPageLoadOperation beginLoad({
    required UserPlaylistSummary playlist,
    required int offset,
    required int size,
  }) {
    requests.add((offset, size));
    return operations[_index++];
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

class _TrackMutationGateway implements TrackLikeGateway {
  _TrackMutationGateway(this.result);

  final TrackLikeMutationResult result;
  int runCount = 0;

  @override
  TrackLikeMutationOperation beginMutation({
    required String providerId,
    required String opaqueTrackId,
    required TrackLikeState desiredState,
  }) => _TrackMutationOperation(this);
}

class _TrackMutationOperation implements TrackLikeMutationOperation {
  const _TrackMutationOperation(this.owner);

  final _TrackMutationGateway owner;

  @override
  bool cancel() => true;

  @override
  Future<TrackLikeMutationResult> run() async {
    owner.runCount += 1;
    return owner.result;
  }
}
