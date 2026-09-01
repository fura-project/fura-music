import 'package:flutter/foundation.dart';
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
    MediaResolutionOperationFactory? operationFactory,
    this.preferredQuality = PlaybackAudioQualityPreference.standard,
  }) : _operationFactory = operationFactory ?? _beginRustResolution;

  final MediaResolutionOperationFactory _operationFactory;
  final PlaybackAudioQualityPreference preferredQuality;

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => _operationFactory(providerId, opaqueTrackId, preferredQuality);
}

MediaResolutionOperation _beginRustResolution(
  String providerId,
  String opaqueTrackId,
  PlaybackAudioQualityPreference preferredQuality,
) => _RustMediaResolutionOperation(
  bridge.beginMediaResolution(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
    preferredQuality: switch (preferredQuality) {
      PlaybackAudioQualityPreference.standard =>
        bridge.MediaQualityPreference.standard,
      PlaybackAudioQualityPreference.high => bridge.MediaQualityPreference.high,
    },
  ),
);

class _RustMediaResolutionOperation implements MediaResolutionOperation {
  const _RustMediaResolutionOperation(this._handle);

  final bridge.MediaResolutionHandle _handle;

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

@visibleForTesting
MediaResolutionResult mapBridgeMediaResolution(bridge.MediaResolution result) {
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
        bridge.MediaFormat.mp3 => PlaybackAudioFormat.mp3,
      },
      quality: switch (bridgeSource.quality) {
        bridge.MediaQuality.standard => PlaybackAudioQuality.standard,
        bridge.MediaQuality.high => PlaybackAudioQuality.high,
      },
      validForSeconds: bridgeSource.validForSeconds,
    ),
  );
}

@visibleForTesting
MediaResolutionFailure mapBridgeMediaResolutionFailure(
  bridge.MediaResolutionFailure failure,
) => switch (failure) {
  bridge.MediaResolutionFailure.coreUnavailable =>
    MediaResolutionFailure.coreUnavailable,
  bridge.MediaResolutionFailure.authenticationRequired =>
    MediaResolutionFailure.authenticationRequired,
  bridge.MediaResolutionFailure.credentialRejected =>
    MediaResolutionFailure.credentialRejected,
  bridge.MediaResolutionFailure.unavailable =>
    MediaResolutionFailure.unavailable,
  bridge.MediaResolutionFailure.network => MediaResolutionFailure.network,
  bridge.MediaResolutionFailure.serviceUnavailable =>
    MediaResolutionFailure.serviceUnavailable,
  bridge.MediaResolutionFailure.invalidResponse =>
    MediaResolutionFailure.invalidResponse,
  bridge.MediaResolutionFailure.replaced => MediaResolutionFailure.replaced,
  bridge.MediaResolutionFailure.cancelled => MediaResolutionFailure.cancelled,
  bridge.MediaResolutionFailure.alreadyRunning =>
    MediaResolutionFailure.alreadyRunning,
};
