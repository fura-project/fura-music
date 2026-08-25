import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/src/rust/api/lyrics.dart' as bridge;

void main() {
  test('maps synchronized lines and segments with redacted diagnostics', () {
    final result = mapBridgeLyricLoad(_validBridgeLoad());

    expect(result.failure, isNull);
    final lyrics = result.lyrics!;
    expect(lyrics.lines, hasLength(1));
    expect(lyrics.hasWordTiming, isTrue);
    final line = lyrics.lines.single;
    expect(line.text, 'private original');
    expect(line.startMs, 1000);
    expect(line.durationMs, 800);
    expect(line.endMs, 1800);
    expect(line.translation, 'private translation');
    expect(line.romanization, 'private romanization');
    expect(line.segments, hasLength(1));
    expect(line.segments.single.text, 'private segment');
    expect(line.segments.single.endMs, 1400);
    expect(() => lyrics.lines.clear(), throwsUnsupportedError);
    expect(() => line.segments.clear(), throwsUnsupportedError);
    expect(
      '$result $lyrics $line ${line.segments.single}',
      isNot(contains('private')),
    );
  });

  test('maps every Bridge failure without collapsing availability', () {
    final expected = {
      bridge.QqMusicLyricLoadFailure.coreUnavailable:
          LyricFailure.coreUnavailable,
      bridge.QqMusicLyricLoadFailure.authenticationRequired:
          LyricFailure.authenticationRequired,
      bridge.QqMusicLyricLoadFailure.credentialRejected:
          LyricFailure.credentialRejected,
      bridge.QqMusicLyricLoadFailure.unavailable: LyricFailure.unavailable,
      bridge.QqMusicLyricLoadFailure.network: LyricFailure.network,
      bridge.QqMusicLyricLoadFailure.serviceUnavailable:
          LyricFailure.serviceUnavailable,
      bridge.QqMusicLyricLoadFailure.invalidResponse:
          LyricFailure.invalidResponse,
      bridge.QqMusicLyricLoadFailure.replaced: LyricFailure.replaced,
      bridge.QqMusicLyricLoadFailure.cancelled: LyricFailure.cancelled,
      bridge.QqMusicLyricLoadFailure.alreadyRunning:
          LyricFailure.alreadyRunning,
    };

    for (final MapEntry(key: input, value: output) in expected.entries) {
      expect(mapBridgeLyricFailure(input), output);
    }
  });

  test('rejects missing conflicting and invalid lyric result shapes', () {
    final validLyrics = _validBridgeLoad().lyrics!;
    final invalid = [
      const bridge.QqMusicLyricLoad(),
      bridge.QqMusicLyricLoad(
        lyrics: validLyrics,
        failure: bridge.QqMusicLyricLoadFailure.network,
      ),
      const bridge.QqMusicLyricLoad(
        lyrics: bridge.QqMusicSynchronizedLyrics(lines: []),
      ),
      const bridge.QqMusicLyricLoad(
        lyrics: bridge.QqMusicSynchronizedLyrics(
          lines: [
            bridge.QqMusicSynchronizedLyricLine(
              text: '',
              startMs: -1,
              durationMs: 0,
              segments: [],
            ),
          ],
        ),
      ),
      const bridge.QqMusicLyricLoad(
        lyrics: bridge.QqMusicSynchronizedLyrics(
          lines: [
            bridge.QqMusicSynchronizedLyricLine(
              text: '',
              startMs: 0xffffffff,
              durationMs: 1,
              segments: [],
            ),
          ],
        ),
      ),
      const bridge.QqMusicLyricLoad(
        lyrics: bridge.QqMusicSynchronizedLyrics(
          lines: [
            bridge.QqMusicSynchronizedLyricLine(
              text: '',
              startMs: 0,
              durationMs: 1,
              segments: [],
              translation: '',
            ),
          ],
        ),
      ),
      const bridge.QqMusicLyricLoad(
        lyrics: bridge.QqMusicSynchronizedLyrics(
          lines: [
            bridge.QqMusicSynchronizedLyricLine(
              text: '',
              startMs: 0,
              durationMs: 1,
              segments: [
                bridge.QqMusicTimedLyricSegment(
                  text: '',
                  startMs: 0,
                  durationMs: -1,
                ),
              ],
            ),
          ],
        ),
      ),
    ];

    for (final result in invalid) {
      expect(mapBridgeLyricLoad(result).failure, LyricFailure.invalidResponse);
    }
  });

  test('forwards exact opaque identity and cancellation', () {
    late String providerId;
    late String opaqueTrackId;
    final operation = _ImmediateOperation(
      const LyricLoadResult(failure: LyricFailure.cancelled),
    );
    final gateway = RustLyricGateway(
      credentialVault: _FakeVault(),
      operationFactory: (provider, opaque) {
        providerId = provider;
        opaqueTrackId = opaque;
        return operation;
      },
    );

    final begun = gateway.beginLoad(
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
    final rejected = RustLyricGateway(
      credentialVault: rejectedVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const LyricLoadResult(failure: LyricFailure.credentialRejected),
      ),
    );
    final rejectedResult = await rejected
        .beginLoad(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(rejectedResult.failure, LyricFailure.credentialRejected);
    expect(rejectedVault.deleteCalls, 1);

    final transientVault = _FakeVault();
    final transient = RustLyricGateway(
      credentialVault: transientVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const LyricLoadResult(failure: LyricFailure.network),
      ),
    );
    await transient
        .beginLoad(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(transientVault.deleteCalls, 0);

    final failingVault = _FakeVault(
      deleteError: StateError('synthetic vault failure'),
    );
    final cleanupFailure = RustLyricGateway(
      credentialVault: failingVault,
      operationFactory: (_, _) => _ImmediateOperation(
        const LyricLoadResult(failure: LyricFailure.credentialRejected),
      ),
    );
    final cleanupResult = await cleanupFailure
        .beginLoad(providerId: 'qq-music', opaqueTrackId: 'opaque')
        .run();
    expect(
      cleanupResult.failure,
      LyricFailure.credentialRejectedStorageCleanupFailed,
    );
    expect(failingVault.deleteCalls, 1);
  });
}

bridge.QqMusicLyricLoad _validBridgeLoad() => const bridge.QqMusicLyricLoad(
  lyrics: bridge.QqMusicSynchronizedLyrics(
    lines: [
      bridge.QqMusicSynchronizedLyricLine(
        text: 'private original',
        startMs: 1000,
        durationMs: 800,
        segments: [
          bridge.QqMusicTimedLyricSegment(
            text: 'private segment',
            startMs: 1000,
            durationMs: 400,
          ),
        ],
        translation: 'private translation',
        romanization: 'private romanization',
      ),
    ],
  ),
);

class _ImmediateOperation implements LyricLoadOperation {
  _ImmediateOperation(this.result);

  final LyricLoadResult result;
  int cancelCalls = 0;

  @override
  bool cancel() {
    cancelCalls += 1;
    return true;
  }

  @override
  Future<LyricLoadResult> run() async => result;
}

class _FakeVault implements CredentialVault {
  _FakeVault({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;

  @override
  Future<void> delete() async {
    deleteCalls += 1;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  Future<Uint8List?> read() async => null;

  @override
  Future<void> write(Uint8List secretBytes) async {}
}
