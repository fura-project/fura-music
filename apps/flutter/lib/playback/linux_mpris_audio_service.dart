import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:dbus/dbus.dart';

const projectMprisVolumeAction = 'projectMprisVolume';
const projectMprisPlayerInterface = 'org.mpris.MediaPlayer2.Player';
const projectMprisObjectPath = '/org/mpris/MediaPlayer2';

/// Installs the Linux platform implementation before `AudioService.init`.
/// Other targets retain their registered audio_service implementation.
void registerProjectLinuxMprisAudioService() {
  if (Platform.isLinux) {
    AudioServicePlatform.instance = ProjectLinuxMprisAudioService();
  }
}

/// Linux MPRIS bridge for audio_service.
///
/// The upstream stable adapter advertises controls it does not implement and
/// stores only a stale position sample. This implementation is intentionally
/// limited to the existing project playback contract and does not own audio or
/// a second queue.
class ProjectLinuxMprisAudioService extends AudioServicePlatform {
  DBusClient? _client;
  ProjectMprisPlayer? _player;
  StreamSubscription<ProjectMprisEvent>? _eventSubscription;
  AudioHandlerCallbacks? _handlerCallbacks;

  @override
  Future<void> configure(ConfigureRequest request) async {
    if (_client != null || _eventSubscription != null) {
      throw StateError('Linux MPRIS playback is already configured.');
    }
    final channelId = request.config.androidNotificationChannelId;
    if (channelId == null || channelId.trim().isEmpty) {
      throw StateError('A non-empty playback service identifier is required.');
    }
    final client = DBusClient.session();
    final player = ProjectMprisPlayer(
      identity: request.config.androidNotificationChannelName,
    );
    _client = client;
    _player = player;
    _eventSubscription = player.events.listen(
      (event) => unawaited(_dispatch(event)),
    );
    await client.registerObject(player);
    final reply = await client.requestName(
      projectMprisServiceName(channelId),
      flags: const {DBusRequestNameFlag.doNotQueue},
    );
    if (reply != DBusRequestNameReply.primaryOwner &&
        reply != DBusRequestNameReply.alreadyOwner) {
      throw StateError('Unable to own the Linux MPRIS playback service name.');
    }
  }

  @override
  Future<void> setState(SetStateRequest request) async {
    _player?.updatePlaybackState(request.state);
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {
    // The project exposes only the current item through MPRIS. The Rust-backed
    // queue remains authoritative and MPRIS TrackList is intentionally absent.
    if (request.queue.isEmpty) _player?.clearMediaItem();
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    _player?.updateMediaItem(request.mediaItem);
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    _player?.stop();
  }

  @override
  Future<void> notifyChildrenChanged(
    NotifyChildrenChangedRequest request,
  ) async {
    // Browsable media children are not part of the accepted system contract.
  }

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    _handlerCallbacks = callbacks;
  }

  Future<void> _dispatch(ProjectMprisEvent event) async {
    final callbacks = _handlerCallbacks;
    final player = _player;
    if (callbacks == null || player == null) return;
    switch (event.type) {
      case ProjectMprisEventType.play:
        await callbacks.play(const PlayRequest());
      case ProjectMprisEventType.pause:
        await callbacks.pause(const PauseRequest());
      case ProjectMprisEventType.stop:
        await callbacks.stop(const StopRequest());
      case ProjectMprisEventType.next:
        await callbacks.skipToNext(const SkipToNextRequest());
      case ProjectMprisEventType.previous:
        await callbacks.skipToPrevious(const SkipToPreviousRequest());
      case ProjectMprisEventType.seek:
        final position = event.value! as Duration;
        await callbacks.seek(SeekRequest(position: position));
        await player.emitSeeked(player.position);
      case ProjectMprisEventType.repeat:
        await callbacks.setRepeatMode(
          SetRepeatModeRequest(
            repeatMode: switch (event.value! as String) {
              'Track' => AudioServiceRepeatModeMessage.one,
              'Playlist' => AudioServiceRepeatModeMessage.all,
              _ => AudioServiceRepeatModeMessage.none,
            },
          ),
        );
      case ProjectMprisEventType.shuffle:
        await callbacks.setShuffleMode(
          SetShuffleModeRequest(
            shuffleMode: event.value! as bool
                ? AudioServiceShuffleModeMessage.all
                : AudioServiceShuffleModeMessage.none,
          ),
        );
      case ProjectMprisEventType.volume:
        await callbacks.customAction(
          CustomActionRequest(
            name: projectMprisVolumeAction,
            extras: {'value': event.value! as double},
          ),
        );
    }
  }
}

enum ProjectMprisEventType {
  play,
  pause,
  stop,
  next,
  previous,
  seek,
  repeat,
  shuffle,
  volume,
}

class ProjectMprisEvent {
  const ProjectMprisEvent(this.type, [this.value]);

  final ProjectMprisEventType type;
  final Object? value;
}

/// Project-owned MPRIS object. Public only so its protocol behavior can be
/// regression-tested without requiring a desktop shell.
class ProjectMprisPlayer extends DBusObject {
  ProjectMprisPlayer({required this.identity, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(DBusObjectPath(projectMprisObjectPath));

  final String identity;
  final DateTime Function() _now;
  final StreamController<ProjectMprisEvent> _events =
      StreamController<ProjectMprisEvent>.broadcast();

  Stream<ProjectMprisEvent> get events => _events.stream;

  String _playbackStatus = 'Stopped';
  String _loopStatus = 'None';
  bool _shuffle = false;
  double _volume = 1;
  double _rate = 1;
  Duration _position = Duration.zero;
  DateTime _positionUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  _ProjectMprisMetadata _metadata = _ProjectMprisMetadata.empty();
  bool _canGoNext = false;
  bool _canGoPrevious = false;
  bool _canPlay = false;
  bool _canPause = false;
  bool _canSeek = false;

  String get playbackStatus => _playbackStatus;
  String get loopStatus => _loopStatus;
  bool get shuffle => _shuffle;
  double get volume => _volume;
  DBusObjectPath get trackId => _metadata.trackId;

  Duration get position {
    var value = _position;
    if (_playbackStatus == 'Playing') {
      final elapsed = _now().difference(_positionUpdatedAt);
      if (!elapsed.isNegative) {
        value += Duration(
          microseconds: (elapsed.inMicroseconds * _rate).round(),
        );
      }
    }
    if (value.isNegative) value = Duration.zero;
    final length = _metadata.length;
    if (length != null && value > length) value = length;
    return value;
  }

  void updatePlaybackState(PlaybackStateMessage state) {
    _position = state.updatePosition;
    _positionUpdatedAt = state.updateTime;
    _rate = state.speed > 0 && state.speed.isFinite ? state.speed : 1;
    _setPlaybackStatus(
      state.processingState == AudioProcessingStateMessage.idle ||
              state.processingState == AudioProcessingStateMessage.completed ||
              state.processingState == AudioProcessingStateMessage.error
          ? 'Stopped'
          : state.playing
          ? 'Playing'
          : 'Paused',
    );
    _setLoopStatus(switch (state.repeatMode) {
      AudioServiceRepeatModeMessage.one => 'Track',
      AudioServiceRepeatModeMessage.all ||
      AudioServiceRepeatModeMessage.group => 'Playlist',
      AudioServiceRepeatModeMessage.none => 'None',
    }, emitEvent: false);
    _setShuffle(
      state.shuffleMode != AudioServiceShuffleModeMessage.none,
      emitEvent: false,
    );

    final actions = <MediaActionMessage>{
      ...state.systemActions,
      ...state.controls.map((control) => control.action),
    };
    _setCapability(
      'CanGoNext',
      actions.contains(MediaActionMessage.skipToNext),
    );
    _setCapability(
      'CanGoPrevious',
      actions.contains(MediaActionMessage.skipToPrevious),
    );
    _setCapability(
      'CanPlay',
      actions.contains(MediaActionMessage.play) ||
          actions.contains(MediaActionMessage.playPause),
    );
    _setCapability(
      'CanPause',
      actions.contains(MediaActionMessage.pause) ||
          actions.contains(MediaActionMessage.playPause),
    );
    _setCapability('CanSeek', actions.contains(MediaActionMessage.seek));
  }

  void updateMediaItem(MediaItemMessage item) {
    _metadata = _ProjectMprisMetadata(
      trackId: _trackIdFor(item.id),
      title: item.title,
      length: item.duration,
      artist: item.artist == null ? null : [item.artist!],
      artUrl: item.artUri?.toString(),
      album: item.album,
      genre: item.genre == null ? null : [item.genre!],
    );
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'Metadata': _metadata.toValue()},
    );
  }

  void clearMediaItem() {
    _metadata = _ProjectMprisMetadata.empty();
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'Metadata': _metadata.toValue()},
    );
  }

  void stop() {
    _position = Duration.zero;
    _positionUpdatedAt = _now();
    _setPlaybackStatus('Stopped');
  }

  void _setPlaybackStatus(String value) {
    if (_playbackStatus == value) return;
    _playbackStatus = value;
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'PlaybackStatus': DBusString(value)},
    );
  }

  void _setLoopStatus(String value, {required bool emitEvent}) {
    if (_loopStatus == value) return;
    _loopStatus = value;
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'LoopStatus': DBusString(value)},
    );
    if (emitEvent) {
      _events.add(ProjectMprisEvent(ProjectMprisEventType.repeat, value));
    }
  }

  void _setShuffle(bool value, {required bool emitEvent}) {
    if (_shuffle == value) return;
    _shuffle = value;
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'Shuffle': DBusBoolean(value)},
    );
    if (emitEvent) {
      _events.add(ProjectMprisEvent(ProjectMprisEventType.shuffle, value));
    }
  }

  void _setVolume(double value, {required bool emitEvent}) {
    final bounded = value.clamp(0, 1).toDouble();
    if (_volume == bounded) return;
    _volume = bounded;
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {'Volume': DBusDouble(bounded)},
    );
    if (emitEvent) {
      _events.add(ProjectMprisEvent(ProjectMprisEventType.volume, bounded));
    }
  }

  void _setCapability(String name, bool value) {
    final previous = switch (name) {
      'CanGoNext' => _canGoNext,
      'CanGoPrevious' => _canGoPrevious,
      'CanPlay' => _canPlay,
      'CanPause' => _canPause,
      'CanSeek' => _canSeek,
      _ => false,
    };
    if (previous == value) return;
    switch (name) {
      case 'CanGoNext':
        _canGoNext = value;
      case 'CanGoPrevious':
        _canGoPrevious = value;
      case 'CanPlay':
        _canPlay = value;
      case 'CanPause':
        _canPause = value;
      case 'CanSeek':
        _canSeek = value;
    }
    emitPropertiesChanged(
      projectMprisPlayerInterface,
      changedProperties: {name: DBusBoolean(value)},
    );
  }

  void _acceptSeek(Duration value) {
    _position = value;
    _positionUpdatedAt = _now();
    _events.add(ProjectMprisEvent(ProjectMprisEventType.seek, value));
  }

  Future<void> emitSeeked(Duration value) => emitSignal(
    projectMprisPlayerInterface,
    'Seeked',
    [DBusInt64(value.inMicroseconds)],
  );

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      'org.mpris.MediaPlayer2',
      properties: [
        DBusIntrospectProperty(
          'CanQuit',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanRaise',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'HasTrackList',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Identity',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedUriSchemes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedMimeTypes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface(
      projectMprisPlayerInterface,
      methods: [
        DBusIntrospectMethod('Next'),
        DBusIntrospectMethod('Previous'),
        DBusIntrospectMethod('Pause'),
        DBusIntrospectMethod('PlayPause'),
        DBusIntrospectMethod('Stop'),
        DBusIntrospectMethod('Play'),
        DBusIntrospectMethod(
          'Seek',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Offset',
            ),
          ],
        ),
        DBusIntrospectMethod(
          'SetPosition',
          args: [
            DBusIntrospectArgument(
              DBusSignature('o'),
              DBusArgumentDirection.in_,
              name: 'TrackId',
            ),
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.in_,
              name: 'Position',
            ),
          ],
        ),
      ],
      signals: [
        DBusIntrospectSignal(
          'Seeked',
          args: [
            DBusIntrospectArgument(
              DBusSignature('x'),
              DBusArgumentDirection.out,
              name: 'Position',
            ),
          ],
        ),
      ],
      properties: [
        for (final entry in const <String, String>{
          'PlaybackStatus': 's',
          'LoopStatus': 's',
          'Rate': 'd',
          'Shuffle': 'b',
          'Metadata': 'a{sv}',
          'Volume': 'd',
          'Position': 'x',
          'MinimumRate': 'd',
          'MaximumRate': 'd',
          'CanGoNext': 'b',
          'CanGoPrevious': 'b',
          'CanPlay': 'b',
          'CanPause': 'b',
          'CanSeek': 'b',
          'CanControl': 'b',
        }.entries)
          DBusIntrospectProperty(
            entry.key,
            DBusSignature(entry.value),
            access:
                const {
                  'LoopStatus',
                  'Rate',
                  'Shuffle',
                  'Volume',
                }.contains(entry.key)
                ? DBusPropertyAccess.readwrite
                : DBusPropertyAccess.read,
          ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != projectMprisPlayerInterface) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    switch (methodCall.name) {
      case 'Next':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canGoNext) {
          _events.add(const ProjectMprisEvent(ProjectMprisEventType.next));
        }
      case 'Previous':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canGoPrevious) {
          _events.add(const ProjectMprisEvent(ProjectMprisEventType.previous));
        }
      case 'Pause':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canPause) {
          _events.add(const ProjectMprisEvent(ProjectMprisEventType.pause));
        }
      case 'PlayPause':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canPlay || _canPause) {
          _events.add(
            ProjectMprisEvent(
              _playbackStatus == 'Playing'
                  ? ProjectMprisEventType.pause
                  : ProjectMprisEventType.play,
            ),
          );
        }
      case 'Stop':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        _events.add(const ProjectMprisEvent(ProjectMprisEventType.stop));
      case 'Play':
        if (methodCall.values.isNotEmpty) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canPlay) {
          _events.add(const ProjectMprisEvent(ProjectMprisEventType.play));
        }
      case 'Seek':
        if (methodCall.signature != DBusSignature('x')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (_canSeek) {
          final target =
              position + Duration(microseconds: methodCall.values[0].asInt64());
          final length = _metadata.length;
          if (length != null && target > length) {
            if (_canGoNext) {
              _events.add(const ProjectMprisEvent(ProjectMprisEventType.next));
            }
          } else {
            _acceptSeek(target.isNegative ? Duration.zero : target);
          }
        }
      case 'SetPosition':
        if (methodCall.signature != DBusSignature('ox')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final requestedTrack = methodCall.values[0].asObjectPath();
        final requested = Duration(
          microseconds: methodCall.values[1].asInt64(),
        );
        final length = _metadata.length;
        if (_canSeek &&
            requestedTrack == _metadata.trackId &&
            !requested.isNegative &&
            (length == null || requested <= length)) {
          _acceptSeek(requested);
        }
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse([]);
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      final value = _rootProperties[name];
      return value == null
          ? DBusMethodErrorResponse.unknownProperty()
          : DBusMethodSuccessResponse([DBusVariant(value)]);
    }
    if (interface != projectMprisPlayerInterface) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    final value = _playerProperties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusMethodSuccessResponse([DBusVariant(value)]);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    final properties = switch (interface) {
      'org.mpris.MediaPlayer2' => _rootProperties,
      projectMprisPlayerInterface => _playerProperties,
      _ => null,
    };
    return properties == null
        ? DBusMethodErrorResponse.unknownInterface()
        : DBusMethodSuccessResponse([DBusDict.stringVariant(properties)]);
  }

  Map<String, DBusValue> get _rootProperties => {
    'CanQuit': const DBusBoolean(false),
    'CanRaise': const DBusBoolean(false),
    'HasTrackList': const DBusBoolean(false),
    'Identity': DBusString(identity),
    'SupportedUriSchemes': DBusArray.string([]),
    'SupportedMimeTypes': DBusArray.string([]),
  };

  Map<String, DBusValue> get _playerProperties => {
    'PlaybackStatus': DBusString(_playbackStatus),
    'LoopStatus': DBusString(_loopStatus),
    'Rate': DBusDouble(_rate),
    'Shuffle': DBusBoolean(_shuffle),
    'Metadata': _metadata.toValue(),
    'Volume': DBusDouble(_volume),
    'Position': DBusInt64(position.inMicroseconds),
    'MinimumRate': const DBusDouble(1),
    'MaximumRate': const DBusDouble(1),
    'CanGoNext': DBusBoolean(_canGoNext),
    'CanGoPrevious': DBusBoolean(_canGoPrevious),
    'CanPlay': DBusBoolean(_canPlay),
    'CanPause': DBusBoolean(_canPause),
    'CanSeek': DBusBoolean(_canSeek),
    'CanControl': const DBusBoolean(true),
  };

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface != projectMprisPlayerInterface) {
      return DBusMethodErrorResponse.unknownProperty();
    }
    switch (name) {
      case 'LoopStatus':
        if (value.signature != DBusSignature('s')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final status = value.asString();
        if (!const {'None', 'Track', 'Playlist'}.contains(status)) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        _setLoopStatus(status, emitEvent: true);
      case 'Shuffle':
        if (value.signature != DBusSignature('b')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        _setShuffle(value.asBoolean(), emitEvent: true);
      case 'Volume':
        if (value.signature != DBusSignature('d')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        _setVolume(value.asDouble(), emitEvent: true);
      case 'Rate':
        if (value.signature != DBusSignature('d')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        if (value.asDouble() != 1) {
          return DBusMethodErrorResponse.notSupported(
            'The current playback owner supports only normal speed.',
          );
        }
      case 'PlaybackStatus' ||
          'Metadata' ||
          'Position' ||
          'MinimumRate' ||
          'MaximumRate' ||
          'CanGoNext' ||
          'CanGoPrevious' ||
          'CanPlay' ||
          'CanPause' ||
          'CanSeek' ||
          'CanControl':
        return DBusMethodErrorResponse.propertyReadOnly();
      default:
        return DBusMethodErrorResponse.unknownProperty();
    }
    return DBusMethodSuccessResponse([]);
  }
}

class _ProjectMprisMetadata {
  const _ProjectMprisMetadata({
    required this.trackId,
    required this.title,
    this.length,
    this.artist,
    this.artUrl,
    this.album,
    this.genre,
  });

  factory _ProjectMprisMetadata.empty() => _ProjectMprisMetadata(
    trackId: DBusObjectPath('/dev/axiaobo/flutterustmusic/track/none'),
    title: 'No track',
  );

  final DBusObjectPath trackId;
  final String title;
  final Duration? length;
  final List<String>? artist;
  final String? artUrl;
  final String? album;
  final List<String>? genre;

  bool get hasTrack =>
      trackId.value != '/dev/axiaobo/flutterustmusic/track/none';

  DBusValue toValue() {
    if (!hasTrack) return DBusDict.stringVariant({});
    return DBusDict.stringVariant({
      'mpris:trackid': trackId,
      'xesam:title': DBusString(title),
      if (length != null) 'mpris:length': DBusInt64(length!.inMicroseconds),
      if (artist != null) 'xesam:artist': DBusArray.string(artist!),
      if (artUrl != null) 'mpris:artUrl': DBusString(artUrl!),
      if (album != null) 'xesam:album': DBusString(album!),
      if (genre != null) 'xesam:genre': DBusArray.string(genre!),
    });
  }
}

DBusObjectPath _trackIdFor(String mediaId) {
  final encoded = base64Url
      .encode(utf8.encode(mediaId))
      .replaceAll('-', '_')
      .replaceAll('=', '');
  return DBusObjectPath('/dev/axiaobo/flutterustmusic/track/t$encoded');
}

String _safeBusSuffix(String value) => value
    .split('.')
    .map((part) {
      final safe = part.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
      if (safe.isEmpty) return 'music';
      return RegExp('^[A-Za-z_]').hasMatch(safe) ? safe : 'p$safe';
    })
    .join('.');

String projectMprisServiceName(String serviceId) =>
    'org.mpris.MediaPlayer2.${_safeBusSuffix(serviceId)}.instance$pid';
