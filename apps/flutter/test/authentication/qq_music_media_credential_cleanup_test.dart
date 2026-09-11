import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_music_media_credential_cleanup.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';

void main() {
  test(
    'QQ authentication owner deletes only after explicit rejection',
    () async {
      final rejectedVault = _FakeVault();
      final rejected = QqMusicCredentialCleaningMediaResolutionGateway(
        _Gateway(
          const MediaResolutionResult(
            failure: MediaResolutionFailure.credentialRejected,
          ),
        ),
        credentialVault: rejectedVault,
      );

      final rejectedResult = await rejected
          .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
          .run();

      expect(rejectedResult.failure, MediaResolutionFailure.credentialRejected);
      expect(rejectedVault.deleteCalls, 1);

      final transientVault = _FakeVault();
      final transient = QqMusicCredentialCleaningMediaResolutionGateway(
        _Gateway(
          const MediaResolutionResult(failure: MediaResolutionFailure.network),
        ),
        credentialVault: transientVault,
      );
      await transient
          .beginResolution(providerId: 'qq-music', opaqueTrackId: 'opaque')
          .run();
      expect(transientVault.deleteCalls, 0);

      final foreignVault = _FakeVault();
      final foreign = QqMusicCredentialCleaningMediaResolutionGateway(
        _Gateway(
          const MediaResolutionResult(
            failure: MediaResolutionFailure.credentialRejected,
          ),
        ),
        credentialVault: foreignVault,
      );
      await foreign
          .beginResolution(providerId: 'future-source', opaqueTrackId: 'opaque')
          .run();
      expect(foreignVault.deleteCalls, 0);
    },
  );

  test(
    'QQ cleanup failure remains visible and cancellation is forwarded',
    () async {
      final inner = _Operation(
        const MediaResolutionResult(
          failure: MediaResolutionFailure.credentialRejected,
        ),
      );
      final gateway = QqMusicCredentialCleaningMediaResolutionGateway(
        _Gateway.operation(inner),
        credentialVault: _FakeVault(
          deleteError: StateError('synthetic vault failure'),
        ),
      );
      final operation = gateway.beginResolution(
        providerId: 'qq-music',
        opaqueTrackId: 'opaque',
      );

      expect(operation.cancel(), isTrue);
      expect(inner.cancelCalls, 1);
      expect(
        (await operation.run()).failure,
        MediaResolutionFailure.credentialRejectedStorageCleanupFailed,
      );
    },
  );

  test(
    'provider-aware cleanup deletes only the rejected owner vault',
    () async {
      final qqVault = _FakeVault();
      final netEaseVault = _FakeVault();
      final gateway = ProviderCredentialCleaningMediaResolutionGateway(
        _Gateway(
          const MediaResolutionResult(
            failure: MediaResolutionFailure.credentialRejected,
          ),
        ),
        credentialVaults: {
          'qq-music': qqVault,
          'netease-cloud-music': netEaseVault,
        },
      );

      await gateway
          .beginResolution(
            providerId: 'netease-cloud-music',
            opaqueTrackId: 'same-opaque-id',
          )
          .run();
      expect(qqVault.deleteCalls, 0);
      expect(netEaseVault.deleteCalls, 1);

      await gateway
          .beginResolution(
            providerId: 'qq-music',
            opaqueTrackId: 'same-opaque-id',
          )
          .run();
      expect(qqVault.deleteCalls, 1);
      expect(netEaseVault.deleteCalls, 1);
    },
  );

  test('unknown providers cannot delete a built-in credential', () async {
    final qqVault = _FakeVault();
    final netEaseVault = _FakeVault();
    final gateway = ProviderCredentialCleaningMediaResolutionGateway(
      _Gateway(
        const MediaResolutionResult(
          failure: MediaResolutionFailure.credentialRejected,
        ),
      ),
      credentialVaults: {
        'qq-music': qqVault,
        'netease-cloud-music': netEaseVault,
      },
    );

    final result = await gateway
        .beginResolution(providerId: 'future-provider', opaqueTrackId: 'opaque')
        .run();
    expect(result.failure, MediaResolutionFailure.credentialRejected);
    expect(qqVault.deleteCalls, 0);
    expect(netEaseVault.deleteCalls, 0);
  });
}

class _Gateway implements MediaResolutionGateway {
  _Gateway(MediaResolutionResult result) : _operation = _Operation(result);

  const _Gateway.operation(this._operation);

  final MediaResolutionOperation _operation;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _operation;
}

class _Operation implements MediaResolutionOperation {
  _Operation(this.result);

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
