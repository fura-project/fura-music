import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/playback/linux_mpris_player.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/playback/track_playback_controller.dart';

void main() {
  late Duration now;
  late ProjectMprisPlayer player;

  setUp(() {
    now = Duration.zero;
    player = ProjectMprisPlayer(identity: 'flutterustmusic', now: () => now);
    player.updateMediaItem(
      const PlaylistTrackSummary(
        providerId: 'qq-music',
        opaqueId: 'opaque-track',
        title: 'Track',
        artistNames: ['Artist'],
        durationSeconds: 180,
      ),
      selection: 0,
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
      now = now + const Duration(seconds: 3);

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
      final relative = await relativeEvent;
      expect(relative.type, ProjectMprisEventType.seekRelative);
      expect(relative.value, const Duration(seconds: 5));
      expect(player.position, const Duration(seconds: 10));

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

  test(
    'root advertises real window activation and keeps Quit disabled',
    () async {
      final fixture = ProjectMprisPlayer(
        identity: 'fura music',
        now: () => now,
      );
      addTearDown(fixture.close);
      const root = 'org.mpris.MediaPlayer2';
      Future<DBusMethodResponse> call(
        ProjectMprisPlayer object,
        String method,
      ) => object.handleMethodCall(
        DBusMethodCall(sender: ':test', interface: root, name: method),
      );
      expect(
        (await fixture.getProperty(
          root,
          'CanRaise',
        )).returnValues.single.asVariant().asBoolean(),
        isFalse,
      );
      expect(await call(fixture, 'Raise'), isA<DBusMethodSuccessResponse>());
      var raises = 0;
      final withWindow = ProjectMprisPlayer(
        identity: 'fura music',
        now: () => now,
        onRaise: () async {
          raises++;
        },
      );
      addTearDown(withWindow.close);
      expect(
        (await withWindow.getProperty(
          root,
          'CanRaise',
        )).returnValues.single.asVariant().asBoolean(),
        isTrue,
      );
      expect(await call(withWindow, 'Raise'), isA<DBusMethodSuccessResponse>());
      expect(await call(withWindow, 'Quit'), isA<DBusMethodSuccessResponse>());
      expect(await call(withWindow, 'Unknown'), isA<DBusMethodErrorResponse>());
      expect(raises, 1);
    },
  );

  test(
    'publishes public artwork only and clears it with the next selection',
    () async {
      Future<DBusValue?> artwork(String? uri, int selection) async {
        player.updateMediaItem(
          PlaylistTrackSummary(
            providerId: 'qq-music',
            opaqueId: 'selected',
            title: 'Track',
            artistNames: const ['Artist'],
            artworkUri: uri,
          ),
          selection: selection,
        );
        return (await _property(
          player,
          'Metadata',
        )).asStringVariantDict()['mpris:artUrl'];
      }

      const cover = 'https://p2.music.126.net/fixture.jpg?param=320y320';
      expect((await artwork(cover, 1))?.asString(), cover);
      final first = player.trackId;
      expect((await artwork(cover, 2))?.asString(), cover);
      expect(player.trackId, isNot(first));
      expect(await artwork(null, 3), isNull);
      expect(
        await artwork('https://name:secret@example.test/cover.png', 4),
        isNull,
      );
      expect(
        await artwork('https://example.test/cover.png?token=secret', 5),
        isNull,
      );
      expect(await artwork('file:///private/cover.png', 6), isNull);
      expect(
        await artwork('https://example.test/cover.png?param=%FF', 7),
        isNull,
      );
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
