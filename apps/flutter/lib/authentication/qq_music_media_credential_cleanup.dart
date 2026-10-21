import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/qq_session_continuation.dart';
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
    this.sessionContinuation,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final MediaResolutionGateway _inner;
  final CredentialVault _credentialVault;
  final QqSessionContinuationCoordinator? sessionContinuation;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    MediaResolutionOperation createOperation() => _inner.beginResolution(
      providerId: providerId,
      opaqueTrackId: opaqueTrackId,
    );
    final operation = createOperation();
    if (providerId != _qqMusicProviderId) return operation;
    return _ProviderCredentialCleaningMediaResolutionOperation(
      operation,
      _credentialVault,
      retryFactory: createOperation,
      continuation: sessionContinuation,
    );
  }
}

/// Deletes only the credential namespace owned by the provider whose media
/// request was explicitly rejected. Unknown providers never trigger cleanup.
class ProviderCredentialCleaningMediaResolutionGateway
    implements MediaResolutionGateway {
  ProviderCredentialCleaningMediaResolutionGateway(
    this._inner, {
    required Map<String, CredentialVault> credentialVaults,
    this.qqSessionContinuation,
  }) : _credentialVaults = Map.unmodifiable(credentialVaults);

  final MediaResolutionGateway _inner;
  final Map<String, CredentialVault> _credentialVaults;
  final QqSessionContinuationCoordinator? qqSessionContinuation;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) {
    MediaResolutionOperation createOperation() => _inner.beginResolution(
      providerId: providerId,
      opaqueTrackId: opaqueTrackId,
    );
    final operation = createOperation();
    final vault = _credentialVaults[providerId];
    return vault == null
        ? operation
        : _ProviderCredentialCleaningMediaResolutionOperation(
            operation,
            vault,
            retryFactory: createOperation,
            continuation: providerId == 'qq-music'
                ? qqSessionContinuation
                : null,
          );
  }
}

class _ProviderCredentialCleaningMediaResolutionOperation
    implements MediaResolutionOperation {
  _ProviderCredentialCleaningMediaResolutionOperation(
    this._inner,
    this._vault, {
    this.retryFactory,
    this.continuation,
  });

  MediaResolutionOperation _inner;
  final CredentialVault _vault;
  final MediaResolutionOperation Function()? retryFactory;
  final QqSessionContinuationCoordinator? continuation;
  bool _cancelled = false;

  @override
  bool cancel() {
    _cancelled = true;
    return _inner.cancel();
  }

  @override
  Future<MediaResolutionResult> run() async {
    final result = await _inner.run();
    if (result.failure != MediaResolutionFailure.credentialRejected) {
      return result;
    }
    if (continuation != null && retryFactory != null) {
      final outcome = await continuation!.continueAfterReadRejection();
      if (outcome == QqSessionContinuationResult.continued && !_cancelled) {
        _inner = retryFactory!();
        return _inner.run();
      }
      if (outcome != QqSessionContinuationResult.reauthenticationRequired) {
        return const MediaResolutionResult(
          failure: MediaResolutionFailure.serviceUnavailable,
        );
      }
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
