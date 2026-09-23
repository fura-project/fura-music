import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/library_mutation_coordinator.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/track_like_gateway.dart';

void main() {
  const track = PlaylistTrackSummary(
    providerId: 'netease-cloud-music',
    opaqueId: 'track-1',
    title: 'Synthetic track',
    artistNames: ['Synthetic artist'],
  );

  test('same identity is single-flight and confirmed writes refresh', () async {
    final operation = _CompletingTrackLikeOperation();
    final gateway = _TrackLikeGateway(operation);
    final coordinator = LibraryMutationCoordinator(
      providerId: 'netease-cloud-music',
      trackLikeGateway: gateway,
    );
    var refreshes = 0;

    final first = coordinator.setTrackLiked(
      track: track,
      liked: true,
      refreshAuthoritativeState: () async => refreshes += 1,
    );
    final repeated = await coordinator.setTrackLiked(
      track: track,
      liked: true,
      refreshAuthoritativeState: () async => refreshes += 1,
    );

    expect(repeated.status, LibraryMutationStatus.alreadyRunning);
    expect(gateway.beginCount, 1);
    operation.complete(
      const TrackLikeMutationResult(confirmedState: TrackLikeState.liked),
    );
    expect((await first).status, LibraryMutationStatus.confirmed);
    expect(refreshes, 1);
    coordinator.dispose();
  });

  test('unknown outcome refreshes once and is never retried', () async {
    final operation = _ImmediateTrackLikeOperation(
      const TrackLikeMutationResult(
        failure: TrackLikeMutationFailure.networkOutcomeUnknown,
      ),
    );
    final gateway = _TrackLikeGateway(operation);
    final coordinator = LibraryMutationCoordinator(
      providerId: 'netease-cloud-music',
      trackLikeGateway: gateway,
    );
    var refreshes = 0;

    final result = await coordinator.setTrackLiked(
      track: track,
      liked: false,
      refreshAuthoritativeState: () async => refreshes += 1,
    );

    expect(result.status, LibraryMutationStatus.outcomeUnknown);
    expect(gateway.beginCount, 1);
    expect(operation.runCount, 1);
    expect(refreshes, 1);
    coordinator.dispose();
  });

  test('foreign provider is rejected before gateway transport', () async {
    final operation = _ImmediateTrackLikeOperation(
      const TrackLikeMutationResult(confirmedState: TrackLikeState.liked),
    );
    final gateway = _TrackLikeGateway(operation);
    final coordinator = LibraryMutationCoordinator(
      providerId: 'qq-music',
      trackLikeGateway: gateway,
    );

    final result = await coordinator.setTrackLiked(
      track: track,
      liked: true,
      refreshAuthoritativeState: () async {},
    );

    expect(result.status, LibraryMutationStatus.unavailable);
    expect(gateway.beginCount, 0);
    coordinator.dispose();
  });

  test(
    'disposing cancels local wait and stale completion cannot refresh',
    () async {
      final operation = _CompletingTrackLikeOperation();
      final coordinator = LibraryMutationCoordinator(
        providerId: 'netease-cloud-music',
        trackLikeGateway: _TrackLikeGateway(operation),
      );
      var refreshes = 0;
      final pending = coordinator.setTrackLiked(
        track: track,
        liked: true,
        refreshAuthoritativeState: () async => refreshes += 1,
      );

      coordinator.dispose();
      expect(operation.cancelCount, 1);
      operation.complete(
        const TrackLikeMutationResult(confirmedState: TrackLikeState.liked),
      );

      expect((await pending).status, LibraryMutationStatus.outcomeUnknown);
      expect(refreshes, 0);
    },
  );
}

class _TrackLikeGateway implements TrackLikeGateway {
  _TrackLikeGateway(this.operation);

  final TrackLikeMutationOperation operation;
  int beginCount = 0;

  @override
  TrackLikeMutationOperation beginMutation({
    required String providerId,
    required String opaqueTrackId,
    required TrackLikeState desiredState,
  }) {
    beginCount += 1;
    return operation;
  }
}

class _ImmediateTrackLikeOperation implements TrackLikeMutationOperation {
  _ImmediateTrackLikeOperation(this.result);

  final TrackLikeMutationResult result;
  int runCount = 0;

  @override
  bool cancel() => true;

  @override
  Future<TrackLikeMutationResult> run() async {
    runCount += 1;
    return result;
  }
}

class _CompletingTrackLikeOperation implements TrackLikeMutationOperation {
  final Completer<TrackLikeMutationResult> _completer = Completer();
  int cancelCount = 0;

  void complete(TrackLikeMutationResult result) => _completer.complete(result);

  @override
  bool cancel() {
    cancelCount += 1;
    return true;
  }

  @override
  Future<TrackLikeMutationResult> run() => _completer.future;
}
