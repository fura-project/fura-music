import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_engine.dart';
import 'package:flutterustmusic/music_video/track_music_video_gateway.dart';
import 'package:flutterustmusic/music_video/track_music_video_surface.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/foreground_playback_controller.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/queue_playback_controller.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';
import 'package:flutterustmusic/theme/material_theme.dart';

void main() {
  testWidgets('compact surface keeps no-MV state and close reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = _playback();
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      _TestApp(
        playback: playback,
        gateway: const _ImmediateGateway(TrackMusicVideoResult()),
        engine: const _UnusedVideoEngine(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-mv')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('track-music-video-compact-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('track-music-video-unavailable')),
      findsOneWidget,
    );
    expect(find.text('No music video for this Track'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('track-music-video-close')));
    await tester.pumpAndSettle();
    expect(find.text('Music video'), findsNothing);
  });

  testWidgets('wide surface exposes project controls and metadata', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = _playback();
    addTearDown(playback.dispose);
    final session = _FakeVideoSession();

    await tester.pumpWidget(
      _TestApp(
        playback: playback,
        gateway: const _ImmediateGateway(
          TrackMusicVideoResult(musicVideo: _video),
        ),
        engine: _FakeVideoEngine(session),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-mv')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('track-music-video-wide-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('track-music-video-player')),
      findsOneWidget,
    );
    expect(find.text('Track one MV'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('track-music-video-play-pause')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('track-music-video-progress')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('track-music-video-play-pause')),
    );
    await tester.pump();
    expect(session.pauseCalls, 1);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.playback,
    required this.gateway,
    required this.engine,
  });

  final QueuePlaybackController playback;
  final TrackMusicVideoGateway gateway;
  final TrackMusicVideoEngine engine;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: MusicMaterialTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-mv'),
            onPressed: () => showTrackMusicVideoSurface(
              context: context,
              gateway: gateway,
              engine: engine,
              track: track,
              playbackController: playback,
            ),
            child: const Text('Open MV'),
          ),
        ),
      ),
    ),
  );
}

const track = PlaylistTrackSummary(
  providerId: 'qq-music',
  opaqueId: 'track:one',
  title: 'Track one',
  artistNames: ['Artist'],
  durationSeconds: 180,
);

const _video = TrackMusicVideoSummary(
  providerId: 'qq-music',
  opaqueId: 'mv:one',
  title: 'Track one MV',
  artistNames: ['Artist'],
  sourceUri: 'https://media.example.invalid/mv.mp4',
  quality: TrackMusicVideoQuality.hd,
  durationSeconds: 120,
);

class _ImmediateGateway implements TrackMusicVideoGateway {
  const _ImmediateGateway(this.result);

  final TrackMusicVideoResult result;

  @override
  TrackMusicVideoLoadOperation beginLoad({
    required PlaylistTrackSummary track,
  }) => _ImmediateOperation(result);
}

class _ImmediateOperation implements TrackMusicVideoLoadOperation {
  const _ImmediateOperation(this.result);

  final TrackMusicVideoResult result;

  @override
  Future<TrackMusicVideoResult> run() async => result;
  @override
  bool cancel() => true;
}

class _FakeVideoEngine implements TrackMusicVideoEngine {
  const _FakeVideoEngine(this.session);

  final _FakeVideoSession session;

  @override
  TrackMusicVideoSession createSession() => session;
}

class _UnusedVideoEngine implements TrackMusicVideoEngine {
  const _UnusedVideoEngine();

  @override
  TrackMusicVideoSession createSession() => throw StateError('not used');
}

class _FakeVideoSession extends TrackMusicVideoSession {
  TrackMusicVideoSessionStage _stage = TrackMusicVideoSessionStage.loading;
  int pauseCalls = 0;

  @override
  TrackMusicVideoSessionStage get stage => _stage;
  @override
  Duration get position => const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(minutes: 2);

  @override
  Future<void> open(String uri) async {
    _stage = TrackMusicVideoSessionStage.playing;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _stage = TrackMusicVideoSessionStage.paused;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    _stage = TrackMusicVideoSessionStage.playing;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Widget buildVideo({Key? key}) => ColoredBox(key: key, color: Colors.black);
}

QueuePlaybackController _playback() => QueuePlaybackController(
  const _QueueGateway(),
  TrackPlaybackController(
    const _UnusedMediaGateway(),
    ForegroundPlaybackController(const _UnusedAudioEngine()),
  ),
);

class _QueueGateway implements PlaybackQueueGateway {
  const _QueueGateway();

  PlaybackQueueResult get _current => PlaybackQueueResult(
    snapshot: PlaybackQueueSnapshot(
      tracks: const [track],
      currentIndex: 0,
      hasPrevious: false,
      hasNext: false,
    ),
  );

  @override
  PlaybackQueueResult snapshot() => _current;
  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) => _current;
  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) => _current;
  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => throw UnimplementedError();
  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) =>
      throw UnimplementedError();
  @override
  PlaybackQueueResult select(int index) => throw UnimplementedError();
  @override
  PlaybackQueueResult advance() => throw UnimplementedError();
  @override
  PlaybackQueueResult rewind() => throw UnimplementedError();
  @override
  PlaybackQueueResult completeCurrent() => throw UnimplementedError();
  @override
  PlaybackQueueResult remove(int index) => throw UnimplementedError();
  @override
  PlaybackQueueResult clear() => throw UnimplementedError();
}

class _UnusedMediaGateway implements MediaResolutionGateway {
  const _UnusedMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => throw StateError('not used');
}

class _UnusedAudioEngine implements ForegroundAudioEngine {
  const _UnusedAudioEngine();

  @override
  Future<ForegroundAudioSession> loadRemote(Uri source) =>
      throw StateError('not used');
}
