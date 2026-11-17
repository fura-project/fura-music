import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';

class SessionAlbumTrackGateway implements AlbumTrackGateway {
  SessionAlbumTrackGateway(this._delegate);

  final AlbumTrackGateway _delegate;
  final Map<(String, String, int, int), _CachedAlbumTrackPage> _pages = {};
  int _generation = 0;
  bool _disposed = false;

  @override
  AlbumTrackPageLoadOperation beginLoad({
    required AlbumSummary album,
    required int offset,
    required int size,
  }) {
    final key = (album.providerId, album.opaqueId, offset, size);
    var entry = _pages[key];
    if (entry == null) {
      final source = _delegate.beginLoad(
        album: album,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final _CachedAlbumTrackPage created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_pages[key], created)) {
          if (result.failure == null && result.offset == offset) {
            created.resolved = result;
          } else {
            _pages.remove(key);
          }
        }
        return result;
      });
      created = _CachedAlbumTrackPage(source, future);
      entry = created;
      _pages[key] = entry;
    }
    return _JoinedAlbumTrackLoadOperation(entry);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    for (final entry in _pages.values) {
      entry.source.cancel();
    }
    _pages.clear();
  }
}

class _CachedAlbumTrackPage {
  _CachedAlbumTrackPage(this.source, this.future);

  final AlbumTrackPageLoadOperation source;
  final Future<AlbumTrackPageResult> future;
  AlbumTrackPageResult? resolved;
}

class _JoinedAlbumTrackLoadOperation implements AlbumTrackPageLoadOperation {
  _JoinedAlbumTrackLoadOperation(this._entry);

  final _CachedAlbumTrackPage _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<AlbumTrackPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const AlbumTrackPageResult(failure: AlbumTrackFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const AlbumTrackPageResult(failure: AlbumTrackFailure.cancelled),
    );
  }
}

class SessionAlbumDetailsGateway implements AlbumDetailsGateway {
  SessionAlbumDetailsGateway(this._delegate);

  final AlbumDetailsGateway _delegate;
  final Map<(String, String), _CachedAlbumDetailsEntry> _entries = {};
  int _generation = 0;
  bool _disposed = false;

  @override
  AlbumDetailsLoadOperation beginLoad(AlbumSummary album) {
    final key = (album.providerId, album.opaqueId);
    var entry = _entries[key];
    if (entry == null) {
      final source = _delegate.beginLoad(album);
      final generation = _generation;
      late final _CachedAlbumDetailsEntry created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_entries[key], created)) {
          if (result.failure == null && result.details != null) {
            created.resolved = result;
          } else {
            _entries.remove(key);
          }
        }
        return result;
      });
      created = _CachedAlbumDetailsEntry(source, future);
      entry = created;
      _entries[key] = entry;
    }
    return _JoinedAlbumDetailsLoadOperation(entry);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    for (final entry in _entries.values) {
      entry.source.cancel();
    }
    _entries.clear();
  }
}

class _CachedAlbumDetailsEntry {
  _CachedAlbumDetailsEntry(this.source, this.future);

  final AlbumDetailsLoadOperation source;
  final Future<AlbumDetailsResult> future;
  AlbumDetailsResult? resolved;
}

class _JoinedAlbumDetailsLoadOperation implements AlbumDetailsLoadOperation {
  _JoinedAlbumDetailsLoadOperation(this._entry);

  final _CachedAlbumDetailsEntry _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<AlbumDetailsResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const AlbumDetailsResult(failure: AlbumDetailsFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const AlbumDetailsResult(failure: AlbumDetailsFailure.cancelled),
    );
  }
}

class SessionArtistTrackGateway implements ArtistTrackGateway {
  SessionArtistTrackGateway(this._delegate);

  final ArtistTrackGateway _delegate;
  final Map<(String, String, int, int), _CachedArtistTrackPage> _pages = {};
  int _generation = 0;
  bool _disposed = false;

  @override
  ArtistTrackPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    final key = (artist.providerId, artist.opaqueId, offset, size);
    var entry = _pages[key];
    if (entry == null) {
      final source = _delegate.beginLoad(
        artist: artist,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final _CachedArtistTrackPage created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_pages[key], created)) {
          if (result.failure == null && result.offset == offset) {
            created.resolved = result;
          } else {
            _pages.remove(key);
          }
        }
        return result;
      });
      created = _CachedArtistTrackPage(source, future);
      entry = created;
      _pages[key] = entry;
    }
    return _JoinedArtistTrackLoadOperation(entry);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    for (final entry in _pages.values) {
      entry.source.cancel();
    }
    _pages.clear();
  }
}

class _CachedArtistTrackPage {
  _CachedArtistTrackPage(this.source, this.future);

  final ArtistTrackPageLoadOperation source;
  final Future<ArtistTrackPageResult> future;
  ArtistTrackPageResult? resolved;
}

class _JoinedArtistTrackLoadOperation implements ArtistTrackPageLoadOperation {
  _JoinedArtistTrackLoadOperation(this._entry);

  final _CachedArtistTrackPage _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<ArtistTrackPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const ArtistTrackPageResult(failure: ArtistTrackFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const ArtistTrackPageResult(failure: ArtistTrackFailure.cancelled),
    );
  }
}

class SessionArtistAlbumGateway implements ArtistAlbumGateway {
  SessionArtistAlbumGateway(this._delegate);

  final ArtistAlbumGateway _delegate;
  final Map<(String, String, int, int), _CachedArtistAlbumPage> _pages = {};
  int _generation = 0;
  bool _disposed = false;

  @override
  ArtistAlbumPageLoadOperation beginLoad({
    required ArtistSummary artist,
    required int offset,
    required int size,
  }) {
    final key = (artist.providerId, artist.opaqueId, offset, size);
    var entry = _pages[key];
    if (entry == null) {
      final source = _delegate.beginLoad(
        artist: artist,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final _CachedArtistAlbumPage created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_pages[key], created)) {
          if (result.failure == null && result.offset == offset) {
            created.resolved = result;
          } else {
            _pages.remove(key);
          }
        }
        return result;
      });
      created = _CachedArtistAlbumPage(source, future);
      entry = created;
      _pages[key] = entry;
    }
    return _JoinedArtistAlbumLoadOperation(entry);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    for (final entry in _pages.values) {
      entry.source.cancel();
    }
    _pages.clear();
  }
}

class _CachedArtistAlbumPage {
  _CachedArtistAlbumPage(this.source, this.future);

  final ArtistAlbumPageLoadOperation source;
  final Future<ArtistAlbumPageResult> future;
  ArtistAlbumPageResult? resolved;
}

class _JoinedArtistAlbumLoadOperation implements ArtistAlbumPageLoadOperation {
  _JoinedArtistAlbumLoadOperation(this._entry);

  final _CachedArtistAlbumPage _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<ArtistAlbumPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const ArtistAlbumPageResult(failure: ArtistAlbumFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const ArtistAlbumPageResult(failure: ArtistAlbumFailure.cancelled),
    );
  }
}

class SessionRankingGateway implements RankingGateway {
  SessionRankingGateway(this._delegate);

  final RankingGateway _delegate;
  _CachedRankingGroupEntry? _groupEntry;
  final Map<(String, String, int, int), _CachedRankingTrackPage> _pages = {};
  int _generation = 0;
  bool _disposed = false;

  @override
  RankingGroupLoadOperation beginGroupLoad() {
    var entry = _groupEntry;
    if (entry == null) {
      final source = _delegate.beginGroupLoad();
      final generation = _generation;
      late final _CachedRankingGroupEntry created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_groupEntry, created)) {
          if (result.failure == null) {
            created.resolved = result;
          } else {
            _groupEntry = null;
          }
        }
        return result;
      });
      created = _CachedRankingGroupEntry(source, future);
      entry = created;
      _groupEntry = entry;
    }
    return _JoinedRankingGroupLoadOperation(entry);
  }

  @override
  RankingTrackPageLoadOperation beginTrackLoad({
    required RankingSummary ranking,
    required int offset,
    required int size,
  }) {
    final key = (ranking.providerId, ranking.opaqueId, offset, size);
    var entry = _pages[key];
    if (entry == null) {
      final source = _delegate.beginTrackLoad(
        ranking: ranking,
        offset: offset,
        size: size,
      );
      final generation = _generation;
      late final _CachedRankingTrackPage created;
      final future = source.run().then((result) {
        if (!_disposed &&
            generation == _generation &&
            identical(_pages[key], created)) {
          if (result.failure == null && result.offset == offset) {
            created.resolved = result;
          } else {
            _pages.remove(key);
          }
        }
        return result;
      });
      created = _CachedRankingTrackPage(source, future);
      entry = created;
      _pages[key] = entry;
    }
    return _JoinedRankingTrackLoadOperation(entry);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    _groupEntry?.source.cancel();
    _groupEntry = null;
    for (final entry in _pages.values) {
      entry.source.cancel();
    }
    _pages.clear();
  }
}

class _CachedRankingGroupEntry {
  _CachedRankingGroupEntry(this.source, this.future);

  final RankingGroupLoadOperation source;
  final Future<RankingGroupResult> future;
  RankingGroupResult? resolved;
}

class _JoinedRankingGroupLoadOperation implements RankingGroupLoadOperation {
  _JoinedRankingGroupLoadOperation(this._entry);

  final _CachedRankingGroupEntry _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<RankingGroupResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const RankingGroupResult(failure: RankingFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const RankingGroupResult(failure: RankingFailure.cancelled),
    );
  }
}

class _CachedRankingTrackPage {
  _CachedRankingTrackPage(this.source, this.future);

  final RankingTrackPageLoadOperation source;
  final Future<RankingTrackPageResult> future;
  RankingTrackPageResult? resolved;
}

class _JoinedRankingTrackLoadOperation
    implements RankingTrackPageLoadOperation {
  _JoinedRankingTrackLoadOperation(this._entry);

  final _CachedRankingTrackPage _entry;
  bool _active = true;

  @override
  bool cancel() {
    final wasActive = _active;
    _active = false;
    return wasActive;
  }

  @override
  Future<RankingTrackPageResult> run() {
    if (!_active) {
      return SynchronousFuture(
        const RankingTrackPageResult(failure: RankingFailure.cancelled),
      );
    }
    final resolved = _entry.resolved;
    if (resolved != null) {
      return SynchronousFuture(resolved);
    }
    return _entry.future.then(
      (result) => _active
          ? result
          : const RankingTrackPageResult(failure: RankingFailure.cancelled),
    );
  }
}
