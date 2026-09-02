import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/src/rust/api/media.dart' as bridge;

void main() {
  test('maps a valid source without exposing its URI in diagnostics', () {
    const privateUri =
        'http://audio.example.test/source.mp3?vkey=must-not-leak';
    final result = mapBridgeMediaResolution(
      const bridge.MediaResolution(
        source: bridge.ResolvedMediaSource(
          uri: privateUri,
          format: bridge.MediaFormat.mp3,
          quality: bridge.MediaQuality.standard,
          validForSeconds: 7_200,
        ),
      ),
    );

    expect(result.failure, isNull);
    expect(result.source?.uri, Uri.parse(privateUri));
    expect(result.source?.format, PlaybackAudioFormat.mp3);
    expect(result.source?.quality, PlaybackAudioQuality.standard);
    expect(result.source?.validForSeconds, 7_200);
    expect('$result ${result.source}', isNot(contains('must-not-leak')));

    final high = mapBridgeMediaResolution(
      const bridge.MediaResolution(
        source: bridge.ResolvedMediaSource(
          uri: 'https://audio.example.test/high.mp3',
          format: bridge.MediaFormat.mp3,
          quality: bridge.MediaQuality.high,
          validForSeconds: 7_200,
        ),
      ),
    );
    expect(high.source?.quality, PlaybackAudioQuality.high);
  });

  test('maps every Bridge failure without collapsing availability', () {
    final expected = {
      bridge.MediaResolutionFailure.coreUnavailable:
          MediaResolutionFailure.coreUnavailable,
      bridge.MediaResolutionFailure.authenticationRequired:
          MediaResolutionFailure.authenticationRequired,
      bridge.MediaResolutionFailure.credentialRejected:
          MediaResolutionFailure.credentialRejected,
      bridge.MediaResolutionFailure.unavailable:
          MediaResolutionFailure.unavailable,
      bridge.MediaResolutionFailure.network: MediaResolutionFailure.network,
      bridge.MediaResolutionFailure.serviceUnavailable:
          MediaResolutionFailure.serviceUnavailable,
      bridge.MediaResolutionFailure.invalidResponse:
          MediaResolutionFailure.invalidResponse,
      bridge.MediaResolutionFailure.replaced: MediaResolutionFailure.replaced,
      bridge.MediaResolutionFailure.cancelled: MediaResolutionFailure.cancelled,
      bridge.MediaResolutionFailure.alreadyRunning:
          MediaResolutionFailure.alreadyRunning,
    };

    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeMediaResolutionFailure(input), output);
    }
  });

  test('rejects missing conflicting or invalid success fields', () {
    const validSource = bridge.ResolvedMediaSource(
      uri: 'https://audio.example.test/source.mp3',
      format: bridge.MediaFormat.mp3,
      quality: bridge.MediaQuality.standard,
      validForSeconds: 1,
    );
    final invalid = [
      const bridge.MediaResolution(),
      const bridge.MediaResolution(
        source: validSource,
        failure: bridge.MediaResolutionFailure.network,
      ),
      const bridge.MediaResolution(
        source: bridge.ResolvedMediaSource(
          uri: 'file:///private/source.mp3',
          format: bridge.MediaFormat.mp3,
          quality: bridge.MediaQuality.standard,
          validForSeconds: 1,
        ),
      ),
      const bridge.MediaResolution(
        source: bridge.ResolvedMediaSource(
          uri: 'https://audio.example.test/source.mp3',
          format: bridge.MediaFormat.mp3,
          quality: bridge.MediaQuality.standard,
          validForSeconds: 0,
        ),
      ),
    ];

    for (final result in invalid) {
      expect(
        mapBridgeMediaResolution(result).failure,
        MediaResolutionFailure.invalidResponse,
      );
    }
  });

  test('forwards exact opaque identity and cancellation', () async {
    late String providerId;
    late String opaqueTrackId;
    late PlaybackAudioQualityPreference preferredQuality;
    final operation = _ImmediateResolution(
      const MediaResolutionResult(failure: MediaResolutionFailure.cancelled),
    );
    final gateway = RustMediaResolutionGateway(
      preferredQuality: PlaybackAudioQualityPreference.high,
      operationFactory: (provider, opaque, quality) {
        providerId = provider;
        opaqueTrackId = opaque;
        preferredQuality = quality;
        return operation;
      },
    );

    final begun = gateway.beginResolution(
      providerId: 'qq-music',
      opaqueTrackId: 'track:41001:0:1:opaqueMid',
    );
    expect(begun.cancel(), isTrue);
    expect(providerId, 'qq-music');
    expect(opaqueTrackId, 'track:41001:0:1:opaqueMid');
    expect(preferredQuality, PlaybackAudioQualityPreference.high);
    expect(operation.cancelCalls, 1);
  });

  test('uses an updated quality preference for the next resolution', () {
    final qualities = <PlaybackAudioQualityPreference>[];
    final gateway = RustMediaResolutionGateway(
      operationFactory: (_, _, quality) {
        qualities.add(quality);
        return _ImmediateResolution(
          const MediaResolutionResult(
            failure: MediaResolutionFailure.unavailable,
          ),
        );
      },
    );

    gateway.beginResolution(providerId: 'qq-music', opaqueTrackId: 'first');
    gateway.updatePreferredQuality(PlaybackAudioQualityPreference.high);
    gateway.beginResolution(providerId: 'qq-music', opaqueTrackId: 'second');

    expect(qualities, [
      PlaybackAudioQualityPreference.standard,
      PlaybackAudioQualityPreference.high,
    ]);
  });

  test(
    'generic gateway reports rejection without persistence policy',
    () async {
      final rejected = RustMediaResolutionGateway(
        operationFactory: (_, _, _) => _ImmediateResolution(
          const MediaResolutionResult(
            failure: MediaResolutionFailure.credentialRejected,
          ),
        ),
      );
      final rejectedResult = await rejected
          .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
          .run();
      expect(rejectedResult.failure, MediaResolutionFailure.credentialRejected);
    },
  );
}

class _ImmediateResolution implements MediaResolutionOperation {
  _ImmediateResolution(this.result);

  final MediaResolutionResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<MediaResolutionResult> run() async => result;
}
