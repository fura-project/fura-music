import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/src/rust/api/lyrics.dart' as bridge;

enum LyricFailure {
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

class TimedLyricSegment {
  const TimedLyricSegment({
    required this.text,
    required this.startMs,
    required this.durationMs,
  });

  final String text;
  final int startMs;
  final int durationMs;
  int get endMs => startMs + durationMs;

  @override
  String toString() =>
      'TimedLyricSegment(text: [REDACTED], startMs: $startMs, '
      'durationMs: $durationMs)';
}

class SynchronizedLyricLine {
  SynchronizedLyricLine({
    required this.text,
    required this.startMs,
    required this.durationMs,
    required List<TimedLyricSegment> segments,
    this.translation,
    this.romanization,
  }) : segments = List.unmodifiable(segments);

  final String text;
  final int startMs;
  final int durationMs;
  final List<TimedLyricSegment> segments;
  final String? translation;
  final String? romanization;
  int get endMs => startMs + durationMs;

  @override
  String toString() =>
      'SynchronizedLyricLine(text: [REDACTED], startMs: $startMs, '
      'durationMs: $durationMs, segmentCount: ${segments.length}, '
      'hasTranslation: ${translation != null}, '
      'hasRomanization: ${romanization != null})';
}

class SynchronizedLyrics {
  SynchronizedLyrics(List<SynchronizedLyricLine> lines)
    : lines = List.unmodifiable(lines);

  final List<SynchronizedLyricLine> lines;
  bool get hasWordTiming => lines.any((line) => line.segments.isNotEmpty);

  @override
  String toString() =>
      'SynchronizedLyrics(lineCount: ${lines.length}, '
      'hasWordTiming: $hasWordTiming)';
}

class LyricLoadResult {
  const LyricLoadResult({this.lyrics, this.failure});

  final SynchronizedLyrics? lyrics;
  final LyricFailure? failure;

  @override
  String toString() =>
      'LyricLoadResult(hasLyrics: ${lyrics != null}, failure: $failure)';
}

abstract interface class LyricGateway {
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  });
}

abstract interface class LyricLoadOperation {
  Future<LyricLoadResult> run();
  bool cancel();
}

typedef LyricLoadOperationFactory = LyricLoadOperation Function(
  String providerId,
  String opaqueTrackId,
);

class RustLyricGateway implements LyricGateway {
  RustLyricGateway({
    CredentialVault? credentialVault,
    LyricLoadOperationFactory? operationFactory,
  }) : _operationFactory = operationFactory ?? _beginRustLoad,
       _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       );

  final CredentialVault _credentialVault;
  final LyricLoadOperationFactory _operationFactory;

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) => _VaultCleaningLyricLoadOperation(
    _operationFactory(providerId, opaqueTrackId),
    _credentialVault,
  );
}

LyricLoadOperation _beginRustLoad(String providerId, String opaqueTrackId) =>
    _RustLyricLoadOperation(
      bridge.beginQqMusicLyricLoad(
        providerId: providerId,
        opaqueTrackId: opaqueTrackId,
      ),
    );

class _RustLyricLoadOperation implements LyricLoadOperation {
  const _RustLyricLoadOperation(this._handle);

  final bridge.QqMusicLyricLoadHandle _handle;

  @override
  bool cancel() => _handle.cancel();

  @override
  Future<LyricLoadResult> run() async {
    try {
      return mapBridgeLyricLoad(await _handle.run());
    } on Object {
      return const LyricLoadResult(failure: LyricFailure.coreUnavailable);
    }
  }
}

class _VaultCleaningLyricLoadOperation implements LyricLoadOperation {
  const _VaultCleaningLyricLoadOperation(this._inner, this._vault);

  final LyricLoadOperation _inner;
  final CredentialVault _vault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<LyricLoadResult> run() async {
    final result = await _inner.run();
    if (result.failure != LyricFailure.credentialRejected) return result;
    try {
      await _vault.delete();
      return result;
    } on Object {
      return const LyricLoadResult(
        failure: LyricFailure.credentialRejectedStorageCleanupFailed,
      );
    }
  }
}

@visibleForTesting
LyricLoadResult mapBridgeLyricLoad(bridge.QqMusicLyricLoad result) {
  final bridgeLyrics = result.lyrics;
  final bridgeFailure = result.failure;
  if (bridgeFailure != null) {
    return LyricLoadResult(
      failure: bridgeLyrics == null
          ? mapBridgeLyricFailure(bridgeFailure)
          : LyricFailure.invalidResponse,
    );
  }
  if (bridgeLyrics == null || bridgeLyrics.lines.isEmpty) {
    return const LyricLoadResult(failure: LyricFailure.invalidResponse);
  }

  final lines = <SynchronizedLyricLine>[];
  for (final line in bridgeLyrics.lines) {
    if (!_validTiming(line.startMs, line.durationMs) ||
        line.translation?.isEmpty == true ||
        line.romanization?.isEmpty == true) {
      return const LyricLoadResult(failure: LyricFailure.invalidResponse);
    }
    final segments = <TimedLyricSegment>[];
    for (final segment in line.segments) {
      if (!_validTiming(segment.startMs, segment.durationMs)) {
        return const LyricLoadResult(failure: LyricFailure.invalidResponse);
      }
      segments.add(
        TimedLyricSegment(
          text: segment.text,
          startMs: segment.startMs,
          durationMs: segment.durationMs,
        ),
      );
    }
    lines.add(
      SynchronizedLyricLine(
        text: line.text,
        startMs: line.startMs,
        durationMs: line.durationMs,
        segments: List.unmodifiable(segments),
        translation: line.translation,
        romanization: line.romanization,
      ),
    );
  }

  return LyricLoadResult(lyrics: SynchronizedLyrics(List.unmodifiable(lines)));
}

bool _validTiming(int startMs, int durationMs) {
  const maxU32 = 0xffffffff;
  return startMs >= 0 &&
      durationMs >= 0 &&
      startMs <= maxU32 &&
      durationMs <= maxU32 &&
      startMs + durationMs <= maxU32;
}

@visibleForTesting
LyricFailure mapBridgeLyricFailure(bridge.QqMusicLyricLoadFailure failure) =>
    switch (failure) {
      bridge.QqMusicLyricLoadFailure.coreUnavailable =>
        LyricFailure.coreUnavailable,
      bridge.QqMusicLyricLoadFailure.authenticationRequired =>
        LyricFailure.authenticationRequired,
      bridge.QqMusicLyricLoadFailure.credentialRejected =>
        LyricFailure.credentialRejected,
      bridge.QqMusicLyricLoadFailure.unavailable => LyricFailure.unavailable,
      bridge.QqMusicLyricLoadFailure.network => LyricFailure.network,
      bridge.QqMusicLyricLoadFailure.serviceUnavailable =>
        LyricFailure.serviceUnavailable,
      bridge.QqMusicLyricLoadFailure.invalidResponse =>
        LyricFailure.invalidResponse,
      bridge.QqMusicLyricLoadFailure.replaced => LyricFailure.replaced,
      bridge.QqMusicLyricLoadFailure.cancelled => LyricFailure.cancelled,
      bridge.QqMusicLyricLoadFailure.alreadyRunning =>
        LyricFailure.alreadyRunning,
    };
