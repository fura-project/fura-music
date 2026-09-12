import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/album/album_details_gateway.dart';
import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/authentication/account_summary_gateway.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
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
import 'package:flutterustmusic/home/recent_listening_gateway.dart';
import 'package:flutterustmusic/library/favorite_album_gateway.dart';
import 'package:flutterustmusic/library/favorite_artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/playlist_detail_gateway.dart';
import 'package:flutterustmusic/library/recent_plays_gateway.dart';
import 'package:flutterustmusic/playback/system_playback_service.dart';
import 'package:flutterustmusic/search/album_search_gateway.dart';
import 'package:flutterustmusic/search/artist_search_gateway.dart';
import 'package:flutterustmusic/search/playlist_search_gateway.dart';
import 'package:flutterustmusic/search/track_search_gateway.dart';
import 'package:flutterustmusic/settings/app_settings.dart';

@immutable
class MusicProviderCapabilities {
  const MusicProviderCapabilities({
    required this.radar,
    required this.recentHistory,
    required this.libraryMutations,
    required this.dailyPlaylist,
    required this.dailyTracks,
    required this.personalFm,
    required this.supportedNewAlbumRegions,
    required this.supportedNewSongCategories,
  });

  static const qqMusic = MusicProviderCapabilities(
    radar: true,
    recentHistory: true,
    libraryMutations: true,
    dailyPlaylist: true,
    dailyTracks: false,
    personalFm: false,
    supportedNewAlbumRegions: NewAlbumRegion.values,
    supportedNewSongCategories: NewSongCategory.values,
  );

  static const netEaseCloudMusic = MusicProviderCapabilities(
    radar: false,
    recentHistory: false,
    libraryMutations: false,
    dailyPlaylist: false,
    dailyTracks: true,
    personalFm: true,
    supportedNewAlbumRegions: [
      NewAlbumRegion.western,
      NewAlbumRegion.korea,
      NewAlbumRegion.japan,
    ],
    supportedNewSongCategories: [
      NewSongCategory.western,
      NewSongCategory.japan,
      NewSongCategory.korea,
      NewSongCategory.latest,
    ],
  );

  final bool radar;
  final bool recentHistory;
  final bool libraryMutations;
  final bool dailyPlaylist;
  final bool dailyTracks;
  final bool personalFm;
  final List<NewAlbumRegion> supportedNewAlbumRegions;
  final List<NewSongCategory> supportedNewSongCategories;
}

@immutable
class MusicProviderDependencies {
  const MusicProviderDependencies({
    required this.authenticationGateway,
    required this.home,
    required this.library,
    required this.discovery,
    required this.capabilities,
    required this.initialCredentialRestore,
    this.desktopQuickLoginEnabled = false,
  });

  final QqMusicAuthenticationGateway authenticationGateway;
  final AuthenticatedHomeDependencies home;
  final AuthenticatedLibraryDependencies library;
  final AuthenticatedDiscoveryDependencies discovery;
  final MusicProviderCapabilities capabilities;
  final CredentialRestoreResult initialCredentialRestore;
  final bool desktopQuickLoginEnabled;
}

@immutable
class BuiltInProviderDependencies {
  const BuiltInProviderDependencies({
    required this.qqMusic,
    required this.netEase,
  });

  final MusicProviderDependencies qqMusic;
  final MusicProviderDependencies netEase;

  MusicProviderDependencies select(AppMusicProvider provider) =>
      switch (provider) {
        AppMusicProvider.qqMusic => qqMusic,
        AppMusicProvider.netEaseCloudMusic => netEase,
      };
}

@immutable
class AuthenticatedHomeDependencies {
  const AuthenticatedHomeDependencies({
    required this.accountSummaryGateway,
    required this.dailyRecommendationGateway,
    required this.personalizedPlaylistsGateway,
    required this.personalizedTracksGateway,
    required this.relatedTracksGateway,
    this.recentListeningFactory,
  });

  final AccountSummaryGateway accountSummaryGateway;
  final DailyRecommendationGateway dailyRecommendationGateway;
  final PersonalizedPlaylistsGateway personalizedPlaylistsGateway;
  final PersonalizedTracksGateway personalizedTracksGateway;
  final RelatedTracksGateway relatedTracksGateway;
  final RecentListeningGateway Function()? recentListeningFactory;
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
    this.recentPlaysGateway,
  });

  final UserLibraryGateway libraryGateway;
  final PlaylistDetailGateway playlistDetailGateway;
  final AlbumTrackGateway albumTrackGateway;
  final AlbumDetailsGateway albumDetailsGateway;
  final ArtistTrackGateway artistTrackGateway;
  final ArtistAlbumGateway artistAlbumGateway;
  final FavoriteAlbumGateway favoriteAlbumGateway;
  final FavoriteArtistGateway favoriteArtistGateway;
  final RecentPlaysGateway? recentPlaysGateway;
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
    required this.playbackHost,
    required this.trackCommentGateway,
  });

  final AppPlaybackHost playbackHost;
  final TrackCommentGateway trackCommentGateway;
}
