import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';

enum LyricStage {
  idle,
  loading,
  content,
  unavailable,
  error,
  authenticationRequired,
  credentialRejected,
}

@immutable
class ActiveLyricSelection {
  const ActiveLyricSelection({
    required this.lineIndex,
    this.segmentIndex,
    this.segmentProgress,
  });

  final int lineIndex;
  final int? segmentIndex;
  final double? segmentProgress;

  @override
  bool operator ==(Object other) =>
      other is ActiveLyricSelection &&
      lineIndex == other.lineIndex &&
      segmentIndex == other.segmentIndex &&
      segmentProgress == other.segmentProgress;

  @override
  int get hashCode => Object.hash(lineIndex, segmentIndex, segmentProgress);

  @override
  String toString() =>
      'ActiveLyricSelection(lineIndex: $lineIndex, '
      'segmentIndex: $segmentIndex, segmentProgress: $segmentProgress)';
}

class LyricController extends ChangeNotifier {
  LyricController(this._gateway);

  final LyricGateway _gateway;

  LyricStage _stage = LyricStage.idle;
  PlaylistTrackSummary? _track;
  SynchronizedLyrics? _lyrics;
  LyricFailure? _failure;
  LyricLoadOperation? _operation;
  int _positionMs = 0;
  ActiveLyricSelection? _activeSelection;
  int _generation = 0;
  bool _disposed = false;

  LyricStage get stage => _stage;
  PlaylistTrackSummary? get track => _track;
  SynchronizedLyrics? get lyrics => _lyrics;
  LyricFailure? get failure => _failure;
  int get positionMs => _positionMs;
  ActiveLyricSelection? get activeSelection => _activeSelection;
  SynchronizedLyricLine? get activeLine {
    final selection = _activeSelection;
    final lines = _lyrics?.lines;
    return selection == null || lines == null
        ? null
        : lines[selection.lineIndex];
  }

  TimedLyricSegment? get activeSegment {
    final selection = _activeSelection;
    final segmentIndex = selection?.segmentIndex;
    return selection == null || segmentIndex == null
        ? null
        : _lyrics!.lines[selection.lineIndex].segments[segmentIndex];
  }

  bool get canRetry =>
      _stage == LyricStage.error &&
      (_failure == LyricFailure.coreUnavailable ||
          _failure == LyricFailure.network ||
          _failure == LyricFailure.serviceUnavailable ||
          _failure == LyricFailure.invalidResponse);

  Future<void> load(PlaylistTrackSummary track) async {
    if (_disposed) return;
    final trackChanged = !_sameTrack(_track, track);
    final generation = ++_generation;
    _operation?.cancel();
    final operation = _gateway.beginLoad(
      providerId: track.providerId,
      opaqueTrackId: track.opaqueId,
    );
    _operation = operation;
    _track = track;
    _lyrics = null;
    _activeSelection = null;
    if (trackChanged) _positionMs = 0;
    _failure = null;
    _stage = LyricStage.loading;
    _notify();

    final result = await operation.run();
    if (identical(_operation, operation)) _operation = null;
    if (!_isCurrent(generation)) return;

    _lyrics = result.lyrics;
    _failure = result.failure;
    if (result.failure == null && result.lyrics != null) {
      _stage = LyricStage.content;
      _activeSelection = selectActiveLyrics(result.lyrics!, _positionMs);
    } else {
      _lyrics = null;
      _failure ??= LyricFailure.invalidResponse;
      _stage = switch (_failure!) {
        LyricFailure.unavailable => LyricStage.unavailable,
        LyricFailure.authenticationRequired ||
        LyricFailure.replaced => LyricStage.authenticationRequired,
        LyricFailure.credentialRejected ||
        LyricFailure.credentialRejectedStorageCleanupFailed =>
          LyricStage.credentialRejected,
        LyricFailure.coreUnavailable ||
        LyricFailure.network ||
        LyricFailure.serviceUnavailable ||
        LyricFailure.invalidResponse ||
        LyricFailure.cancelled ||
        LyricFailure.alreadyRunning => LyricStage.error,
      };
    }
    _notify();
  }

  void retry() {
    final current = _track;
    if (current != null && canRetry) unawaited(load(current));
  }

  void updatePositionMs(int positionMs) {
    if (_disposed || positionMs < 0 || _positionMs == positionMs) return;
    _positionMs = positionMs;
    final nextSelection = _lyrics == null
        ? null
        : selectActiveLyrics(_lyrics!, positionMs);
    if (nextSelection != _activeSelection) {
      _activeSelection = nextSelection;
      _notify();
      return;
    }
    if (nextSelection?.segmentIndex != null) _notify();
  }

  void clear() {
    if (_disposed) return;
    ++_generation;
    _operation?.cancel();
    _operation = null;
    _track = null;
    _lyrics = null;
    _positionMs = 0;
    _activeSelection = null;
    _failure = null;
    _stage = LyricStage.idle;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      ++_generation;
      _operation?.cancel();
      _operation = null;
    }
    super.dispose();
  }
}

bool _sameTrack(PlaylistTrackSummary? left, PlaylistTrackSummary right) =>
    left?.providerId == right.providerId && left?.opaqueId == right.opaqueId;

@visibleForTesting
ActiveLyricSelection? selectActiveLyrics(
  SynchronizedLyrics lyrics,
  int positionMs,
) {
  if (positionMs < 0) return null;
  final lineIndex = _latestStartedIndex(
    lyrics.lines.length,
    (index) => lyrics.lines[index].startMs,
    positionMs,
  );
  if (lineIndex == null) return null;

  final segments = lyrics.lines[lineIndex].segments;
  final segmentIndex = _latestStartedIndex(
    segments.length,
    (index) => segments[index].startMs,
    positionMs,
    include: (index) => segments[index].durationMs > 0,
  );
  if (segmentIndex == null) {
    return ActiveLyricSelection(lineIndex: lineIndex);
  }
  final segment = segments[segmentIndex];
  return ActiveLyricSelection(
    lineIndex: lineIndex,
    segmentIndex: segmentIndex,
    segmentProgress: ((positionMs - segment.startMs) / segment.durationMs)
        .clamp(0.0, 1.0),
  );
}

int? _latestStartedIndex(
  int length,
  int Function(int index) startAt,
  int positionMs, {
  bool Function(int index)? include,
}) {
  int? selected;
  var selectedStart = -1;
  for (var index = 0; index < length; index += 1) {
    final start = startAt(index);
    if (positionMs < start || include?.call(index) == false) continue;
    if (start > selectedStart || start == selectedStart) {
      selected = index;
      selectedStart = start;
    }
  }
  return selected;
}
