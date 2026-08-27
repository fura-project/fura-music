import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/src/rust/api/music_video.dart' as bridge;

void main() {
  test('maps exact valid MV and immutable credited artists', () {
    final result = mapBridgeTrackMusicVideo(
      const bridge.TrackMusicVideoLoad(
        musicVideo: bridge.TrackMusicVideoSummary(
          providerId: 'qq-music',
          opaqueId: 'mv:fixture',
          title: 'Fixture MV',
          artistNames: ['Fixture Artist'],
          artworkUri: 'https://example.invalid/cover.jpg',
          durationSeconds: 181,
          sourceUri: 'https://example.invalid/video.mp4',
          quality: bridge.TrackMusicVideoQuality.hd,
        ),
      ),
    );

    expect(result.failure, isNull);
    expect(result.musicVideo?.opaqueId, 'mv:fixture');
    expect(result.musicVideo?.quality, TrackMusicVideoQuality.hd);
    expect(result.musicVideo?.durationSeconds, 181);
    expect(
      () => result.musicVideo?.artistNames.add('Another'),
      throwsUnsupportedError,
    );
  });

  test('preserves no-MV and maps every coarse failure', () {
    final noMv = mapBridgeTrackMusicVideo(const bridge.TrackMusicVideoLoad());
    expect(noMv.musicVideo, isNull);
    expect(noMv.failure, isNull);

    final expected = {
      bridge.TrackMusicVideoLoadFailure.coreUnavailable:
          TrackMusicVideoFailure.coreUnavailable,
      bridge.TrackMusicVideoLoadFailure.network: TrackMusicVideoFailure.network,
      bridge.TrackMusicVideoLoadFailure.serviceUnavailable:
          TrackMusicVideoFailure.serviceUnavailable,
      bridge.TrackMusicVideoLoadFailure.invalidResponse:
          TrackMusicVideoFailure.invalidResponse,
      bridge.TrackMusicVideoLoadFailure.sourceUnavailable:
          TrackMusicVideoFailure.sourceUnavailable,
      bridge.TrackMusicVideoLoadFailure.cancelled:
          TrackMusicVideoFailure.cancelled,
      bridge.TrackMusicVideoLoadFailure.alreadyRunning:
          TrackMusicVideoFailure.alreadyRunning,
    };
    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeTrackMusicVideoFailure(input), output);
    }
  });

  test('rejects conflicting, cleartext, and malformed envelopes', () {
    const valid = bridge.TrackMusicVideoSummary(
      providerId: 'qq-music',
      opaqueId: 'mv:fixture',
      title: 'Fixture MV',
      artistNames: ['Fixture Artist'],
      durationSeconds: 181,
      sourceUri: 'https://example.invalid/video.mp4',
      quality: bridge.TrackMusicVideoQuality.sd,
    );
    final malformed = [
      const bridge.TrackMusicVideoLoad(
        musicVideo: valid,
        failure: bridge.TrackMusicVideoLoadFailure.network,
      ),
      const bridge.TrackMusicVideoLoad(
        musicVideo: bridge.TrackMusicVideoSummary(
          providerId: 'qq-music',
          opaqueId: 'mv:fixture',
          title: 'Fixture MV',
          artistNames: ['Fixture Artist'],
          durationSeconds: 181,
          sourceUri: 'http://example.invalid/video.mp4',
          quality: bridge.TrackMusicVideoQuality.sd,
        ),
      ),
      const bridge.TrackMusicVideoLoad(
        musicVideo: bridge.TrackMusicVideoSummary(
          providerId: 'qq-music',
          opaqueId: 'mv:fixture',
          title: '',
          artistNames: ['Fixture Artist'],
          durationSeconds: 181,
          sourceUri: 'https://example.invalid/video.mp4',
          quality: bridge.TrackMusicVideoQuality.sd,
        ),
      ),
    ];

    for (final result in malformed) {
      expect(
        mapBridgeTrackMusicVideo(result).failure,
        TrackMusicVideoFailure.invalidResponse,
      );
    }
  });

  test('forwards exact opaque Track identity and cancellation', () {
    late (String, String) request;
    final operation = _ImmediateOperation(
      const TrackMusicVideoResult(failure: TrackMusicVideoFailure.cancelled),
    );
    final gateway = RustTrackMusicVideoGateway(
      operationFactory: (provider, opaqueTrackId) {
        request = (provider, opaqueTrackId);
        return operation;
      },
    );
    final begun = gateway.beginLoad(track: _track);

    expect(begun.cancel(), isTrue);
    expect(request, ('qq-music', 'track:41001:0:opaqueMid:-'));
    expect(operation.cancelCalls, 1);
  });
}

const _track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:41001:0:opaqueMid:-',
  title: 'Fixture Track',
  artistNames: ['Fixture Artist'],
);

class _ImmediateOperation implements TrackMusicVideoLoadOperation {
  _ImmediateOperation(this.result);

  final TrackMusicVideoResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<TrackMusicVideoResult> run() async => result;
}
