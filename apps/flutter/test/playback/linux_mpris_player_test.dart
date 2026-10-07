import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/linux_mpris_player.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  late DateTime now;
  late ProjectMprisPlayer player;

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12);
    player = ProjectMprisPlayer(identity: 'flutterustmusic', now: () => now);
    player.updateMediaItem(
      const PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'opaque-track',
        title: 'Track',
        artistNames: ['Artist'],
        durationSeconds: 180,
      ),
      index: 0,
    );
    player.updatePlaybackState(
      ProjectMprisPlaybackState(
        stage: TrackPlaybackStage.playing,
        canPlay: true,
        canPause: true,
        canSeek: true,
        updatePosition: const Duration(seconds: 10),
        updateTime: now,
      ),
    );
  });

  test(
    'projects a live position and publishes a valid MPRIS track id',
    () async {
      now = now.add(const Duration(seconds: 3));

      expect(player.position, const Duration(seconds: 13));
      final position = await _property(player, 'Position');
      expect(position.asInt64(), 13000000);

      final metadata = (await _property(
        player,
        'Metadata',
      )).asStringVariantDict();
      expect(metadata['mpris:trackid'], player.trackId);
      expect(player.trackId.value, startsWith('/com/fura/'));
    },
  );

  test(
    'absolute and relative MPRIS seeks delegate a bounded position',
    () async {
      final absoluteEvent = player.events.first;
      await player.handleMethodCall(
        DBusMethodCall(
          sender: ':test',
          interface: projectMprisPlayerInterface,
          name: 'SetPosition',
          values: [
            DBusObjectPath(player.trackId.value),
            const DBusInt64(42000000),
          ],
        ),
      );
      expect((await absoluteEvent).value, const Duration(seconds: 42));

      final relativeEvent = player.events.first;
      await player.handleMethodCall(
        DBusMethodCall(
          sender: ':test',
          interface: projectMprisPlayerInterface,
          name: 'Seek',
          values: [DBusInt64(5000000)],
        ),
      );
      expect((await relativeEvent).value, const Duration(seconds: 47));

      final ignored = <ProjectMprisEvent>[];
      final subscription = player.events.listen(ignored.add);
      await player.handleMethodCall(
        DBusMethodCall(
          sender: ':test',
          interface: projectMprisPlayerInterface,
          name: 'SetPosition',
          values: [
            DBusObjectPath('/com/fura/flutterustmusic/track/stale'),
            const DBusInt64(1000000),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(ignored, isEmpty);
      await subscription.cancel();
    },
  );

  test('loop and shuffle properties are bidirectional', () async {
    final repeatEvent = player.events.first;
    await player.setProperty(
      projectMprisPlayerInterface,
      'LoopStatus',
      const DBusString('Track'),
    );
    expect((await repeatEvent).value, 'Track');

    final shuffleEvent = player.events.first;
    await player.setProperty(
      projectMprisPlayerInterface,
      'Shuffle',
      const DBusBoolean(true),
    );
    expect((await shuffleEvent).value, isTrue);

    player.updatePlaybackState(
      ProjectMprisPlaybackState(
        stage: TrackPlaybackStage.paused,
        updatePosition: Duration.zero,
        repeatMode: PlaybackRepeatMode.all,
        order: PlaybackOrder.sequential,
        updateTime: now,
      ),
    );
    expect((await _property(player, 'LoopStatus')).asString(), 'Playlist');
    expect((await _property(player, 'Shuffle')).asBoolean(), isFalse);
  });

  tearDown(() async => player.close());

  test(
    'volume is finite and bounded, and closed projection rejects commands',
    () async {
      final values = <ProjectMprisEvent>[];
      final subscription = player.events.listen(values.add);
      expect(
        await player.setProperty(
          projectMprisPlayerInterface,
          'Volume',
          const DBusDouble(double.nan),
        ),
        isA<DBusMethodErrorResponse>(),
      );
      expect(
        await player.setProperty(
          projectMprisPlayerInterface,
          'Volume',
          const DBusDouble(double.infinity),
        ),
        isA<DBusMethodErrorResponse>(),
      );
      expect(player.volume, 1);
      await player.setProperty(
        projectMprisPlayerInterface,
        'Volume',
        const DBusDouble(-1),
      );
      expect(player.volume, 0);
      await player.setProperty(
        projectMprisPlayerInterface,
        'Volume',
        const DBusDouble(2),
      );
      expect(player.volume, 1);
      await Future<void>.delayed(Duration.zero);
      expect(values.map((value) => value.value), [0.0, 1.0]);
      await player.close();
      expect(
        await player.setProperty(
          projectMprisPlayerInterface,
          'Shuffle',
          const DBusBoolean(true),
        ),
        isA<DBusMethodErrorResponse>(),
      );
      expect(player.shuffle, isFalse);
      await subscription.cancel();
    },
  );

  test('clearing the owner removes stale current-track metadata', () async {
    player.clearMediaItem();

    expect(
      (await _property(player, 'Metadata')).asStringVariantDict(),
      isEmpty,
    );
  });
}

Future<DBusValue> _property(ProjectMprisPlayer player, String name) async {
  final response = await player.getProperty(projectMprisPlayerInterface, name);
  expect(response, isA<DBusMethodSuccessResponse>());
  return (response.returnValues.single as DBusVariant).value;
}
