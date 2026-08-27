import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/src/rust/api/music_video.dart' as bridge;

enum TrackMusicVideoQuality { fullHd, hd, sd, low }

class TrackMusicVideoSummary {
  const TrackMusicVideoSummary({
    required this.providerId,
    required this.opaqueId,
    required this.title,
    required this.artistNames,
    required this.sourceUri,
    required this.quality,
    this.artworkUri,
    this.durationSeconds,
  });

  final String providerId;
  final String opaqueId;
  final String title;
  final List<String> artistNames;
  final String? artworkUri;
  final int? durationSeconds;
  final String sourceUri;
  final TrackMusicVideoQuality quality;
}

enum TrackMusicVideoFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  sourceUnavailable,
  cancelled,
  alreadyRunning,
}

class TrackMusicVideoResult {
  const TrackMusicVideoResult({this.musicVideo, this.failure});

  final TrackMusicVideoSummary? musicVideo;
  final TrackMusicVideoFailure? failure;
}

abstract interface class TrackMusicVideoGateway {
  TrackMusicVideoLoadOperation beginLoad({required PlaylistTrackSummary track});
}

abstract interface class TrackMusicVideoLoadOperation {
  Future<TrackMusicVideoResult> run();
  bool cancel();
}

typedef TrackMusicVideoLoadOperationFactory =
    TrackMusicVideoLoadOperation Function(
      String providerId,
      String opaqueTrackId,
    );

class RustTrackMusicVideoGateway implements TrackMusicVideoGateway {
  const RustTrackMusicVideoGateway({
    TrackMusicVideoLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad;

  final TrackMusicVideoLoadOperationFactory _operationFactory;

  @override
  TrackMusicVideoLoadOperation beginLoad({
    required PlaylistTrackSummary track,
  }) => _operationFactory(track.providerId, track.opaqueId);
}

TrackMusicVideoLoadOperation _beginRustLoad(
  String providerId,
  String opaqueTrackId,
) => _RustTrackMusicVideoLoadOperation(
  bridge.beginTrackMusicVideoLoad(
    providerId: providerId,
    opaqueTrackId: opaqueTrackId,
  ),
);

class _RustTrackMusicVideoLoadOperation
    implements TrackMusicVideoLoadOperation {
  const _RustTrackMusicVideoLoadOperation(this._handle);

  final bridge.TrackMusicVideoLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<TrackMusicVideoResult> run() async {
    try {
      return mapBridgeTrackMusicVideo(await _handle.run());
    } on Object {
      return const TrackMusicVideoResult(
        failure: TrackMusicVideoFailure.coreUnavailable,
      );
    }
  }
}

@visibleForTesting
TrackMusicVideoResult mapBridgeTrackMusicVideo(
  bridge.TrackMusicVideoLoad result,
) {
  final failure = result.failure;
  final raw = result.musicVideo;
  if (failure != null) {
    if (raw != null) {
      return const TrackMusicVideoResult(
        failure: TrackMusicVideoFailure.invalidResponse,
      );
    }
    return TrackMusicVideoResult(
      failure: mapBridgeTrackMusicVideoFailure(failure),
    );
  }
  if (raw == null) return const TrackMusicVideoResult();

  final source = Uri.tryParse(raw.sourceUri);
  final artwork = raw.artworkUri == null ? null : Uri.tryParse(raw.artworkUri!);
  if (raw.providerId.trim().isEmpty ||
      raw.opaqueId.trim().isEmpty ||
      raw.title.trim().isEmpty ||
      raw.artistNames.isEmpty ||
      raw.artistNames.any((artist) => artist.trim().isEmpty) ||
      source == null ||
      source.scheme != 'https' ||
      source.host.isEmpty ||
      (artwork != null &&
          (artwork.scheme != 'https' || artwork.host.isEmpty)) ||
      raw.durationSeconds == null ||
      raw.durationSeconds! <= 0) {
    return const TrackMusicVideoResult(
      failure: TrackMusicVideoFailure.invalidResponse,
    );
  }
  return TrackMusicVideoResult(
    musicVideo: TrackMusicVideoSummary(
      providerId: raw.providerId,
      opaqueId: raw.opaqueId,
      title: raw.title,
      artistNames: List.unmodifiable(raw.artistNames),
      artworkUri: raw.artworkUri,
      durationSeconds: raw.durationSeconds,
      sourceUri: raw.sourceUri,
      quality: switch (raw.quality) {
        bridge.TrackMusicVideoQuality.fullHd => TrackMusicVideoQuality.fullHd,
        bridge.TrackMusicVideoQuality.hd => TrackMusicVideoQuality.hd,
        bridge.TrackMusicVideoQuality.sd => TrackMusicVideoQuality.sd,
        bridge.TrackMusicVideoQuality.low => TrackMusicVideoQuality.low,
      },
    ),
  );
}

@visibleForTesting
TrackMusicVideoFailure mapBridgeTrackMusicVideoFailure(
  bridge.TrackMusicVideoLoadFailure failure,
) => switch (failure) {
  bridge.TrackMusicVideoLoadFailure.coreUnavailable =>
    TrackMusicVideoFailure.coreUnavailable,
  bridge.TrackMusicVideoLoadFailure.network => TrackMusicVideoFailure.network,
  bridge.TrackMusicVideoLoadFailure.serviceUnavailable =>
    TrackMusicVideoFailure.serviceUnavailable,
  bridge.TrackMusicVideoLoadFailure.invalidResponse =>
    TrackMusicVideoFailure.invalidResponse,
  bridge.TrackMusicVideoLoadFailure.sourceUnavailable =>
    TrackMusicVideoFailure.sourceUnavailable,
  bridge.TrackMusicVideoLoadFailure.cancelled =>
    TrackMusicVideoFailure.cancelled,
  bridge.TrackMusicVideoLoadFailure.alreadyRunning =>
    TrackMusicVideoFailure.alreadyRunning,
};
