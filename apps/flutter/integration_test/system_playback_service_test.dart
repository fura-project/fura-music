import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/linux_mpris_audio_service.dart';
import 'package:flutterustmusic/playback/media_kit_foreground_audio_engine.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/playback_stack_experiment.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('initializes the host system media session', (tester) async {
    final selection = PlaybackStackSelection.current();
    final host = await initializeAppPlaybackHost(
      playbackQueueGateway: _MemoryQueueGateway(),
      mediaResolutionGateway: const _NeverMediaGateway(),
      lyricGateway: const _NeverLyricGateway(),
      audioEngine: switch (selection.audioEngine) {
        MusicAudioEngineKind.audioplayers =>
          AudioplayersForegroundAudioEngine(),
        MusicAudioEngineKind.mediaKit => MediaKitForegroundAudioEngine(),
      },
      systemMediaEdge: selection.systemMediaEdge,
    );

    expect(host, isA<AudioServiceAppPlaybackHost>());
    expect(host.controller, isNotNull);
    expect(selection.usesProjectLinuxMpris, isTrue);

    final client = DBusClient.session();
    final remote = DBusRemoteObject(
      client,
      name: projectMprisServiceName('dev.axiaobo.flutterustmusic.playback'),
      path: DBusObjectPath(projectMprisObjectPath),
    );
    expect(
      (await remote.getProperty(
        'org.mpris.MediaPlayer2',
        'Identity',
        signature: DBusSignature('s'),
      )).asString(),
      'fura music playback',
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'Position',
        signature: DBusSignature('x'),
      )).asInt64(),
      0,
    );
    final playerProperties = await remote.getAllProperties(
      projectMprisPlayerInterface,
    );
    expect(
      playerProperties.keys,
      containsAll(['Position', 'LoopStatus', 'Shuffle', 'CanSeek']),
    );

    await remote.setProperty(
      projectMprisPlayerInterface,
      'LoopStatus',
      const DBusString('Track'),
    );
    await remote.setProperty(
      projectMprisPlayerInterface,
      'Shuffle',
      const DBusBoolean(true),
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'LoopStatus',
      )).asString(),
      'Track',
    );
    expect(
      (await remote.getProperty(
        projectMprisPlayerInterface,
        'Shuffle',
      )).asBoolean(),
      isTrue,
    );

    await host.dispose();
    await client.close();
  });
}

class _MemoryQueueGateway implements PlaybackQueueGateway {
  PlaybackQueueSnapshot _snapshot = PlaybackQueueSnapshot.empty();

  @override
  PlaybackQueueResult snapshot() => PlaybackQueueResult(snapshot: _snapshot);

  @override
  PlaybackQueueResult setOrder(PlaybackOrder order) {
    _snapshot = _copy(order: order);
    return snapshot();
  }

  @override
  PlaybackQueueResult setRepeatMode(PlaybackRepeatMode repeatMode) {
    _snapshot = _copy(repeatMode: repeatMode);
    return snapshot();
  }

  PlaybackQueueSnapshot _copy({
    PlaybackOrder? order,
    PlaybackRepeatMode? repeatMode,
  }) => PlaybackQueueSnapshot(
    tracks: _snapshot.tracks,
    currentIndex: _snapshot.currentIndex,
    hasPrevious: _snapshot.hasPrevious,
    hasNext: _snapshot.hasNext,
    order: order ?? _snapshot.order,
    repeatMode: repeatMode ?? _snapshot.repeatMode,
  );

  @override
  PlaybackQueueResult replace({
    required List<PlaylistTrackSummary> tracks,
    required int? currentIndex,
  }) => snapshot();

  @override
  PlaybackQueueResult push(PlaylistTrackSummary track) => snapshot();

  @override
  PlaybackQueueResult select(int index) => snapshot();

  @override
  PlaybackQueueResult advance() => snapshot();

  @override
  PlaybackQueueResult rewind() => snapshot();

  @override
  PlaybackQueueResult completeCurrent() => snapshot();

  @override
  PlaybackQueueResult remove(int index) => snapshot();

  @override
  PlaybackQueueResult clear() => snapshot();
}

class _NeverMediaGateway implements MediaResolutionGateway {
  const _NeverMediaGateway();

  @override
  MediaResolutionOperation beginResolution({
    required String providerId,
    required String opaqueTrackId,
  }) => throw UnsupportedError('No media is loaded by this integration test.');
}

class _NeverLyricGateway implements LyricGateway {
  const _NeverLyricGateway();

  @override
  LyricLoadOperation beginLoad({
    required String providerId,
    required String opaqueTrackId,
  }) =>
      throw UnsupportedError('No lyrics are loaded by this integration test.');
}
