import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/comments/track_comment_gateway.dart';
import 'package:flutterustmusic/discover/new_album_gateway.dart';
import 'package:flutterustmusic/discover/new_song_gateway.dart';
import 'package:flutterustmusic/discover/radar_gateway.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';
import 'package:flutterustmusic/discover/recommended_playlist_gateway.dart';
import 'package:flutterustmusic/home/daily_recommendation_gateway.dart';
import 'package:flutterustmusic/home/personalized_playlist_gateway.dart';
import 'package:flutterustmusic/home/personalized_track_gateway.dart';
import 'package:flutterustmusic/home/related_track_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/lyrics/lyric_gateway.dart';
import 'package:flutterustmusic/playback/foreground_audio_player.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/playback/media_resolution_gateway.dart';
import 'package:flutterustmusic/playback/playback_queue_gateway.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';

@immutable
class AuthenticatedHomeDependencies {
  const AuthenticatedHomeDependencies({
    required this.accountSummaryGateway,
    required this.dailyRecommendationGateway,
    required this.personalizedPlaylistsGateway,
    required this.personalizedTracksGateway,
    required this.relatedTracksGateway,
  });

  final AccountSummaryGateway accountSummaryGateway;
  final DailyRecommendationGateway dailyRecommendationGateway;
  final PersonalizedPlaylistsGateway personalizedPlaylistsGateway;
  final PersonalizedTracksGateway personalizedTracksGateway;
  final RelatedTracksGateway relatedTracksGateway;
}

@immutable
class AuthenticatedLibraryDependencies {
  const AuthenticatedLibraryDependencies({
    required this.libraryGateway,
    required this.playlistDetailGateway,
    required this.albumTrackGateway,
    required this.albumDetailsGateway,
    required this.artistTrackGateway,
    required this.artistAlbumGateway,
    required this.favoriteAlbumGateway,
    required this.favoriteArtistGateway,
  });

  final UserLibraryGateway libraryGateway;
  final PlaylistDetailGateway playlistDetailGateway;
  final AlbumTrackGateway albumTrackGateway;
  final AlbumDetailsGateway albumDetailsGateway;
  final ArtistTrackGateway artistTrackGateway;
  final ArtistAlbumGateway artistAlbumGateway;
  final FavoriteAlbumGateway favoriteAlbumGateway;
  final FavoriteArtistGateway favoriteArtistGateway;
}

@immutable
class AuthenticatedDiscoveryDependencies {
  const AuthenticatedDiscoveryDependencies({
    required this.trackSearchGateway,
    required this.artistSearchGateway,
    required this.albumSearchGateway,
    required this.playlistSearchGateway,
    required this.recommendedPlaylistGateway,
    required this.newAlbumGateway,
    required this.newSongGateway,
    required this.rankingGateway,
    required this.radarGateway,
  });

  final TrackSearchGateway trackSearchGateway;
  final ArtistSearchGateway artistSearchGateway;
  final AlbumSearchGateway albumSearchGateway;
  final PlaylistSearchGateway playlistSearchGateway;
  final RecommendedPlaylistGateway recommendedPlaylistGateway;
  final NewAlbumGateway newAlbumGateway;
  final NewSongGateway newSongGateway;
  final RankingGateway rankingGateway;
  final RadarGateway radarGateway;
}

@immutable
class AuthenticatedPlaybackDependencies {
  const AuthenticatedPlaybackDependencies({
    required this.mediaResolutionGateway,
    required this.lyricGateway,
    required this.playbackQueueGateway,
    required this.trackCommentGateway,
    required this.audioEngine,
    this.systemPlaybackBinding = const NoopSystemPlaybackBinding(),
  });

  final MediaResolutionGateway mediaResolutionGateway;
  final LyricGateway lyricGateway;
  final PlaybackQueueGateway playbackQueueGateway;
  final TrackCommentGateway trackCommentGateway;
  final ForegroundAudioEngine audioEngine;
  final SystemPlaybackBinding systemPlaybackBinding;
}
