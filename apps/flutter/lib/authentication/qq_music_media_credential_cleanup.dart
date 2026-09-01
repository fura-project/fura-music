import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';

/// QQ authentication-owned cleanup around provider-neutral media resolution.
///
/// The Rust QQ resolver clears its in-process authenticated candidate after an
/// explicit rejection. This adapter keeps the serialized platform copy in
/// sync without teaching the generic playback gateway about QQ persistence.
class QqMusicCredentialCleaningMediaResolutionGateway
    implements MediaResolutionGateway {
  static const _qqMusicProviderId = 'qq-music';

  QqMusicCredentialCleaningMediaResolutionGateway(
    this._inner, {
    CredentialVault? credentialVault,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final MediaResolutionGateway _inner;
  final CredentialVault _credentialVault;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _QqMusicCredentialCleaningMediaResolutionOperation(
    _inner.beginResolution(
      providerId: providerId,
      opaqueTrackId: opaqueTrackId,
    ),
    _credentialVault,
    cleansQqCredential: providerId == _qqMusicProviderId,
  );
}

class _QqMusicCredentialCleaningMediaResolutionOperation
    implements MediaResolutionOperation {
  const _QqMusicCredentialCleaningMediaResolutionOperation(
    this._inner,
    this._vault, {
    required this.cleansQqCredential,
  });

  final MediaResolutionOperation _inner;
  final CredentialVault _vault;
  final bool cleansQqCredential;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<MediaResolutionResult> run() async {
    final result = await _inner.run();
    if (!cleansQqCredential ||
        result.failure != MediaResolutionFailure.credentialRejected) {
      return result;
    }
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const MediaResolutionResult(
        failure: MediaResolutionFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}
