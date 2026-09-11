import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/src/rust/api/media.dart' as media;
import 'package:flutterustmusic/src/rust/api/search.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

const _liveTestsEnabled = bool.fromEnvironment('QQMUSIC_LIVE_TESTS');
const _playbackLiveTestsEnabled = bool.fromEnvironment(
  'QQMUSIC_ANDROID_PLAYBACK_LIVE_TESTS',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('loads one anonymous QQ Music search page over Android HTTPS', (
    _,
  ) async {
    final result = await beginQqMusicTrackSearchPageLoad(
      query: '周杰伦',
      page: 1,
      size: 1,
    ).run();

    expect(
      result.failure,
      isNull,
      reason:
          'Android must initialize its rustls platform verifier before '
          'the first QQ Music HTTPS request.',
    );
    expect(result.items, isNotEmpty);
  }, skip: !Platform.isAndroid || !_liveTestsEnabled);

  testWidgets(
    'resolves HTTPS and advances one anonymous Android playback session',
    (tester) async {
      final search = await beginQqMusicTrackSearchPageLoad(
        query: 'Take me hand',
        page: 1,
        size: 8,
      ).run();
      expect(search.failure, isNull);

      media.ResolvedMediaSource? source;
      for (final item in search.items) {
        final resolution = media.beginMediaResolution(
          providerId: item.track.providerId,
          opaqueTrackId: item.track.opaqueId,
          preferredQuality: media.MediaQualityPreference.standard,
        );
        try {
          final outcome = await resolution.run().timeout(
            const Duration(seconds: 10),
          );
          if (outcome.source != null) {
            source = outcome.source;
            break;
          }
        } on TimeoutException {
          resolution.cancel();
        }
      }

      expect(
        source != null,
        isTrue,
        reason:
            'The bounded anonymous sample did not expose a playable source.',
      );
      final resolved = source!;
      final uri = Uri.tryParse(resolved.uri);
      expect(
        uri != null && uri.scheme == 'https' && uri.hasAuthority,
        isTrue,
        reason: 'QQ playback must not expose a cleartext or malformed source.',
      );

      final engine = AudioplayersForegroundAudioEngine();
      ForegroundAudioSession? session;
      try {
        session = await engine.loadRemote(
          uri!,
          format: switch (resolved.format) {
            media.MediaFormat.mp3 => ForegroundAudioFormat.mp3,
            media.MediaFormat.m4A => ForegroundAudioFormat.m4a,
            media.MediaFormat.flac => ForegroundAudioFormat.flac,
          },
        );
        await session.setVolume(0);
        final progressed = session.positionMs.firstWhere(
          (positionMs) => positionMs > 0,
        );
        await session.play();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          await progressed.timeout(const Duration(seconds: 10)),
          greaterThan(0),
        );
      } finally {
        await session?.stop();
        await session?.dispose();
      }
    },
    skip: !Platform.isAndroid || !_playbackLiveTestsEnabled,
  );
}
