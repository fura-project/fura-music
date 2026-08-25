import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/src/rust/api/media.dart' as bridge;

void main() {
  test('maps a valid source without exposing its URI in diagnostics', () {
    const privateUri =
        'http://audio.example.test/source.mp3?vkey=must-not-leak';
    final result = mapBridgeMediaResolution(
      const bridge.QqMusicMediaResolution(
        source: bridge.QqMusicResolvedMediaSource(
          uri: privateUri,
          format: bridge.QqMusicMediaFormat.mp3,
          quality: bridge.QqMusicMediaQuality.standard,
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
  });

  test('maps every Bridge failure without collapsing availability', () {
    final expected = {
      bridge.QqMusicMediaResolutionFailure.coreUnavailable:
          MediaResolutionFailure.coreUnavailable,
      bridge.QqMusicMediaResolutionFailure.authenticationRequired:
          MediaResolutionFailure.authenticationRequired,
      bridge.QqMusicMediaResolutionFailure.credentialRejected:
          MediaResolutionFailure.credentialRejected,
      bridge.QqMusicMediaResolutionFailure.unavailable:
          MediaResolutionFailure.unavailable,
      bridge.QqMusicMediaResolutionFailure.network:
          MediaResolutionFailure.network,
      bridge.QqMusicMediaResolutionFailure.serviceUnavailable:
          MediaResolutionFailure.serviceUnavailable,
      bridge.QqMusicMediaResolutionFailure.invalidResponse:
          MediaResolutionFailure.invalidResponse,
      bridge.QqMusicMediaResolutionFailure.replaced:
          MediaResolutionFailure.replaced,
      bridge.QqMusicMediaResolutionFailure.cancelled:
          MediaResolutionFailure.cancelled,
      bridge.QqMusicMediaResolutionFailure.alreadyRunning:
          MediaResolutionFailure.alreadyRunning,
    };

    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeMediaResolutionFailure(input), output);
    }
  });

  test('rejects missing conflicting or invalid success fields', () {
    const validSource = bridge.QqMusicResolvedMediaSource(
      uri: 'https://audio.example.test/source.mp3',
      format: bridge.QqMusicMediaFormat.mp3,
      quality: bridge.QqMusicMediaQuality.standard,
      validForSeconds: 1,
    );
    final invalid = [
      const bridge.QqMusicMediaResolution(),
      const bridge.QqMusicMediaResolution(
        source: validSource,
        failure: bridge.QqMusicMediaResolutionFailure.network,
      ),
      const bridge.QqMusicMediaResolution(
        source: bridge.QqMusicResolvedMediaSource(
          uri: 'file:///private/source.mp3',
          format: bridge.QqMusicMediaFormat.mp3,
          quality: bridge.QqMusicMediaQuality.standard,
          validForSeconds: 1,
        ),
      ),
      const bridge.QqMusicMediaResolution(
        source: bridge.QqMusicResolvedMediaSource(
          uri: 'https://audio.example.test/source.mp3',
          format: bridge.QqMusicMediaFormat.mp3,
          quality: bridge.QqMusicMediaQuality.standard,
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
    final operation = _ImmediateResolution(
      const MediaResolutionResult(failure: MediaResolutionFailure.cancelled),
    );
    final gateway = RustMediaResolutionGateway(
      credentialVault: _FakeVault(),
      operationFactory: (provider, opaque) {
        providerId = provider;
        opaqueTrackId = opaque;
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
    expect(operation.cancelCalls, 1);
  });

  test('deletes the shared vault only after explicit rejection', () async {
    final rejectedVault = _FakeVault();
    final rejected = RustMediaResolutionGateway(
      credentialVault: rejectedVault,
      operationFactory: (_, _) => _ImmediateResolution(
        const MediaResolutionResult(
          failure: MediaResolutionFailure.credentialRejected,
        ),
      ),
    );
    final rejectedResult = await rejected
        .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(rejectedResult.failure, MediaResolutionFailure.credentialRejected);
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    final transient = RustMediaResolutionGateway(
      credentialVault: transientVault,
      operationFactory: (_, _) => _ImmediateResolution(
        const MediaResolutionResult(failure: MediaResolutionFailure.network),
      ),
    );
    await transient
        .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(transientVault.deleteCalls, 0);

    final failingVault = _FakeVault(
      deleteError: StateError('synthetic vault failure'),
    );
    final cleanupFailure = RustMediaResolutionGateway(
      credentialVault: failingVault,
      operationFactory: (_, _) => _ImmediateResolution(
        const MediaResolutionResult(
          failure: MediaResolutionFailure.credentialRejected,
        ),
      ),
    );
    final cleanupResult = await cleanupFailure
        .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(
      cleanupResult.failure,
      MediaResolutionFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failingVault.deleteCalls, 1);
  });
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

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final deleteError = this.deleteError;
    if (deleteError != null) throw deleteError;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
