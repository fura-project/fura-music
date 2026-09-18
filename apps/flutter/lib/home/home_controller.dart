import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum HomeResourceStage { loading, content, empty, error }

class HomeController extends ChangeNotifier {
  HomeController(
    this._accountGateway,
    this._dailyGateway,
    this._personalizedPlaylistsGateway,
    this._personalizedTracksGateway,
    this._relatedTracksGateway, {
    RecentListeningGateway? recentListening,
  }) : _recentListening = recentListening ?? RustRecentListeningGateway();

  final AccountSummaryGateway _accountGateway;
  final DailyRecommendationGateway _dailyGateway;
  final PersonalizedPlaylistsGateway _personalizedPlaylistsGateway;
  final PersonalizedTracksGateway _personalizedTracksGateway;
  final RelatedTracksGateway _relatedTracksGateway;
  final RecentListeningGateway _recentListening;

  HomeResourceStage _accountStage = HomeResourceStage.loading;
  HomeResourceStage _dailyStage = HomeResourceStage.loading;
  HomeResourceStage _personalizedPlaylistsStage = HomeResourceStage.loading;
  HomeResourceStage _personalizedTracksStage = HomeResourceStage.loading;
  HomeResourceStage _relatedTracksStage = HomeResourceStage.empty;
  AuthenticatedAccountSummary? _account;
  RecommendedPlaylistSummary? _dailyPlaylist;
  List<PlaylistTrackSummary> _dailyTracks = const [];
  List<RecommendedPlaylistSummary> _personalizedPlaylists = const [];
  List<PlaylistTrackSummary> _personalizedTracks = const [];
  PlaylistTrackSummary? _relatedSeed;
  List<PlaylistTrackSummary> _relatedTracks = const [];
  AccountSummaryFailure? _accountFailure;
  DailyRecommendationFailure? _dailyFailure;
  PersonalizedPlaylistsFailure? _personalizedPlaylistsFailure;
  PersonalizedTracksFailure? _personalizedTracksFailure;
  RelatedTracksFailure? _relatedTracksFailure;
  int _dailyOmittedTrackCount = 0;
  int _personalizedPlaylistsOmittedCount = 0;
  int _personalizedTracksOmittedCount = 0;
  int _relatedTracksOmittedCount = 0;
  int _dailyPartialResultRevision = 0;
  int _personalizedPlaylistsPartialResultRevision = 0;
  int _personalizedTracksPartialResultRevision = 0;
  int _relatedTracksPartialResultRevision = 0;
  AccountSummaryLoadOperation? _accountOperation;
  DailyRecommendationLoadOperation? _dailyOperation;
  PersonalizedPlaylistsLoadOperation? _personalizedPlaylistsOperation;
  PersonalizedTracksLoadOperation? _personalizedTracksOperation;
  RelatedTracksLoadOperation? _relatedTracksOperation;
  int _accountGeneration = 0;
  int _dailyGeneration = 0;
  int _personalizedPlaylistsGeneration = 0;
  int _personalizedTracksGeneration = 0;
  int _relatedTracksGeneration = 0;
  bool _disposed = false;
  Future<void>? _refreshFuture;
  bool _active = true;

  bool get isRefreshing => _refreshFuture != null;
  bool get refreshHasErrors =>
      _dailyFailure != null ||
      _personalizedPlaylistsFailure != null ||
      _personalizedTracksFailure != null;

  void setActive(bool active) {
    _active = active;
  }

  HomeResourceStage get accountStage => _accountStage;
  HomeResourceStage get dailyStage => _dailyStage;
  HomeResourceStage get personalizedPlaylistsStage =>
      _personalizedPlaylistsStage;
  HomeResourceStage get personalizedTracksStage => _personalizedTracksStage;
  HomeResourceStage get relatedTracksStage => _relatedTracksStage;
  AuthenticatedAccountSummary? get account => _account;
  RecommendedPlaylistSummary? get dailyPlaylist => _dailyPlaylist;
  List<PlaylistTrackSummary> get dailyTracks => _dailyTracks;
  List<RecommendedPlaylistSummary> get personalizedPlaylists =>
      _personalizedPlaylists;
  List<PlaylistTrackSummary> get personalizedTracks => _personalizedTracks;
  PlaylistTrackSummary? get relatedSeed => _relatedSeed;
  List<PlaylistTrackSummary> get relatedTracks => _relatedTracks;
  AccountSummaryFailure? get accountFailure => _accountFailure;
  DailyRecommendationFailure? get dailyFailure => _dailyFailure;
  PersonalizedPlaylistsFailure? get personalizedPlaylistsFailure =>
      _personalizedPlaylistsFailure;
  PersonalizedTracksFailure? get personalizedTracksFailure =>
      _personalizedTracksFailure;
  RelatedTracksFailure? get relatedTracksFailure => _relatedTracksFailure;
  int get dailyOmittedTrackCount => _dailyOmittedTrackCount;
  int get personalizedPlaylistsOmittedCount =>
      _personalizedPlaylistsOmittedCount;
  int get personalizedTracksOmittedCount => _personalizedTracksOmittedCount;
  int get relatedTracksOmittedCount => _relatedTracksOmittedCount;
  int get dailyPartialResultRevision => _dailyPartialResultRevision;
  int get personalizedPlaylistsPartialResultRevision =>
      _personalizedPlaylistsPartialResultRevision;
  int get personalizedTracksPartialResultRevision =>
      _personalizedTracksPartialResultRevision;
  int get relatedTracksPartialResultRevision =>
      _relatedTracksPartialResultRevision;

  bool get requiresSignIn =>
      _accountRequiresSignIn(_accountFailure) ||
      _dailyRequiresSignIn(_dailyFailure) ||
      _playlistsRequireSignIn(_personalizedPlaylistsFailure) ||
      _tracksRequireSignIn(_personalizedTracksFailure);

  Future<void> load() async {
    await Future.wait([
      _loadAccount(),
      _loadDaily(),
      _loadPersonalizedPlaylists(),
      _loadPersonalizedTracks(),
    ]);
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshFuture ??= _refresh();
  }

  Future<void> _refresh() async {
    try {
      await Future.wait([
        _loadDaily(),
        _loadPersonalizedPlaylists(),
        _loadPersonalizedTracks(),
      ]);
      if (!_disposed && _active) refreshRelatedTracks();
    } finally {
      _refreshFuture = null;
      _notify();
    }
  }

  void retryAccount() => unawaited(_loadAccount());
  void retryDaily() => unawaited(_loadDaily());
  void retryPersonalizedPlaylists() => unawaited(_loadPersonalizedPlaylists());
  void retryPersonalizedTracks() => unawaited(_loadPersonalizedTracks());

  /// Refreshes only the playlist shelf owned by Home's playlist section.
  Future<void> refreshPersonalizedPlaylists() => _loadPersonalizedPlaylists();
  void retryRelatedTracks() {
    final seed = _relatedSeed;
    if (seed != null) unawaited(_loadRelatedTracks(seed));
  }

  void observePlayback(
    PlaylistTrackSummary? track,
    int positionMs,
    bool playing,
  ) {
    if (_disposed) return;
    _recentListening.observe(track, positionMs, playing);
    if (_active && _relatedSeed == null) refreshRelatedTracks();
  }

  void refreshRelatedTracks() {
    if (_disposed) return;
    final seed = _recentListening.choose();
    final previous = _relatedSeed;
    if (previous?.providerId == seed?.providerId &&
        previous?.opaqueId == seed?.opaqueId) {
      return;
    }
    ++_relatedTracksGeneration;
    _relatedTracksOperation?.cancel();
    _relatedTracksOperation = null;
    _relatedSeed = seed;
    _relatedTracks = const [];
    _relatedTracksOmittedCount = 0;
    _relatedTracksFailure = null;
    if (seed == null) {
      _relatedTracksStage = HomeResourceStage.empty;
      _notify();
      return;
    }
    unawaited(_loadRelatedTracks(seed));
  }

  Future<void> _loadAccount() async {
    final generation = ++_accountGeneration;
    _accountOperation?.cancel();
    late final AccountSummaryLoadOperation operation;
    try {
      operation = _accountGateway.beginLoad();
    } on Object {
      _account = null;
      _accountFailure = AccountSummaryFailure.coreUnavailable;
      _accountStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _accountOperation = operation;
    _account = null;
    _accountFailure = null;
    _accountStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_accountOperation, operation)) _accountOperation = null;
    if (!_accountCurrent(generation)) return;
    _account = result.summary;
    _accountFailure = result.failure;
    _accountStage = result.summary == null
        ? HomeResourceStage.error
        : HomeResourceStage.content;
    _notify();
  }

  Future<void> _loadDaily() async {
    final generation = ++_dailyGeneration;
    _dailyOperation?.cancel();
    late final DailyRecommendationLoadOperation operation;
    try {
      operation = _dailyGateway.beginLoad();
    } on Object {
      _dailyFailure = DailyRecommendationFailure.coreUnavailable;
      _dailyStage = _dailyPlaylist == null && _dailyTracks.isEmpty
          ? HomeResourceStage.error
          : HomeResourceStage.content;
      _notify();
      return;
    }
    _dailyOperation = operation;
    _dailyFailure = null;
    _dailyStage = _dailyPlaylist == null && _dailyTracks.isEmpty
        ? HomeResourceStage.loading
        : HomeResourceStage.content;
    _notify();
    final result = await operation.run();
    if (identical(_dailyOperation, operation)) _dailyOperation = null;
    if (!_dailyCurrent(generation)) return;
    if (result.failure != null &&
        !_dailyRequiresSignIn(result.failure) &&
        (_dailyPlaylist != null || _dailyTracks.isNotEmpty)) {
      _dailyFailure = result.failure;
      _notify();
      return;
    }
    _dailyPlaylist = result.playlist;
    _dailyTracks = List.unmodifiable(result.tracks);
    _dailyOmittedTrackCount = result.omittedTrackCount;
    if (result.omittedTrackCount > 0) {
      _dailyPartialResultRevision += 1;
    }
    _dailyFailure = result.failure;
    _dailyStage = result.failure != null
        ? HomeResourceStage.error
        : result.playlist == null &&
              result.tracks.isEmpty &&
              result.omittedTrackCount == 0
        ? HomeResourceStage.empty
        : HomeResourceStage.content;
    _notify();
  }

  Future<void> _loadPersonalizedPlaylists() async {
    final generation = ++_personalizedPlaylistsGeneration;
    _personalizedPlaylistsOperation?.cancel();
    late final PersonalizedPlaylistsLoadOperation operation;
    try {
      operation = _personalizedPlaylistsGateway.beginLoad();
    } on Object {
      _personalizedPlaylistsFailure =
          PersonalizedPlaylistsFailure.coreUnavailable;
      _personalizedPlaylistsStage = _personalizedPlaylists.isEmpty
          ? HomeResourceStage.error
          : HomeResourceStage.content;
      _notify();
      return;
    }
    _personalizedPlaylistsOperation = operation;
    _personalizedPlaylistsFailure = null;
    _personalizedPlaylistsStage = _personalizedPlaylists.isEmpty
        ? HomeResourceStage.loading
        : HomeResourceStage.content;
    _notify();
    final result = await operation.run();
    if (identical(_personalizedPlaylistsOperation, operation)) {
      _personalizedPlaylistsOperation = null;
    }
    if (!_personalizedPlaylistsCurrent(generation)) return;
    if (result.failure != null &&
        !_playlistsRequireSignIn(result.failure) &&
        _personalizedPlaylists.isNotEmpty) {
      _personalizedPlaylistsFailure = result.failure;
      _notify();
      return;
    }
    _personalizedPlaylists = List.unmodifiable(result.playlists);
    _personalizedPlaylistsOmittedCount = result.omittedPlaylistCount;
    if (result.omittedPlaylistCount > 0) {
      _personalizedPlaylistsPartialResultRevision += 1;
    }
    _personalizedPlaylistsFailure = result.failure;
    _personalizedPlaylistsStage = result.failure != null
        ? HomeResourceStage.error
        : result.playlists.isEmpty && result.omittedPlaylistCount == 0
        ? HomeResourceStage.empty
        : HomeResourceStage.content;
    _notify();
  }

  Future<void> _loadPersonalizedTracks() async {
    final generation = ++_personalizedTracksGeneration;
    _personalizedTracksOperation?.cancel();
    late final PersonalizedTracksLoadOperation operation;
    try {
      operation = _personalizedTracksGateway.beginLoad();
    } on Object {
      _personalizedTracksFailure = PersonalizedTracksFailure.coreUnavailable;
      _personalizedTracksStage = _personalizedTracks.isEmpty
          ? HomeResourceStage.error
          : HomeResourceStage.content;
      _notify();
      return;
    }
    _personalizedTracksOperation = operation;
    _personalizedTracksFailure = null;
    _personalizedTracksStage = _personalizedTracks.isEmpty
        ? HomeResourceStage.loading
        : HomeResourceStage.content;
    _notify();
    final result = await operation.run();
    if (identical(_personalizedTracksOperation, operation)) {
      _personalizedTracksOperation = null;
    }
    if (!_personalizedTracksCurrent(generation)) return;
    if (result.failure != null &&
        !_tracksRequireSignIn(result.failure) &&
        _personalizedTracks.isNotEmpty) {
      _personalizedTracksFailure = result.failure;
      _notify();
      return;
    }
    _personalizedTracks = List.unmodifiable(result.tracks);
    _personalizedTracksOmittedCount = result.omittedTrackCount;
    if (result.omittedTrackCount > 0) {
      _personalizedTracksPartialResultRevision += 1;
    }
    _personalizedTracksFailure = result.failure;
    _personalizedTracksStage = result.failure != null
        ? HomeResourceStage.error
        : result.tracks.isEmpty && result.omittedTrackCount == 0
        ? HomeResourceStage.empty
        : HomeResourceStage.content;
    _notify();
  }

  Future<void> _loadRelatedTracks(PlaylistTrackSummary seed) async {
    final generation = ++_relatedTracksGeneration;
    _relatedTracksOperation?.cancel();
    late final RelatedTracksLoadOperation operation;
    try {
      operation = _relatedTracksGateway.beginLoad(seed);
    } on Object {
      _relatedTracks = const [];
      _relatedTracksOmittedCount = 0;
      _relatedTracksFailure = RelatedTracksFailure.coreUnavailable;
      _relatedTracksStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _relatedTracksOperation = operation;
    _relatedTracks = const [];
    _relatedTracksOmittedCount = 0;
    _relatedTracksFailure = null;
    _relatedTracksStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_relatedTracksOperation, operation)) {
      _relatedTracksOperation = null;
    }
    if (!_relatedTracksCurrent(generation, seed)) return;
    _relatedTracks = List.unmodifiable(result.tracks);
    _relatedTracksOmittedCount = result.omittedTrackCount;
    if (result.omittedTrackCount > 0) {
      _relatedTracksPartialResultRevision += 1;
    }
    _relatedTracksFailure = result.failure;
    _relatedTracksStage = result.failure != null
        ? HomeResourceStage.error
        : result.tracks.isEmpty && result.omittedTrackCount == 0
        ? HomeResourceStage.empty
        : HomeResourceStage.content;
    _notify();
  }

  bool _accountCurrent(int generation) =>
      !_disposed && generation == _accountGeneration;
  bool _dailyCurrent(int generation) =>
      !_disposed && generation == _dailyGeneration;
  bool _personalizedPlaylistsCurrent(int generation) =>
      !_disposed && generation == _personalizedPlaylistsGeneration;
  bool _personalizedTracksCurrent(int generation) =>
      !_disposed && generation == _personalizedTracksGeneration;
  bool _relatedTracksCurrent(int generation, PlaylistTrackSummary seed) =>
      !_disposed &&
      generation == _relatedTracksGeneration &&
      _relatedSeed?.providerId == seed.providerId &&
      _relatedSeed?.opaqueId == seed.opaqueId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _recentListening.dispose();
    ++_accountGeneration;
    ++_dailyGeneration;
    ++_personalizedPlaylistsGeneration;
    ++_personalizedTracksGeneration;
    ++_relatedTracksGeneration;
    _accountOperation?.cancel();
    _dailyOperation?.cancel();
    _personalizedPlaylistsOperation?.cancel();
    _personalizedTracksOperation?.cancel();
    _relatedTracksOperation?.cancel();
    _accountOperation = null;
    _dailyOperation = null;
    _personalizedPlaylistsOperation = null;
    _personalizedTracksOperation = null;
    _relatedTracksOperation = null;
    super.dispose();
  }
}

bool _accountRequiresSignIn(AccountSummaryFailure? failure) =>
    failure == AccountSummaryFailure.authenticationRequired ||
    failure == AccountSummaryFailure.credentialRejected ||
    failure == AccountSummaryFailure.credentialRejectedStorageCleanupFailed;

bool _dailyRequiresSignIn(DailyRecommendationFailure? failure) =>
    failure == DailyRecommendationFailure.authenticationRequired ||
    failure == DailyRecommendationFailure.credentialRejected ||
    failure ==
        DailyRecommendationFailure.credentialRejectedStorageCleanupFailed;

bool _playlistsRequireSignIn(PersonalizedPlaylistsFailure? failure) =>
    failure == PersonalizedPlaylistsFailure.authenticationRequired ||
    failure == PersonalizedPlaylistsFailure.credentialRejected ||
    failure ==
        PersonalizedPlaylistsFailure.credentialRejectedStorageCleanupFailed;

bool _tracksRequireSignIn(PersonalizedTracksFailure? failure) =>
    failure == PersonalizedTracksFailure.authenticationRequired ||
    failure == PersonalizedTracksFailure.credentialRejected ||
    failure == PersonalizedTracksFailure.credentialRejectedStorageCleanupFailed;
