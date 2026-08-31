import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';

enum HomeResourceStage { loading, content, empty, error }

class HomeController extends ChangeNotifier {
  HomeController(
    this._accountGateway,
    this._dailyGateway,
    this._personalizedPlaylistsGateway,
    this._personalizedTracksGateway,
    this._relatedTracksGateway,
  );

  final AccountSummaryGateway _accountGateway;
  final DailyRecommendationGateway _dailyGateway;
  final PersonalizedPlaylistsGateway _personalizedPlaylistsGateway;
  final PersonalizedTracksGateway _personalizedTracksGateway;
  final RelatedTracksGateway _relatedTracksGateway;

  HomeResourceStage _accountStage = HomeResourceStage.loading;
  HomeResourceStage _dailyStage = HomeResourceStage.loading;
  HomeResourceStage _personalizedPlaylistsStage = HomeResourceStage.loading;
  HomeResourceStage _personalizedTracksStage = HomeResourceStage.loading;
  HomeResourceStage _relatedTracksStage = HomeResourceStage.empty;
  AuthenticatedAccountSummary? _account;
  RecommendedPlaylistSummary? _dailyPlaylist;
  List<RecommendedPlaylistSummary> _personalizedPlaylists = const [];
  List<PlaylistTrackSummary> _personalizedTracks = const [];
  PlaylistTrackSummary? _relatedSeed;
  List<PlaylistTrackSummary> _relatedTracks = const [];
  AccountSummaryFailure? _accountFailure;
  DailyRecommendationFailure? _dailyFailure;
  PersonalizedPlaylistsFailure? _personalizedPlaylistsFailure;
  PersonalizedTracksFailure? _personalizedTracksFailure;
  RelatedTracksFailure? _relatedTracksFailure;
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

  HomeResourceStage get accountStage => _accountStage;
  HomeResourceStage get dailyStage => _dailyStage;
  HomeResourceStage get personalizedPlaylistsStage =>
      _personalizedPlaylistsStage;
  HomeResourceStage get personalizedTracksStage => _personalizedTracksStage;
  HomeResourceStage get relatedTracksStage => _relatedTracksStage;
  AuthenticatedAccountSummary? get account => _account;
  RecommendedPlaylistSummary? get dailyPlaylist => _dailyPlaylist;
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

  void retryAccount() => unawaited(_loadAccount());
  void retryDaily() => unawaited(_loadDaily());
  void retryPersonalizedPlaylists() => unawaited(_loadPersonalizedPlaylists());
  void retryPersonalizedTracks() => unawaited(_loadPersonalizedTracks());
  void retryRelatedTracks() {
    final seed = _relatedSeed;
    if (seed != null) unawaited(_loadRelatedTracks(seed));
  }

  void updateRelatedSeed(PlaylistTrackSummary? seed) {
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
      _dailyPlaylist = null;
      _dailyFailure = DailyRecommendationFailure.coreUnavailable;
      _dailyStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _dailyOperation = operation;
    _dailyPlaylist = null;
    _dailyFailure = null;
    _dailyStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_dailyOperation, operation)) _dailyOperation = null;
    if (!_dailyCurrent(generation)) return;
    _dailyPlaylist = result.playlist;
    _dailyFailure = result.failure;
    _dailyStage = result.failure != null
        ? HomeResourceStage.error
        : result.playlist == null
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
      _personalizedPlaylists = const [];
      _personalizedPlaylistsFailure =
          PersonalizedPlaylistsFailure.coreUnavailable;
      _personalizedPlaylistsStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _personalizedPlaylistsOperation = operation;
    _personalizedPlaylists = const [];
    _personalizedPlaylistsFailure = null;
    _personalizedPlaylistsStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_personalizedPlaylistsOperation, operation)) {
      _personalizedPlaylistsOperation = null;
    }
    if (!_personalizedPlaylistsCurrent(generation)) return;
    _personalizedPlaylists = List.unmodifiable(result.playlists);
    _personalizedPlaylistsFailure = result.failure;
    _personalizedPlaylistsStage = result.failure != null
        ? HomeResourceStage.error
        : result.playlists.isEmpty
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
      _personalizedTracks = const [];
      _personalizedTracksFailure = PersonalizedTracksFailure.coreUnavailable;
      _personalizedTracksStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _personalizedTracksOperation = operation;
    _personalizedTracks = const [];
    _personalizedTracksFailure = null;
    _personalizedTracksStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_personalizedTracksOperation, operation)) {
      _personalizedTracksOperation = null;
    }
    if (!_personalizedTracksCurrent(generation)) return;
    _personalizedTracks = List.unmodifiable(result.tracks);
    _personalizedTracksFailure = result.failure;
    _personalizedTracksStage = result.failure != null
        ? HomeResourceStage.error
        : result.tracks.isEmpty
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
      _relatedTracksFailure = RelatedTracksFailure.coreUnavailable;
      _relatedTracksStage = HomeResourceStage.error;
      _notify();
      return;
    }
    _relatedTracksOperation = operation;
    _relatedTracks = const [];
    _relatedTracksFailure = null;
    _relatedTracksStage = HomeResourceStage.loading;
    _notify();
    final result = await operation.run();
    if (identical(_relatedTracksOperation, operation)) {
      _relatedTracksOperation = null;
    }
    if (!_relatedTracksCurrent(generation, seed)) return;
    _relatedTracks = List.unmodifiable(result.tracks);
    _relatedTracksFailure = result.failure;
    _relatedTracksStage = result.failure != null
        ? HomeResourceStage.error
        : result.tracks.isEmpty
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
