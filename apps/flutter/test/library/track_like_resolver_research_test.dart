import 'package:flutter_test/flutter_test.dart';

enum _State { liked, notLiked, unknown }

enum _Resolution { liked, notLiked, unknown, conflictBlocked }

enum _Strategy { fullSnapshot, directStatus, hybrid }

class _Metrics {
  const _Metrics({
    required this.foregroundRequests,
    required this.backgroundRequests,
    required this.currentTargetAuthoritativeAfterLogicalRtts,
    required this.wholeWorkloadAuthoritativeAfterLogicalRtts,
    required this.authoritativeTargets,
    required this.unknownTargets,
  });

  final int foregroundRequests;
  final int backgroundRequests;
  final int currentTargetAuthoritativeAfterLogicalRtts;
  final int wholeWorkloadAuthoritativeAfterLogicalRtts;
  final int authoritativeTargets;
  final int unknownTargets;
}

_Metrics _measure({
  required _Strategy strategy,
  required int targetCount,
  required int snapshotPages,
  required bool snapshotExact,
  required bool currentTargetLiked,
  int currentTargetSnapshotPage = 1,
  int directBatchSize = 20,
}) {
  switch (strategy) {
    case _Strategy.fullSnapshot:
      return _Metrics(
        foregroundRequests: snapshotPages,
        backgroundRequests: 0,
        currentTargetAuthoritativeAfterLogicalRtts: currentTargetLiked
            ? currentTargetSnapshotPage
            : snapshotPages,
        wholeWorkloadAuthoritativeAfterLogicalRtts: snapshotPages,
        authoritativeTargets: snapshotExact ? targetCount : 0,
        unknownTargets: snapshotExact ? 0 : targetCount,
      );
    case _Strategy.directStatus:
      final batches = (targetCount + directBatchSize - 1) ~/ directBatchSize;
      return _Metrics(
        foregroundRequests: batches,
        backgroundRequests: 0,
        currentTargetAuthoritativeAfterLogicalRtts: batches == 0 ? 0 : 1,
        wholeWorkloadAuthoritativeAfterLogicalRtts: batches,
        authoritativeTargets: targetCount,
        unknownTargets: 0,
      );
    case _Strategy.hybrid:
      final batches = (targetCount + directBatchSize - 1) ~/ directBatchSize;
      return _Metrics(
        foregroundRequests: batches,
        backgroundRequests: snapshotPages,
        currentTargetAuthoritativeAfterLogicalRtts: batches == 0 ? 0 : 1,
        wholeWorkloadAuthoritativeAfterLogicalRtts: batches,
        authoritativeTargets: targetCount,
        unknownTargets: 0,
      );
  }
}

_Resolution _reconcile({
  required int snapshotGeneration,
  required int directGeneration,
  required _State snapshot,
  required _State direct,
}) {
  if (snapshotGeneration != directGeneration) return _Resolution.unknown;
  final snapshotAuthoritative = snapshot != _State.unknown;
  final directAuthoritative = direct != _State.unknown;
  if (snapshotAuthoritative && directAuthoritative && snapshot != direct) {
    return _Resolution.conflictBlocked;
  }
  final state = directAuthoritative ? direct : snapshot;
  return switch (state) {
    _State.liked => _Resolution.liked,
    _State.notLiked => _Resolution.notLiked,
    _State.unknown => _Resolution.unknown,
  };
}

void main() {
  test('deterministic workloads keep responsibility costs separate', () {
    for (final targets in [1, 20, 100]) {
      final full = _measure(
        strategy: _Strategy.fullSnapshot,
        targetCount: targets,
        snapshotPages: 12,
        snapshotExact: true,
        currentTargetLiked: true,
        currentTargetSnapshotPage: 7,
      );
      final direct = _measure(
        strategy: _Strategy.directStatus,
        targetCount: targets,
        snapshotPages: 12,
        snapshotExact: true,
        currentTargetLiked: true,
      );
      final hybrid = _measure(
        strategy: _Strategy.hybrid,
        targetCount: targets,
        snapshotPages: 12,
        snapshotExact: true,
        currentTargetLiked: true,
      );

      expect(full.foregroundRequests, 12);
      expect(full.currentTargetAuthoritativeAfterLogicalRtts, 7);
      expect(full.wholeWorkloadAuthoritativeAfterLogicalRtts, 12);
      expect(direct.foregroundRequests, (targets + 19) ~/ 20);
      expect(direct.backgroundRequests, 0);
      expect(direct.currentTargetAuthoritativeAfterLogicalRtts, 1);
      expect(
        direct.wholeWorkloadAuthoritativeAfterLogicalRtts,
        (targets + 19) ~/ 20,
      );
      expect(hybrid.foregroundRequests, direct.foregroundRequests);
      expect(hybrid.backgroundRequests, 12);
      expect(hybrid.currentTargetAuthoritativeAfterLogicalRtts, 1);
      expect(
        hybrid.wholeWorkloadAuthoritativeAfterLogicalRtts,
        (targets + 19) ~/ 20,
      );
    }

    final absent = _measure(
      strategy: _Strategy.fullSnapshot,
      targetCount: 1,
      snapshotPages: 12,
      snapshotExact: true,
      currentTargetLiked: false,
    );
    expect(absent.currentTargetAuthoritativeAfterLogicalRtts, 12);
  });

  test(
    'dirty snapshot and missing direct identity fail closed independently',
    () {
      final inexactSnapshot = _measure(
        strategy: _Strategy.fullSnapshot,
        targetCount: 20,
        snapshotPages: 12,
        snapshotExact: false,
        currentTargetLiked: false,
      );
      expect(inexactSnapshot.authoritativeTargets, 0);
      expect(inexactSnapshot.unknownTargets, 20);

      // A direct MID read cannot help a historical row whose MID is absent;
      // the numeric membership snapshot remains an independent capability.
      expect(
        _reconcile(
          snapshotGeneration: 4,
          directGeneration: 4,
          snapshot: _State.liked,
          direct: _State.unknown,
        ),
        _Resolution.liked,
      );
    },
  );

  test('authoritative disagreement blocks rather than choosing a winner', () {
    for (final conflict in [
      (_State.liked, _State.notLiked),
      (_State.notLiked, _State.liked),
    ]) {
      expect(
        _reconcile(
          snapshotGeneration: 7,
          directGeneration: 7,
          snapshot: conflict.$1,
          direct: conflict.$2,
        ),
        _Resolution.conflictBlocked,
      );
    }
  });

  test('session generation mismatch cannot reuse either resolver result', () {
    expect(
      _reconcile(
        snapshotGeneration: 7,
        directGeneration: 8,
        snapshot: _State.liked,
        direct: _State.liked,
      ),
      _Resolution.unknown,
    );
  });
}
