import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/new_songs.dart' as bridge;

void main() {
  test('maps a valid bounded new-song collection', () {
    final result = mapBridgeNewSongs(
      const bridge.QqMusicNewSongsLoad(
        category: bridge.QqMusicNewSongCategory.latest,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixtureMid:-',
            title: 'Synthetic Track',
            artistNames: ['Artist'],
            artists: [],
          ),
        ],
      ),
      NewSongCategory.latest,
    );

    expect(result.failure, isNull);
    expect(result.category, NewSongCategory.latest);
    expect(result.tracks.single.title, 'Synthetic Track');
    expect(
      () => result.tracks.add(result.tracks.single),
      throwsUnsupportedError,
    );
  });

  test('rejects category mismatch and contradictory failure data', () {
    final mismatch = mapBridgeNewSongs(
      const bridge.QqMusicNewSongsLoad(
        category: bridge.QqMusicNewSongCategory.japan,
        tracks: [],
      ),
      NewSongCategory.latest,
    );
    expect(mismatch.failure, NewSongFailure.invalidResponse);

    final conflict = mapBridgeNewSongs(
      const bridge.QqMusicNewSongsLoad(
        category: bridge.QqMusicNewSongCategory.latest,
        tracks: [
          bridge_library.LibraryTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'track:41001:0:fixtureMid:-',
            title: 'must not coexist',
            artistNames: ['Artist'],
            artists: [],
          ),
        ],
        failure: bridge.QqMusicNewSongsLoadFailure.network,
      ),
      NewSongCategory.latest,
    );
    expect(conflict.failure, NewSongFailure.invalidResponse);
  });

  test('maps every Bridge failure and forwards category and cancellation', () {
    final expected = {
      bridge.QqMusicNewSongsLoadFailure.coreUnavailable:
          NewSongFailure.coreUnavailable,
      bridge.QqMusicNewSongsLoadFailure.network: NewSongFailure.network,
      bridge.QqMusicNewSongsLoadFailure.serviceUnavailable:
          NewSongFailure.serviceUnavailable,
      bridge.QqMusicNewSongsLoadFailure.invalidResponse:
          NewSongFailure.invalidResponse,
      bridge.QqMusicNewSongsLoadFailure.cancelled: NewSongFailure.cancelled,
      bridge.QqMusicNewSongsLoadFailure.alreadyRunning:
          NewSongFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeNewSongFailure(input), output);
    }

    late NewSongCategory requested;
    final operation = _ImmediateOperation();
    final gateway = RustNewSongGateway(
      operationFactory: (category) {
        requested = category;
        return operation;
      },
    );
    final begun = gateway.beginLoad(category: NewSongCategory.korea);
    expect(begun.cancel(), isTrue);
    expect(requested, NewSongCategory.korea);
    expect(operation.cancelCalls, 1);
  });
}

class _ImmediateOperation implements NewSongLoadOperation {
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<NewSongResult> run() async => const NewSongResult(
    category: NewSongCategory.latest,
    failure: NewSongFailure.cancelled,
  );
}
