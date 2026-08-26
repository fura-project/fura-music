import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/catalog/catalog_models.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/src/rust/api/album.dart' as bridge_album;
import 'package:flutterustmusic/src/rust/api/artist.dart' as bridge_artist;
import 'package:flutterustmusic/src/rust/api/library.dart' as bridge_library;
import 'package:flutterustmusic/src/rust/api/queue.dart' as bridge_queue;

void main() {
  test('maps valid positional duplicates and redacts diagnostics', () {
    final duplicate = _bridgeTrack('same');
    final gateway = RustPlaybackQueueGateway(
      bridge: _FakeBridge([
        bridge_queue.PlaybackQueueUpdate(
          snapshot: bridge_queue.PlaybackQueueSnapshot(
            tracks: [duplicate, _bridgeTrack('middle'), duplicate],
            currentIndex: 2,
            hasPrevious: true,
            hasNext: false,
          ),
          currentChanged: true,
        ),
      ]),
    );

    final result = gateway.snapshot();

    expect(result.failure, isNull);
    expect(result.currentChanged, isTrue);
    expect(result.snapshot?.tracks, hasLength(3));
    expect(result.snapshot?.tracks[0].opaqueId, 'same');
    expect(result.snapshot?.tracks[2].opaqueId, 'same');
    expect(
      result.snapshot?.tracks.first.album?.opaqueId,
      'album:43001:private-mid',
    );
    expect(
      result.snapshot?.tracks.first.artists.first.opaqueId,
      'artist:42001:private-mid',
    );
    expect(result.snapshot?.currentIndex, 2);
    expect(result.toString(), isNot(contains('private-title')));
    expect(result.snapshot.toString(), isNot(contains('private-title')));
  });

  test('forwards complete track DTOs and exact positions', () {
    final bridge = _FakeBridge([
      bridge_queue.PlaybackQueueUpdate(
        snapshot: bridge_queue.PlaybackQueueSnapshot(
          tracks: [_bridgeTrack('one')],
          currentIndex: 0,
          hasPrevious: false,
          hasNext: false,
        ),
        currentChanged: true,
      ),
    ]);
    final gateway = RustPlaybackQueueGateway(bridge: bridge);
    const track = PlaylistTrackSummary(
      providerId: 'qq-music',
      opaqueId: 'opaque-one',
      title: 'Track one',
      subtitle: 'Version',
      artistNames: ['Artist one', 'Artist two'],
      artists: [
        ArtistSummary(
          providerId: 'qq-music',
          opaqueId: 'artist:42001:fixtureArtistMid',
          name: 'Artist one',
        ),
      ],
      albumTitle: 'Album',
      album: AlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:fixtureAlbumMid',
        title: 'Album',
      ),
      artworkUri: 'https://images.example.test/one.jpg',
      durationSeconds: 123,
    );

    gateway.replace(tracks: const [track, track], currentIndex: 1);

    expect(bridge.replaceIndex, 1);
    expect(bridge.replaceTracks, hasLength(2));
    final forwarded = bridge.replaceTracks.first;
    expect(forwarded.providerId, track.providerId);
    expect(forwarded.opaqueId, track.opaqueId);
    expect(forwarded.title, track.title);
    expect(forwarded.artistNames, track.artistNames);
    expect(forwarded.artists.single.opaqueId, track.artists.single.opaqueId);
    expect(forwarded.subtitle, track.subtitle);
    expect(forwarded.albumTitle, track.albumTitle);
    expect(forwarded.album?.opaqueId, track.album?.opaqueId);
    expect(forwarded.artworkUri, track.artworkUri);
    expect(forwarded.durationSeconds, track.durationSeconds);
  });

  test('maps every typed failure and thrown bridge call', () {
    final variants = {
      bridge_queue.PlaybackQueueFailure.invalidTrack:
          PlaybackQueueFailure.invalidTrack,
      bridge_queue.PlaybackQueueFailure.invalidPosition:
          PlaybackQueueFailure.invalidPosition,
      bridge_queue.PlaybackQueueFailure.coreUnavailable:
          PlaybackQueueFailure.coreUnavailable,
    };
    for (final entry in variants.entries) {
      final result = mapBridgePlaybackQueueUpdate(
        bridge_queue.PlaybackQueueUpdate(
          currentChanged: false,
          failure: entry.key,
        ),
      );
      expect(result.failure, entry.value);
      expect(result.snapshot, isNull);
    }

    final gateway = RustPlaybackQueueGateway(bridge: _ThrowingBridge());
    expect(gateway.snapshot().failure, PlaybackQueueFailure.coreUnavailable);
  });

  test('rejects ambiguous or structurally invalid snapshots', () {
    final valid = bridge_queue.PlaybackQueueSnapshot(
      tracks: [_bridgeTrack('one')],
      currentIndex: 0,
      hasPrevious: false,
      hasNext: false,
    );
    final invalid = <bridge_queue.PlaybackQueueUpdate>[
      bridge_queue.PlaybackQueueUpdate(
        snapshot: valid,
        currentChanged: false,
        failure: bridge_queue.PlaybackQueueFailure.invalidPosition,
      ),
      const bridge_queue.PlaybackQueueUpdate(currentChanged: false),
      bridge_queue.PlaybackQueueUpdate(
        snapshot: bridge_queue.PlaybackQueueSnapshot(
          tracks: const [],
          currentIndex: 0,
          hasPrevious: false,
          hasNext: false,
        ),
        currentChanged: false,
      ),
      bridge_queue.PlaybackQueueUpdate(
        snapshot: bridge_queue.PlaybackQueueSnapshot(
          tracks: [_bridgeTrack('one')],
          currentIndex: 0,
          hasPrevious: false,
          hasNext: true,
        ),
        currentChanged: false,
      ),
      bridge_queue.PlaybackQueueUpdate(
        snapshot: bridge_queue.PlaybackQueueSnapshot(
          tracks: [
            bridge_library.LibraryTrackSummary(
              providerId: 'QQ Music',
              opaqueId: 'one',
              title: 'private-title',
              artistNames: const ['private-artist'],
              artists: const [],
            ),
          ],
          currentIndex: 0,
          hasPrevious: false,
          hasNext: false,
        ),
        currentChanged: false,
      ),
    ];

    for (final update in invalid) {
      expect(
        mapBridgePlaybackQueueUpdate(update).failure,
        PlaybackQueueFailure.invalidResponse,
      );
    }
  });
}

bridge_library.LibraryTrackSummary _bridgeTrack(String opaqueId) =>
    bridge_library.LibraryTrackSummary(
      providerId: 'qq-music',
      opaqueId: opaqueId,
      title: 'private-title',
      subtitle: 'private-subtitle',
      artistNames: const ['private-artist'],
      artists: const [
        bridge_artist.CatalogArtistSummary(
          providerId: 'qq-music',
          opaqueId: 'artist:42001:private-mid',
          name: 'private-artist',
        ),
      ],
      albumTitle: 'private-album',
      album: const bridge_album.CatalogAlbumSummary(
        providerId: 'qq-music',
        opaqueId: 'album:43001:private-mid',
        title: 'private-album',
      ),
      artworkUri: 'https://images.example.test/private.jpg',
      durationSeconds: 120,
    );

class _FakeBridge implements PlaybackQueueBridge {
  _FakeBridge(this._updates);

  final List<bridge_queue.PlaybackQueueUpdate> _updates;
  List<bridge_library.LibraryTrackSummary> replaceTracks = const [];
  int? replaceIndex;

  bridge_queue.PlaybackQueueUpdate get _next => _updates.removeAt(0);

  @override
  bridge_queue.PlaybackQueueUpdate snapshot() => _next;

  @override
  bridge_queue.PlaybackQueueUpdate replace({
    required List<bridge_library.LibraryTrackSummary> tracks,
    required int? currentIndex,
  }) {
    replaceTracks = tracks;
    replaceIndex = currentIndex;
    return _next;
  }

  @override
  bridge_queue.PlaybackQueueUpdate push(
    bridge_library.LibraryTrackSummary track,
  ) => _next;

  @override
  bridge_queue.PlaybackQueueUpdate select(int index) => _next;

  @override
  bridge_queue.PlaybackQueueUpdate advance() => _next;

  @override
  bridge_queue.PlaybackQueueUpdate rewind() => _next;

  @override
  bridge_queue.PlaybackQueueUpdate completeCurrent() => _next;

  @override
  bridge_queue.PlaybackQueueUpdate remove(int index) => _next;

  @override
  bridge_queue.PlaybackQueueUpdate clear() => _next;
}

class _ThrowingBridge implements PlaybackQueueBridge {
  Never _throw() => throw StateError('bridge unavailable');

  @override
  bridge_queue.PlaybackQueueUpdate snapshot() => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate replace({
    required List<bridge_library.LibraryTrackSummary> tracks,
    required int? currentIndex,
  }) => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate push(
    bridge_library.LibraryTrackSummary track,
  ) => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate select(int index) => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate advance() => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate rewind() => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate completeCurrent() => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate remove(int index) => _throw();

  @override
  bridge_queue.PlaybackQueueUpdate clear() => _throw();
}
