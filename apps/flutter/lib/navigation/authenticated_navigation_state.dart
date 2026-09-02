import 'package:flutterustmusic/album/album_gateway.dart';
import 'package:flutterustmusic/artist/artist_gateway.dart';
import 'package:flutterustmusic/library/library_gateway.dart';
import 'package:flutterustmusic/library/library_section_selector.dart';
import 'package:flutterustmusic/discover/ranking_gateway.dart';

enum AuthenticatedPrimaryDestination { home, discover, search, library }

enum PlaylistRouteOrigin {
  library,
  homeLibrary,
  search,
  discover,
  homeRecommendation,
}

enum AlbumRouteOrigin {
  search,
  searchArtist,
  discover,
  favoriteAlbums,
  favoriteArtist,
  trackContext,
  trackContextArtist,
  albumArtist,
  nowPlaying,
  nowPlayingArtist,
}

enum ArtistRouteOrigin {
  search,
  favoriteArtists,
  trackContext,
  album,
  nowPlaying,
}

sealed class AuthenticatedLocalRoute {
  const AuthenticatedLocalRoute();
}

class PlaylistLocalRoute extends AuthenticatedLocalRoute {
  const PlaylistLocalRoute({required this.playlist, required this.origin});

  final UserPlaylistSummary playlist;
  final PlaylistRouteOrigin origin;
}

class AlbumLocalRoute extends AuthenticatedLocalRoute {
  const AlbumLocalRoute({required this.album, required this.origin});

  final AlbumSummary album;
  final AlbumRouteOrigin origin;
}

class ArtistLocalRoute extends AuthenticatedLocalRoute {
  const ArtistLocalRoute({required this.artist, required this.origin});

  final ArtistSummary artist;
  final ArtistRouteOrigin origin;
}

class RankingLocalRoute extends AuthenticatedLocalRoute {
  const RankingLocalRoute(this.ranking);

  final RankingSummary ranking;
}

class ExpandedNowPlayingLocalRoute extends AuthenticatedLocalRoute {
  const ExpandedNowPlayingLocalRoute();
}

class SettingsLocalRoute extends AuthenticatedLocalRoute {
  const SettingsLocalRoute();
}

enum AuthenticatedBackTarget { none, localRoute, libraryPlaylists, home }

class AuthenticatedBackResult {
  const AuthenticatedBackResult._(this.target, [this.route]);

  const AuthenticatedBackResult.none() : this._(AuthenticatedBackTarget.none);

  const AuthenticatedBackResult.localRoute(AuthenticatedLocalRoute route)
    : this._(AuthenticatedBackTarget.localRoute, route);

  const AuthenticatedBackResult.libraryPlaylists()
    : this._(AuthenticatedBackTarget.libraryPlaylists);

  const AuthenticatedBackResult.home() : this._(AuthenticatedBackTarget.home);

  final AuthenticatedBackTarget target;
  final AuthenticatedLocalRoute? route;

  bool get changed => target != AuthenticatedBackTarget.none;
}

/// Owns retained, presentation-only navigation state for the authenticated app.
///
/// Widgets and their controllers remain in the retained [IndexedStack] owned by
/// `UserLibraryPage`; this model only makes destination, subsection, local-route
/// order, and Back resolution explicit.
class AuthenticatedNavigationState {
  AuthenticatedPrimaryDestination _primaryDestination =
      AuthenticatedPrimaryDestination.home;
  LibrarySection _librarySection = LibrarySection.playlists;
  final Set<AuthenticatedPrimaryDestination> _visitedDestinations = {
    AuthenticatedPrimaryDestination.home,
    AuthenticatedPrimaryDestination.library,
  };
  final Set<LibrarySection> _visitedLibrarySections = {
    LibrarySection.playlists,
  };
  final List<AuthenticatedLocalRoute> _routes = [];

  AuthenticatedPrimaryDestination get primaryDestination => _primaryDestination;
  LibrarySection get librarySection => _librarySection;
  List<AuthenticatedLocalRoute> get routes => List.unmodifiable(_routes);
  AuthenticatedLocalRoute? get topRoute =>
      _routes.isEmpty ? null : _routes.last;
  bool get hasLocalRoute => _routes.isNotEmpty;
  bool get hasLibrarySubsection =>
      _primaryDestination == AuthenticatedPrimaryDestination.library &&
      _librarySection != LibrarySection.playlists;
  bool get canGoBack =>
      hasLocalRoute ||
      hasLibrarySubsection ||
      _primaryDestination != AuthenticatedPrimaryDestination.home;

  bool visitedDestination(AuthenticatedPrimaryDestination destination) =>
      _visitedDestinations.contains(destination);

  bool visitedLibrarySection(LibrarySection section) =>
      _visitedLibrarySections.contains(section);

  bool selectPrimaryDestination(AuthenticatedPrimaryDestination destination) {
    if (hasLocalRoute || _primaryDestination == destination) return false;
    _primaryDestination = destination;
    _visitedDestinations.add(destination);
    return true;
  }

  bool selectLibrarySection(LibrarySection section) {
    if (hasLocalRoute ||
        _primaryDestination != AuthenticatedPrimaryDestination.library ||
        _librarySection == section) {
      return false;
    }
    _librarySection = section;
    _visitedLibrarySections.add(section);
    return true;
  }

  void push(AuthenticatedLocalRoute route) {
    _routes.add(route);
  }

  AuthenticatedLocalRoute? popRoute() =>
      _routes.isEmpty ? null : _routes.removeLast();

  AuthenticatedBackResult goBack() {
    final route = popRoute();
    if (route != null) return AuthenticatedBackResult.localRoute(route);
    if (hasLibrarySubsection) {
      _librarySection = LibrarySection.playlists;
      return const AuthenticatedBackResult.libraryPlaylists();
    }
    if (_primaryDestination != AuthenticatedPrimaryDestination.home) {
      _primaryDestination = AuthenticatedPrimaryDestination.home;
      return const AuthenticatedBackResult.home();
    }
    return const AuthenticatedBackResult.none();
  }
}
