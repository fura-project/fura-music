import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/discover/recommended_playlist_controller.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/official_playlist_controller.dart';

enum HomeSpotlightKind { official, publicFallback }

enum HomeSpotlightStage { loading, content, empty, error }

/// Presentation source for Home's rotating Hero. Official/editorial playlists
/// are primary; the public PlaylistSquare feed is an explicitly labelled
/// fallback and remains a separate controller/capability.
class HomeSpotlightController extends ChangeNotifier {
  HomeSpotlightController(this._official, this._publicRecommendations) {
    _official.addListener(_onSourceChanged);
    _publicRecommendations.addListener(_onSourceChanged);
  }

  static const candidateLimit = 8;
  static const publicFallbackCandidateLimit = 3;

  final OfficialPlaylistController _official;
  final RecommendedPlaylistController _publicRecommendations;
  bool _disposed = false;

  HomeSpotlightKind get kind => _officialCandidates.isNotEmpty
      ? HomeSpotlightKind.official
      : HomeSpotlightKind.publicFallback;

  HomeSpotlightStage get stage {
    if (candidates.isNotEmpty) return HomeSpotlightStage.content;
    if (_official.stage == OfficialPlaylistStage.loading ||
        _publicRecommendations.stage == RecommendedPlaylistStage.loading) {
      return HomeSpotlightStage.loading;
    }
    if (_official.stage == OfficialPlaylistStage.error &&
        _publicRecommendations.stage == RecommendedPlaylistStage.error) {
      return HomeSpotlightStage.error;
    }
    if (_publicRecommendations.stage == RecommendedPlaylistStage.error) {
      return HomeSpotlightStage.error;
    }
    return HomeSpotlightStage.empty;
  }

  List<RecommendedPlaylistSummary> get candidates {
    final official = _officialCandidates;
    if (official.isNotEmpty) return official;
    return List.unmodifiable(
      _publicRecommendations.playlists.take(publicFallbackCandidateLimit),
    );
  }

  List<RecommendedPlaylistSummary> get _officialCandidates => List.unmodifiable(
    _official.playlists
        .take(candidateLimit)
        .map((playlist) => playlist.toRecommendationSummary()),
  );

  Future<void> load() async {
    await Future.wait([_official.load(), _publicRecommendations.load()]);
  }

  void retry() {
    unawaited(load());
  }

  void _onSourceChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _official.removeListener(_onSourceChanged);
    _publicRecommendations.removeListener(_onSourceChanged);
    super.dispose();
  }
}
