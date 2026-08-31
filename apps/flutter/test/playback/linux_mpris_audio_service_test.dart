import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/linux_mpris_audio_service.dart';

void main() {
  late DateTime now;
  late ProjectMprisPlayer player;

  setUp(() {
    now = DateTime.utc(2026, 8, 31, 12);
    player = ProjectMprisPlayer(identity: 'flutterustmusic', now: () => now);
    player.updateMediaItem(
      const MediaItemMessage(
        id: 'qq-music:opaque-track:0',
        title: 'Track',
        artist: 'Artist',
        duration: Duration(minutes: 3),
      ),
    );
    player.updatePlaybackState(
      PlaybackStateMessage(
        processingState: AudioProcessingStateMessage.ready,
        playing: true,
        systemActions: const {
          MediaActionMessage.seek,
          MediaActionMessage.setRepeatMode,
          MediaActionMessage.setShuffleMode,
        },
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
      expect(player.trackId.value, startsWith('/dev/axiaobo/'));
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
            DBusObjectPath('/dev/axiaobo/flutterustmusic/track/stale'),
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
      PlaybackStateMessage(
        processingState: AudioProcessingStateMessage.ready,
        repeatMode: AudioServiceRepeatModeMessage.all,
        shuffleMode: AudioServiceShuffleModeMessage.none,
        updateTime: now,
      ),
    );
    expect((await _property(player, 'LoopStatus')).asString(), 'Playlist');
    expect((await _property(player, 'Shuffle')).asBoolean(), isFalse);
  });

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
