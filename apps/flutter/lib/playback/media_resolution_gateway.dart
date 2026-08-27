import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/media.dart' as bridge;

enum PlaybackAudioFormat { mp3 }

enum PlaybackAudioQuality { standard, high }

enum PlaybackAudioQualityPreference { standard, high }

enum MediaResolutionFailure {
  coreUnavailable,
  authenticationRequired,
  credentialRejected,
  credentialRejectedStorageCleanupFailed,
  unavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  replaced,
  cancelled,
  alreadyRunning,
}

class ResolvedPlaybackSource {
  const ResolvedPlaybackSource({
    required this.uri,
    required this.format,
    required this.quality,
    required this.validForSeconds,
  });

  final Uri uri;
  final PlaybackAudioFormat format;
  final PlaybackAudioQuality quality;
  final int validForSeconds;

  @override
  String toString() =>
      'ResolvedPlaybackSource(uri: [REDACTED], format: ${format.name}, '
      'quality: ${quality.name}, validForSeconds: $validForSeconds)';
}

class MediaResolutionResult {
  const MediaResolutionResult({this.source, this.failure});

  final ResolvedPlaybackSource? source;
  final MediaResolutionFailure? failure;

  @override
  String toString() =>
      'MediaResolutionResult(hasSource: ${source != null}, failure: $failure)';
}

abstract interface class MediaResolutionGateway {
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  });
}

abstract interface class MediaResolutionOperation {
  Future<MediaResolutionResult> run();
  bool cancel();
}

typedef MediaResolutionOperationFactory = MediaResolutionOperation Function(
  String providerId,
  String opaqueTrackId,
  PlaybackAudioQualityPreference preferredQuality,
);

class RustMediaResolutionGateway implements MediaResolutionGateway {
  RustMediaResolutionGateway({
    CredentialVault? credentialVault,
    MediaResolutionOperationFactory? operationFactory,
    this.preferredQuality = PlaybackAudioQualityPreference.standard,
  }) : _operationFactory = operationFactory ?? _beginRustResolution,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final MediaResolutionOperationFactory _operationFactory;
  final PlaybackAudioQualityPreference preferredQuality;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _VaultCleaningMediaResolutionOperation(
    _operationFactory(providerId, opaqueTrackId, preferredQuality),
    _credentialVault,
  );
}

MediaResolutionOperation _beginRustResolution(
  String providerId,
  String opaqueTrackId,
  PlaybackAudioQualityPreference preferredQuality,
) => _RustMediaResolutionOperation(
  bridge.beginQqMusicMediaResolution(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
    preferredQuality: switch (preferredQuality) {
      PlaybackAudioQualityPreference.standard =>
        bridge.QqMusicMediaQualityPreference.standard,
      PlaybackAudioQualityPreference.high =>
        bridge.QqMusicMediaQualityPreference.high,
    },
  ),
);

class _RustMediaResolutionOperation implements MediaResolutionOperation {
  const _RustMediaResolutionOperation(this._handle);

  final bridge.QqMusicMediaResolutionHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<MediaResolutionResult> run() async {
    try {
      return mapBridgeMediaResolution(await _handle.run());
    } on Object {
      return const MediaResolutionResult(
        failure: MediaResolutionFailure.coreUnavailable,
      );
    }
  }
}

class _VaultCleaningMediaResolutionOperation
    implements MediaResolutionOperation {
  const _VaultCleaningMediaResolutionOperation(this._inner, this._vault);

  final MediaResolutionOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<MediaResolutionResult> run() async {
    final result = await _inner.run();
    if (result.failure != MediaResolutionFailure.credentialRejected) {
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

@visibleForTesting
MediaResolutionResult mapBridgeMediaResolution(
  bridge.QqMusicMediaResolution result,
) {
  final bridgeSource = result.source;
  final bridgeFailure = result.failure;
  if (bridgeFailure != null) {
    return MediaResolutionResult(
      failure: bridgeSource == null
          ? mapBridgeMediaResolutionFailure(bridgeFailure)
          : MediaResolutionFailure.invalidResponse,
    );
  }
  if (bridgeSource == null || bridgeSource.validForSeconds <= 0) {
    return const MediaResolutionResult(
      failure: MediaResolutionFailure.invalidResponse,
    );
  }
  final uri = Uri.tryParse(bridgeSource.uri);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !uri.hasAuthority) {
    return const MediaResolutionResult(
      failure: MediaResolutionFailure.invalidResponse,
    );
  }
  return MediaResolutionResult(
    source: ResolvedPlaybackSource(
      uri: uri,
      format: switch (bridgeSource.format) {
        bridge.QqMusicMediaFormat.mp3 => PlaybackAudioFormat.mp3,
      },
      quality: switch (bridgeSource.quality) {
        bridge.QqMusicMediaQuality.standard => PlaybackAudioQuality.standard,
        bridge.QqMusicMediaQuality.high => PlaybackAudioQuality.high,
      },
      validForSeconds: bridgeSource.validForSeconds,
    ),
  );
}

@visibleForTesting
MediaResolutionFailure mapBridgeMediaResolutionFailure(
  bridge.QqMusicMediaResolutionFailure failure,
) => switch (failure) {
  bridge.QqMusicMediaResolutionFailure.coreUnavailable =>
    MediaResolutionFailure.coreUnavailable,
  bridge.QqMusicMediaResolutionFailure.authenticationRequired =>
    MediaResolutionFailure.authenticationRequired,
  bridge.QqMusicMediaResolutionFailure.credentialRejected =>
    MediaResolutionFailure.credentialRejected,
  bridge.QqMusicMediaResolutionFailure.unavailable =>
    MediaResolutionFailure.unavailable,
  bridge.QqMusicMediaResolutionFailure.network =>
    MediaResolutionFailure.network,
  bridge.QqMusicMediaResolutionFailure.serviceUnavailable =>
    MediaResolutionFailure.serviceUnavailable,
  bridge.QqMusicMediaResolutionFailure.invalidResponse =>
    MediaResolutionFailure.invalidResponse,
  bridge.QqMusicMediaResolutionFailure.replaced =>
    MediaResolutionFailure.replaced,
  bridge.QqMusicMediaResolutionFailure.cancelled =>
    MediaResolutionFailure.cancelled,
  bridge.QqMusicMediaResolutionFailure.alreadyRunning =>
    MediaResolutionFailure.alreadyRunning,
};
