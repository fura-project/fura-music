// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'fura music';

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonClearSearch => 'Clear search';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonTryLoadingMoreAgain => 'Try loading more again';

  @override
  String get commonAddToQueue => 'Add to queue';

  @override
  String get commonMoreActions => 'More actions';

  @override
  String get commonPlayFromHere => 'Play from here';

  @override
  String get commonOpenAlbum => 'Open album';

  @override
  String get commonOpenArtist => 'Open artist';

  @override
  String get commonChooseArtist => 'Choose artist';

  @override
  String get commonPlay => 'Play';

  @override
  String commonTrackSemantics(Object artists, Object title) {
    return '$title, $artists';
  }

  @override
  String commonAnnouncement(Object detail, Object title) {
    return '$title. $detail';
  }

  @override
  String commonSelectedValue(Object label, Object value) {
    return '$label: $value';
  }

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonScrollToLoadMore => 'Scroll to load more';

  @override
  String get tableTitle => 'Title';

  @override
  String get tableArtist => 'Artist';

  @override
  String get tableAlbum => 'Album';

  @override
  String get tableDuration => 'Duration';

  @override
  String get trackUnknownArtist => 'Unknown artist';

  @override
  String trackBrowseContextTooltip(String trackTitle) {
    return 'Browse context for $trackTitle';
  }

  @override
  String trackAddToQueueTooltip(String trackTitle) {
    return 'Add $trackTitle to queue';
  }

  @override
  String trackArtworkSemantics(String trackTitle) {
    return 'Artwork for $trackTitle';
  }

  @override
  String get trackChooseArtistTitle => 'Choose an artist';

  @override
  String get trackMultipleArtistsDetail =>
      'This track credits more than one artist.';

  @override
  String metadataActionSemantics(String action, String value) {
    return '$action: $value';
  }

  @override
  String get librarySectionLabel => 'Library';

  @override
  String get libraryLikedSongs => 'Liked songs';

  @override
  String get libraryPlaylists => 'Playlists';

  @override
  String get libraryAlbums => 'Albums';

  @override
  String get libraryArtists => 'Artists';

  @override
  String get libraryRefreshDismissTooltip => 'Dismiss refresh message';

  @override
  String get authCloseTooltip => 'Close sign in';

  @override
  String authSignInTitle(String provider) {
    return 'Sign in to $provider';
  }

  @override
  String get authIntroductionMultiple =>
      'Authorize with QQ or WeChat QR. Passwords are never collected.';

  @override
  String authIntroductionSingle(String provider) {
    return 'Use the official $provider app to scan this code. Passwords are never collected.';
  }

  @override
  String get authScanWithQq => 'Scan with QQ';

  @override
  String get authScanWithWechat => 'Scan with WeChat';

  @override
  String authScanWithProvider(String provider) {
    return 'Scan with $provider';
  }

  @override
  String get authCreatingCodeTitle => 'Creating a secure code…';

  @override
  String authConnectingProvider(String provider) {
    return 'Connecting directly to $provider.';
  }

  @override
  String get authConnectingQq => 'Connecting directly to QQ authorization.';

  @override
  String get authConnectingWechat =>
      'Connecting directly to WeChat and QQ Music.';

  @override
  String get authCheckingSavedSession => 'Checking your saved session…';

  @override
  String get authSavedSessionFound => 'Saved session found';

  @override
  String authConfirmingSavedSession(String provider) {
    return 'Confirming it directly with $provider before restoring access.';
  }

  @override
  String authSavedSessionNeedsVerification(String provider) {
    return 'It passed local checks but still needs $provider verification.';
  }

  @override
  String get authChooseMethod => 'Choose a sign-in method';

  @override
  String get authSignedOutStorageTitle =>
      'Signed out, but saved session remains';

  @override
  String authSignedOutStorageDetail(String provider) {
    return 'The active $provider session was cleared, but secure storage could not remove its saved copy. It may appear again after restart.';
  }

  @override
  String get authSavedSessionExpiredTitle => 'Saved session expired';

  @override
  String authSavedSessionExpiredDetail(Object provider) {
    return '$provider’s advertised lifetime has ended. Sign in again to continue.';
  }

  @override
  String get authSavedSessionOtherVersionTitle =>
      'Saved session is from another version';

  @override
  String get authSavedSessionOtherVersionDetail =>
      'This build left it unchanged instead of guessing. You can replace it by signing in again.';

  @override
  String get authStorageUnavailableTitle => 'Secure storage is unavailable';

  @override
  String get authStorageUnavailableDetail =>
      'You can sign in for this run, but the session may not survive restart.';

  @override
  String get authCoreUnavailableTitle => 'The music core is unavailable';

  @override
  String get authRestoreCoreUnavailableDetail =>
      'The stored session could not be checked safely. Try again after restart.';

  @override
  String get authSavedSessionUnreadableTitle =>
      'Saved session could not be read';

  @override
  String get authSavedSessionUnreadableDetail =>
      'It was left unchanged instead of being treated as a valid login. You can replace it by signing in again.';

  @override
  String get authRemovingSavedSession => 'Removing saved session…';

  @override
  String get authRemoveSavedSessionAgain => 'Try removing it again';

  @override
  String get authTryVerificationAgain => 'Try verification again';

  @override
  String get authSignInAgain => 'Sign in again';

  @override
  String get authSavedSessionRejectedTitle => 'Saved session was rejected';

  @override
  String authSavedSessionRejectedDetail(Object provider) {
    return '$provider no longer accepts it, so the stored session was removed.';
  }

  @override
  String authSavedSessionRejectedCleanupDetail(Object provider) {
    return '$provider no longer accepts it, but secure storage could not remove it. It may appear again after restart.';
  }

  @override
  String authCouldNotReachProviderTitle(Object provider) {
    return 'Couldn’t reach $provider';
  }

  @override
  String get authSavedSessionNetworkDetail =>
      'The saved session is still available. Check your connection and try again.';

  @override
  String authProviderUnavailableTitle(Object provider) {
    return '$provider is unavailable';
  }

  @override
  String get authSavedSessionServiceDetail =>
      'The saved session was kept unchanged. Try verification again later.';

  @override
  String authProviderChangedResponseTitle(Object provider) {
    return '$provider changed its response';
  }

  @override
  String get authSavedSessionInvalidResponseDetail =>
      'The saved session was kept instead of being treated as signed out.';

  @override
  String get authSavedSessionVerifyCoreDetail =>
      'The saved session could not be verified safely. Try again after restart.';

  @override
  String get authSavedSessionNotCurrentTitle =>
      'Saved session is no longer current';

  @override
  String get authSignInAgainDetail => 'Sign in again to continue.';

  @override
  String get authConfirmPhoneTitle => 'Confirm on your phone';

  @override
  String get authReconnectingTitle => 'Reconnecting…';

  @override
  String get authCodeScannedProviderDetail =>
      'The code was scanned. Approve the sign-in in the official app.';

  @override
  String get authCodeScannedQqDetail =>
      'The code was scanned. Approve the sign-in in QQ.';

  @override
  String get authCodeScannedWechatDetail =>
      'The code was scanned. Approve the sign-in in WeChat.';

  @override
  String get authReconnectingDetail =>
      'Your code is still active. We’ll retry the connection.';

  @override
  String authOpenProviderScanDetail(Object provider) {
    return 'Open $provider, choose Scan, then point your camera here.';
  }

  @override
  String get authOpenQqScanDetail =>
      'Open QQ, choose Scan, then point your camera here.';

  @override
  String get authOpenWechatScanDetail =>
      'Open WeChat, choose Scan, then point your camera here.';

  @override
  String authProviderQrSemantics(Object provider) {
    return '$provider sign-in QR code';
  }

  @override
  String get authQqQrSemantics => 'QQ sign-in QR code';

  @override
  String get authWechatQrSemantics => 'WeChat sign-in QR code';

  @override
  String get authQqLogin => 'QQ login';

  @override
  String get authWechatLogin => 'WeChat login';

  @override
  String get authQuickLoginTitle => 'Quick login';

  @override
  String get authQuickLoginDetail =>
      'Use an account already signed in to desktop QQ.';

  @override
  String get authNewCode => 'New code';

  @override
  String get authOpenQrExternally => 'Open in system browser or NetEase app';

  @override
  String get authOpeningQrExternally => 'Opening confirmation page…';

  @override
  String get authOpenQrExternallyFailed =>
      'The system could not open this confirmation page. Scan the QR code on another device.';

  @override
  String get authSignedInTitle => 'You’re signed in';

  @override
  String authSavingSessionDetail(Object provider) {
    return '$provider accepted this session. Saving it to platform secure storage…';
  }

  @override
  String get authSavedSessionReadyDetail =>
      'This session is stored securely and ready for this run.';

  @override
  String get authSessionOnlyDetail =>
      'You’re signed in for this session, but secure storage was unavailable. You’ll need to sign in again after restart.';

  @override
  String authStorageNotConfirmedDetail(Object provider) {
    return '$provider accepted this session. Secure storage has not been confirmed.';
  }

  @override
  String get authCodeExpiredTitle => 'This code expired';

  @override
  String get authCodeExpiredDetail =>
      'Create a fresh code to continue signing in.';

  @override
  String get authNotApprovedTitle => 'Sign-in wasn’t approved';

  @override
  String get authNotApprovedDetail =>
      'Nothing changed on your account. You can try again.';

  @override
  String authSecurityVerificationTitle(Object provider) {
    return '$provider requires an additional security check';
  }

  @override
  String get authSecurityVerificationDetail =>
      'This QR sign-in triggered the provider’s security verification. Fura will not bypass it; create a fresh code and try again later.';

  @override
  String authSecondaryVerificationTitle(Object provider) {
    return '$provider requires a second verification step';
  }

  @override
  String get authSecondaryVerificationDetail =>
      'Continue on the official NetEase website to complete the provider-controlled verification.';

  @override
  String get authServiceRejectedDetail =>
      'The service did not accept this request. Try again in a moment.';

  @override
  String get authRejectedTitle => 'Sign-in was rejected';

  @override
  String get authRejectedDetail =>
      'The authorization was not accepted. Choose a method and try again.';

  @override
  String get authNetworkFailuresTitle => 'Connection keeps dropping';

  @override
  String get authNetworkFailuresDetail =>
      'Check your network, then create a fresh code.';

  @override
  String get authInvalidResponseDetail =>
      'This client stopped safely instead of guessing. Try a new code later.';

  @override
  String get authCouldNotContinueTitle => 'Couldn’t continue sign-in';

  @override
  String get authCouldNotContinueDetail =>
      'Try this session again or create a new code.';

  @override
  String authAnnouncementSemantics(Object detail, Object title) {
    return '$title. $detail';
  }

  @override
  String get authCheckingDesktopQq => 'Checking desktop QQ…';

  @override
  String get authOpenDesktopQqDetail =>
      'Open and sign in to desktop QQ to use quick login.';

  @override
  String get authNoDesktopAccount =>
      'No signed-in desktop QQ account was found.';

  @override
  String get authDesktopClientUnavailable =>
      'Desktop QQ is not available. Open QQ and try again.';

  @override
  String get authDesktopNetworkFailure =>
      'Desktop QQ authorization could not reach QQ Music.';

  @override
  String get authDesktopServiceUnavailable =>
      'QQ authorization is temporarily unavailable.';

  @override
  String get authDesktopRejected =>
      'Desktop QQ did not approve this authorization.';

  @override
  String get authDesktopInvalidResponse =>
      'Desktop QQ returned a response this build could not verify.';

  @override
  String get authDesktopAttemptInactive =>
      'This quick-login attempt is no longer active. Retry discovery.';

  @override
  String get authDesktopAlreadyRunning =>
      'Desktop QQ authorization is already in progress.';

  @override
  String get authDesktopCoreUnavailable =>
      'The music core could not start desktop QQ authorization.';

  @override
  String get authDesktopUnavailable => 'Desktop QQ quick login is unavailable.';

  @override
  String get authUsePhoneCode => 'Use phone code';

  @override
  String get authUseQrCode => 'Use QR code';

  @override
  String get authUseOfficialWebsite => 'Continue on NetEase website';

  @override
  String get authOfficialWebTitle => 'Complete sign-in with NetEase';

  @override
  String get authOfficialWebDetail =>
      'Use the official login window. Fura will import only the resulting session and verify it before saving.';

  @override
  String get authOfficialWebErrorTitle =>
      'Official NetEase sign-in did not finish';

  @override
  String get authOfficialWebUnavailable =>
      'The official login window is not available on this device.';

  @override
  String get authOfficialWebRejected =>
      'NetEase did not accept the completed website session.';

  @override
  String get authOfficialWebNetwork =>
      'The completed website session could not be verified because the connection failed.';

  @override
  String get authOfficialWebServiceUnavailable =>
      'NetEase accepted the website interaction but its account verification service is unavailable.';

  @override
  String get authOfficialWebInvalidCredential =>
      'The official window did not return a session Fura can validate.';

  @override
  String get authOfficialWebAlreadyRunning =>
      'An official NetEase login window is already open.';

  @override
  String get authOfficialWebFailed =>
      'The official login window could not complete safely. No session was saved.';

  @override
  String get authOfficialWebLoading =>
      'Loading the official NetEase sign-in page';

  @override
  String get authOfficialWebWaiting =>
      'Complete sign-in on the official page. Fura will verify the resulting session before saving it.';

  @override
  String get authOfficialWebSystemBrowserWaiting =>
      'A private system-browser window is open. Complete sign-in there; Fura will close it after securely reading and verifying the resulting session.';

  @override
  String get authOfficialWebVerifying => 'Verifying your NetEase account';

  @override
  String get authOfficialWebTimedOut =>
      'The official login session timed out. Start a new attempt.';

  @override
  String get authOfficialWebCleanupFailed =>
      'Fura could not clear the temporary website session. No credential was saved.';

  @override
  String get authSignedOutWebCleanupTitle =>
      'Signed out, but website cleanup needs attention';

  @override
  String authSignedOutWebCleanupDetail(String providerName) {
    return 'The $providerName account and saved session were removed, but Fura could not confirm that the temporary website data was cleared.';
  }

  @override
  String get authPhoneCodeTitle => 'Sign in with a phone code';

  @override
  String get authPhoneCodeDetail =>
      'Request a one-time code for the phone number linked to NetEase Cloud Music.';

  @override
  String get authCountryCode => 'Country code';

  @override
  String get authPhoneNumber => 'Phone number';

  @override
  String get authSmsCode => 'Verification code';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authResendCode => 'Resend code';

  @override
  String authResendCodeIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authCodeSent => 'Code sent. Check your messages.';

  @override
  String get authSmsSignIn => 'Sign in';

  @override
  String get authSendingCode => 'Sending code…';

  @override
  String get authCheckingSmsCode => 'Checking code…';

  @override
  String get authSmsRiskWarning =>
      'NetEase may still require an additional security check. Fura will stop and report it instead of bypassing the check.';

  @override
  String get authSmsInvalidInput =>
      'Enter a valid country code, phone number, and verification code using digits only.';

  @override
  String get authSmsCodeRejected =>
      'That verification code was not accepted. Check it and try again.';

  @override
  String get authSmsRateLimited =>
      'Too many requests were made. Wait before requesting another code.';

  @override
  String get authSmsSecurityVerification =>
      'NetEase requires an additional security check for this phone login. Fura cannot bypass it.';

  @override
  String get authSmsSecondaryVerification =>
      'NetEase requires an interactive second verification. Continue on the official website to finish sign-in.';

  @override
  String get authSmsNetworkFailure =>
      'Couldn’t reach NetEase. Check your connection and try again.';

  @override
  String get authSmsServiceUnavailable =>
      'NetEase phone login is temporarily unavailable. Try again later or use QR sign-in.';

  @override
  String get authSmsInvalidResponse =>
      'NetEase returned a response this version could not verify. No login was installed.';

  @override
  String get authSmsAlreadyRunning =>
      'A phone login request is already in progress.';

  @override
  String get authSmsAttemptReplaced =>
      'This phone login is no longer current. Request a new code.';

  @override
  String get authSmsCoreUnavailable =>
      'The music core could not continue phone login.';

  @override
  String get searchSongHint => 'Song, artist, or album name';

  @override
  String get searchArtistHint => 'Artist name';

  @override
  String get searchAlbumHint => 'Album name';

  @override
  String get searchPlaylistHint => 'Playlist name';

  @override
  String get searchTypeLabel => 'Search type';

  @override
  String searchSuggestionSubmit(String query) {
    return 'Search “$query”';
  }

  @override
  String get searchTracksType => 'Tracks';

  @override
  String get searchArtistsType => 'Artists';

  @override
  String get searchAlbumsType => 'Albums';

  @override
  String get searchPlaylistsType => 'Playlists';

  @override
  String get searchBackTooltip => 'Back to your music';

  @override
  String searchProviderTitle(Object provider) {
    return 'Search $provider';
  }

  @override
  String searchFindTracksTitle(Object provider) {
    return 'Find tracks on $provider';
  }

  @override
  String get searchTrackPrompt => 'Search by song, artist, or album name.';

  @override
  String searchLoadingTracks(Object provider) {
    return 'Searching $provider tracks';
  }

  @override
  String get searchNoTracksTitle => 'No tracks found';

  @override
  String get searchNoResultsDetail =>
      'Try a different spelling or a broader search.';

  @override
  String get searchEditAction => 'Edit search';

  @override
  String searchFindArtistsTitle(Object provider) {
    return 'Find artists on $provider';
  }

  @override
  String get searchArtistPrompt => 'Search by an artist or group name.';

  @override
  String searchLoadingArtists(Object provider) {
    return 'Searching $provider artists';
  }

  @override
  String get searchNoArtistsTitle => 'No artists found';

  @override
  String searchFindAlbumsTitle(Object provider) {
    return 'Find albums on $provider';
  }

  @override
  String get searchAlbumPrompt => 'Search by an album name.';

  @override
  String searchLoadingAlbums(Object provider) {
    return 'Searching $provider albums';
  }

  @override
  String get searchNoAlbumsTitle => 'No albums found';

  @override
  String searchFindPlaylistsTitle(Object provider) {
    return 'Find playlists on $provider';
  }

  @override
  String get searchPlaylistPrompt => 'Search by a public playlist name.';

  @override
  String searchLoadingPlaylists(Object provider) {
    return 'Searching $provider playlists';
  }

  @override
  String get searchNoPlaylistsTitle => 'No playlists found';

  @override
  String searchFailureTitle(Object provider) {
    return 'Couldn’t search $provider';
  }

  @override
  String get queueAddedMessage => 'Added to queue';

  @override
  String get queueUpdateFailureMessage => 'Couldn’t update the queue';

  @override
  String searchResultCount(int count, String query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results for “$query”',
      one: '1 result for “$query”',
    );
    return '$_temp0';
  }

  @override
  String searchArtistResultCount(num count, Object query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artists for ‘$query’',
      one: '1 Artist for ‘$query’',
    );
    return '$_temp0';
  }

  @override
  String searchAlbumResultCount(num count, Object query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Albums for ‘$query’',
      one: '1 Album for ‘$query’',
    );
    return '$_temp0';
  }

  @override
  String searchPlaylistResultCount(num count, Object query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Playlists for ‘$query’',
      one: '1 Playlist for ‘$query’',
    );
    return '$_temp0';
  }

  @override
  String get searchArtistResultType => 'Artist';

  @override
  String get searchAlbumResultType => 'Album';

  @override
  String get searchPlaylistResultType => 'Playlist';

  @override
  String trackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get searchBrowseCreditedArtists => 'Browse credited artists';

  @override
  String searchOpenNamedAlbum(Object albumTitle) {
    return 'Open $albumTitle';
  }

  @override
  String get searchEndOfResults => 'End of results';

  @override
  String get searchNetworkFailure => 'Check your connection and try again.';

  @override
  String get searchServiceUnavailable =>
      'This music service’s search is temporarily unavailable.';

  @override
  String get searchCancelled => 'The search was cancelled.';

  @override
  String get searchCoreUnavailable =>
      'The local music core is unavailable. Restart the app and try again.';

  @override
  String get searchUnexpectedResponse =>
      'The music service returned an unexpected search response.';

  @override
  String get searchArtistServiceUnavailable =>
      'Artist search is temporarily unavailable.';

  @override
  String get searchArtistCancelled => 'The artist search was cancelled.';

  @override
  String get searchArtistUnexpectedResponse =>
      'The music service returned an unexpected artist search response.';

  @override
  String get searchAlbumServiceUnavailable =>
      'Album search is temporarily unavailable.';

  @override
  String get searchAlbumCancelled => 'The album search was cancelled.';

  @override
  String get searchAlbumUnexpectedResponse =>
      'The music service returned an unexpected album search response.';

  @override
  String get searchPlaylistServiceUnavailable =>
      'Playlist search is temporarily unavailable.';

  @override
  String get searchPlaylistCancelled => 'The playlist search was cancelled.';

  @override
  String get searchPlaylistUnexpectedResponse =>
      'The music service returned an unexpected playlist search response.';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get discoverBackTooltip => 'Back to your music';

  @override
  String discoverSubtitleWithRadar(Object provider) {
    return 'Playlists, charts, Radar, and new releases from $provider';
  }

  @override
  String discoverSubtitleWithoutRadar(Object provider) {
    return 'Playlists, charts, and new releases from $provider';
  }

  @override
  String get discoverPlaylistsTab => 'Playlists';

  @override
  String get discoverRankingsTab => 'Rankings';

  @override
  String get discoverRadarTab => 'Radar';

  @override
  String get discoverNewAlbumsTab => 'New albums';

  @override
  String get discoverNewSongsTab => 'New songs';

  @override
  String get discoverLoadingRecommendations => 'Loading recommended playlists';

  @override
  String get discoverNoRecommendationsTitle => 'No recommendations right now';

  @override
  String discoverNoRecommendationsDetail(Object provider) {
    return '$provider returned an empty recommended-playlist page.';
  }

  @override
  String get discoverRecommendationsFailureTitle =>
      'Couldn’t load recommendations';

  @override
  String discoverLoadingRankings(Object provider) {
    return 'Loading $provider Rankings';
  }

  @override
  String get discoverNoRankingsTitle => 'No rankings right now';

  @override
  String discoverNoRankingsDetail(Object provider) {
    return '$provider returned no current rankings.';
  }

  @override
  String get discoverRankingsFailureTitle => 'Couldn’t load rankings';

  @override
  String get discoverLoadingRadar => 'Loading QQ Music Radar';

  @override
  String get discoverNoRadarTitle => 'No Radar tracks right now';

  @override
  String get discoverNoRadarDetail =>
      'QQ Music returned an empty Radar track page.';

  @override
  String get discoverRadarFailureTitle => 'Couldn’t load Radar';

  @override
  String get discoverReloadRadar => 'Reload Radar';

  @override
  String get discoverRefreshRadar => 'Refresh Radar';

  @override
  String get discoverLoadingNewAlbums => 'Loading new albums';

  @override
  String get discoverNoNewAlbumsTitle => 'No new albums right now';

  @override
  String discoverNoNewAlbumsDetail(Object provider) {
    return '$provider returned no albums here.';
  }

  @override
  String get discoverNewAlbumsFailureTitle => 'Couldn’t load new albums';

  @override
  String get discoverLoadingNewSongs => 'Loading New Songs';

  @override
  String get discoverNoNewSongsTitle => 'No new songs right now';

  @override
  String discoverNoNewSongsDetail(Object provider) {
    return '$provider returned no tracks here.';
  }

  @override
  String get discoverNewSongsFailureTitle => 'Couldn’t load new songs';

  @override
  String get discoverEndNewAlbums => 'End of new albums';

  @override
  String get discoverEndRadar => 'End of Radar recommendations';

  @override
  String get discoverEndRecommendations => 'End of recommendations';

  @override
  String get discoverMusicServicePlaylist => 'Music service playlist';

  @override
  String get discoverCurrentRanking => 'Current ranking';

  @override
  String get discoverAlbumType => 'Album';

  @override
  String get discoverRecommendationServiceFailure =>
      'Recommendations are temporarily unavailable.';

  @override
  String get discoverRecommendationCancelled =>
      'The recommendation request was cancelled.';

  @override
  String get discoverRecommendationUnexpected =>
      'The music service returned an unexpected recommendation response.';

  @override
  String get discoverRadarAuthenticationRequired =>
      'Sign in to load QQ Music Radar Tracks.';

  @override
  String get discoverRadarCredentialRejected =>
      'Your QQ Music session expired. Sign in again to continue.';

  @override
  String get discoverRadarCredentialCleanupFailure =>
      'Your QQ Music session expired, but its saved copy could not be removed. Sign in again after checking secure storage.';

  @override
  String get discoverRadarServiceFailure =>
      'QQ Music Radar is temporarily unavailable.';

  @override
  String get discoverRadarAccountChanged =>
      'The signed-in account changed while Radar was loading.';

  @override
  String get discoverRadarCancelled => 'The Radar request was cancelled.';

  @override
  String get discoverRadarUnexpected =>
      'QQ Music returned an unexpected Radar response.';

  @override
  String get discoverNewAlbumServiceFailure =>
      'New albums are temporarily unavailable.';

  @override
  String get discoverNewAlbumCancelled =>
      'The new-album request was cancelled.';

  @override
  String get discoverNewAlbumUnexpected =>
      'The music service returned an unexpected new-album response.';

  @override
  String get discoverNewSongServiceFailure =>
      'New songs are temporarily unavailable.';

  @override
  String get discoverNewSongCancelled => 'The new-song request was cancelled.';

  @override
  String get discoverNewSongUnexpected =>
      'The music service returned an unexpected new-song response.';

  @override
  String get discoverRegionMainlandChina => 'Mainland China';

  @override
  String get discoverRegionHongKongTaiwan => 'Hong Kong / Taiwan';

  @override
  String get discoverRegionWestern => 'Western';

  @override
  String get discoverRegionKorea => 'Korea';

  @override
  String get discoverRegionJapan => 'Japan';

  @override
  String get discoverRegionOther => 'Other';

  @override
  String get discoverCategoryLatest => 'Latest';

  @override
  String get rankingTitle => 'Ranking';

  @override
  String get rankingBackTooltip => 'Back to rankings';

  @override
  String get rankingLoadingTracks => 'Loading ranking tracks';

  @override
  String get rankingEmptyTitle => 'This ranking has no available tracks';

  @override
  String rankingEmptyDetail(Object provider) {
    return '$provider returned an empty current-ranking track list.';
  }

  @override
  String get rankingFailureTitle => 'Couldn’t load this ranking';

  @override
  String get rankingEyebrow => 'QQ MUSIC RANKING';

  @override
  String rankingShowingTracks(Object shown, Object total) {
    return 'Showing $shown of $total tracks';
  }

  @override
  String get rankingEnd => 'End of current ranking';

  @override
  String rankingServiceFailure(Object provider) {
    return '$provider rankings are temporarily unavailable.';
  }

  @override
  String get rankingCancelled => 'The ranking request was cancelled.';

  @override
  String rankingUnexpected(Object provider) {
    return '$provider returned an unexpected ranking response.';
  }

  @override
  String get commonNetworkFailure => 'Check your connection and try again.';

  @override
  String get commonCoreUnavailable =>
      'The local music core is unavailable. Restart the app and try again.';

  @override
  String get commonSeeAll => 'See all';

  @override
  String commonUnavailableSemantics(Object label) {
    return '$label, unavailable';
  }

  @override
  String get homeRecommendationsSemantics => 'Home recommendations';

  @override
  String get homeRefreshPartialFailure =>
      'Some recommendations could not refresh. You can retry each section.';

  @override
  String homeRefreshSuccess(Object provider) {
    return 'Recommendations refreshed. $provider may return the same picks.';
  }

  @override
  String get homeRefreshWarning =>
      'Some picks could not refresh. Showing the last available recommendations; use Refresh to retry.';

  @override
  String get homePlaylistTreasures => 'Your playlist treasures';

  @override
  String get homePopularPlaylists => 'Popular playlists';

  @override
  String get homeRefreshing => 'Refreshing…';

  @override
  String get homePersonalFm => 'Personal FM';

  @override
  String get homeSongsPickedForYou => 'Songs picked for you';

  @override
  String get homeNewSongs => 'New songs';

  @override
  String get homeFreshReleases => 'Fresh releases';

  @override
  String get homePublicPlaylists => 'Public playlists';

  @override
  String get homeMoreFromListening => 'More from your listening';

  @override
  String get homeChangePicks => 'Change picks';

  @override
  String get homeRecommendTab => 'Recommend';

  @override
  String get homeMusicTab => 'Music';

  @override
  String get homeAudiobooksTab => 'Audiobooks';

  @override
  String get homeAudiobooksUnavailable => 'Audiobooks are not available';

  @override
  String get homePodcastsTab => 'Podcasts';

  @override
  String get homePodcastsUnavailable =>
      'Podcasts are outside the current product scope';

  @override
  String get homeSignOut => 'Sign out';

  @override
  String homeSignInToProvider(Object provider) {
    return 'Sign in to $provider';
  }

  @override
  String get homeForYouEyebrow => 'FOR YOU';

  @override
  String get homePublicSpotlightEyebrow => 'PUBLIC SPOTLIGHT';

  @override
  String get homeSelectedForYou => 'Selected for you';

  @override
  String get homeTodaysPick => 'Today’s pick';

  @override
  String get homeLoadingRecommendations => 'Loading recommendations…';

  @override
  String get homeRecommendationsUnavailable =>
      'Recommendations are unavailable. Please try again.';

  @override
  String get homeNoRecommendations =>
      'No recommendations right now. You can browse Discover.';

  @override
  String get homePopularPlaylist => 'Popular playlist';

  @override
  String get homeDailyTracks => 'Daily tracks';

  @override
  String get homeDailyRecommendation => 'Daily recommendation';

  @override
  String get homeRadar => 'Radar';

  @override
  String get homeMusicService => 'Music service';

  @override
  String homeTrackPlaySemantics(
    Object artists,
    Object label,
    Object trackTitle,
  ) {
    return '$label, $trackTitle, $artists. Play';
  }

  @override
  String get homePreviousSpotlight => 'Previous spotlight';

  @override
  String get homePauseSpotlight => 'Pause spotlight rotation';

  @override
  String get homeResumeSpotlight => 'Resume spotlight rotation';

  @override
  String get homeNextSpotlight => 'Next spotlight';

  @override
  String homeRetrySection(Object title) {
    return 'Retry $title';
  }

  @override
  String get homeLoadingPublicPlaylists => 'Loading public playlists';

  @override
  String get homeNoPublicPlaylists => 'No public playlists right now';

  @override
  String homeNoPublicPlaylistsDetail(Object provider) {
    return '$provider did not return any public playlist recommendations.';
  }

  @override
  String get homePublicPlaylistsFailure => 'Couldn’t load public playlists';

  @override
  String get homeNoAdditionalPublicPlaylists =>
      'No additional public playlists right now';

  @override
  String get homeAvailablePublicShown =>
      'The available public recommendations are shown above.';

  @override
  String get homeLoadingPublicNewSongs => 'Loading public new songs';

  @override
  String get homeNoNewSongs => 'No new songs right now';

  @override
  String homeNoNewSongsDetail(Object provider) {
    return '$provider did not return a public new-song collection.';
  }

  @override
  String get homeNewSongsFailure => 'Couldn’t load new songs';

  @override
  String get homeLoadingYourPlaylists => 'Loading your playlists';

  @override
  String get homeNoPersonalizedPlaylists =>
      'No personalized playlists right now';

  @override
  String get homeNoPersonalizedPlaylistsDetail =>
      'Try refreshing later, or browse public playlists in Discover.';

  @override
  String homePersonalizedPlaylistSemantics(Object title) {
    return '$title, personalized playlist';
  }

  @override
  String get homeDiscoverAction => 'Discover';

  @override
  String get homeDailyAction => 'Daily';

  @override
  String get homeRankingsAction => 'Rankings';

  @override
  String get homeLikedAction => 'Liked';

  @override
  String get homeLoadingPersonalFm => 'Loading Personal FM';

  @override
  String get homeLoadingPersonalizedSongs => 'Loading personalized songs';

  @override
  String get homePersonalFmEmpty => 'Personal FM has no songs right now';

  @override
  String get homePersonalizedSongsEmpty => 'No personalized songs right now';

  @override
  String get homePersonalizedSongsEmptyDetail =>
      'Public playlists and your Library remain available.';

  @override
  String get homePersonalFmFailure => 'Couldn’t load Personal FM';

  @override
  String get homePersonalizedSongsFailure => 'Couldn’t load personalized songs';

  @override
  String get homeOtherSectionsAvailable =>
      'Other Home sections are still available.';

  @override
  String homeLoadingRelatedSongs(Object seed) {
    return 'Loading songs related to $seed';
  }

  @override
  String get homeRecentListening => 'your recent listening';

  @override
  String get homeStartListeningTitle => 'Start listening to discover more';

  @override
  String get homeStartListeningDetail =>
      'After listening in fura, picks inspired by a recently heard song appear here. Listening history stays in this session.';

  @override
  String get homeNoRelatedSongs => 'No related songs right now';

  @override
  String homeNoRelatedSongsDetail(Object seed) {
    return 'The track’s music service returned no related songs for “$seed”.';
  }

  @override
  String homeBecauseListened(Object seed) {
    return 'Because you listened to “$seed”';
  }

  @override
  String get homeRecentSong => 'a recent song';

  @override
  String homeAddTrackToQueue(Object trackTitle) {
    return 'Add $trackTitle to queue';
  }

  @override
  String get homeMoreRecommendationsUnavailable =>
      'More recommendations aren’t available';

  @override
  String get homePrimaryRecommendationShown =>
      'The primary recommendation state is shown above.';

  @override
  String get homePreviousPlaylists => 'Previous playlists';

  @override
  String get homeNextPlaylists => 'Next playlists';

  @override
  String get homePersonalizedInvalidTitle =>
      'Personalized playlist response not recognized';

  @override
  String get homePersonalizedOfflineTitle =>
      'Personalized playlists are offline';

  @override
  String get homePersonalizedUnavailableTitle =>
      'Personalized playlists are temporarily unavailable';

  @override
  String get homePersonalizedReplacedTitle =>
      'Personalized playlist request was replaced';

  @override
  String get homePersonalizedCancelledTitle =>
      'Personalized playlist request was cancelled';

  @override
  String get homePersonalizedRunningTitle =>
      'Personalized playlists are already loading';

  @override
  String get homePersonalizedFailureTitle =>
      'Couldn’t load personalized playlists';

  @override
  String homePersonalizedInvalidDetail(Object provider) {
    return '$provider returned a personalized-playlist structure this client does not recognize. No account content was recorded.';
  }

  @override
  String get homeNetworkRetryDetail =>
      'Check the network connection, then try again.';

  @override
  String homePersonalizedServiceDetail(Object provider) {
    return '$provider rejected or could not serve this request. Try again later.';
  }

  @override
  String get homePersonalizedReplacedDetail =>
      'A newer authenticated recommendation request replaced this one.';

  @override
  String get homePersonalizedCancelledDetail =>
      'The request ended before personalized playlists were returned.';

  @override
  String get homePersonalizedRunningDetail =>
      'Wait for the active personalized-playlist request to finish.';

  @override
  String get homePublicAndSearchAvailable =>
      'Public recommendations and Search are still available.';

  @override
  String get homeRelatedInvalidTitle => 'This song can’t seed recommendations';

  @override
  String get homeRelatedOfflineTitle => 'Related songs are offline';

  @override
  String get homeRelatedUnavailableTitle =>
      'Related songs are temporarily unavailable';

  @override
  String get homeRelatedInvalidResponseTitle =>
      'Related-song response not recognized';

  @override
  String get homeRelatedCancelledTitle => 'Related-song request was cancelled';

  @override
  String get homeRelatedRunningTitle => 'Related songs are already loading';

  @override
  String get homeRelatedFailureTitle => 'Couldn’t load related songs';

  @override
  String homeRelatedInvalidTrackDetail(Object seed) {
    return '“$seed” has no usable music-service identity.';
  }

  @override
  String get homeThisSong => 'This song';

  @override
  String get homeRelatedServiceDetail =>
      'The track’s music service could not serve related songs for this seed right now.';

  @override
  String get homeRelatedInvalidResponseDetail =>
      'The track’s music service returned a related-song structure this client does not recognize.';

  @override
  String get homeRelatedCancelledDetail =>
      'The seed changed before related songs were returned.';

  @override
  String get homeRelatedRunningDetail =>
      'Wait for the active related-song request to finish.';

  @override
  String get homeRelatedCoreDetail =>
      'The related-song Core capability could not be reached.';

  @override
  String get homePublicLoading => 'Loading public recommendations…';

  @override
  String get homePublicNoAdditional =>
      'No additional public recommendation is available right now.';

  @override
  String homePublicEmpty(Object provider) {
    return '$provider has no public recommendation available right now.';
  }

  @override
  String get homePublicFailure => 'Public recommendations could not be loaded.';

  @override
  String get homeLoadingDailyTracks => 'Loading your daily tracks…';

  @override
  String get homeLoadingDaily30 => 'Loading your Daily 30…';

  @override
  String get homeDailyTracksUnavailable =>
      'Daily tracks are unavailable right now.';

  @override
  String get homeDaily30Unavailable => 'Daily 30 is unavailable right now.';

  @override
  String get homeDailyTracksFailure => 'Daily tracks could not be loaded.';

  @override
  String get homeDaily30Failure => 'Daily 30 could not be loaded.';

  @override
  String get homeRadarLoading => 'Loading your Radar recommendations…';

  @override
  String get homeRadarUnavailable => 'Radar is unavailable right now.';

  @override
  String get homeRadarEmpty =>
      'QQ Music has no Radar recommendation right now.';

  @override
  String get homeRadarFailure => 'Radar recommendations could not be loaded.';

  @override
  String get homePublicNewSongsLoading => 'Loading public new songs…';

  @override
  String get homePublicNewSongsUnavailable =>
      'No public new song is available right now.';

  @override
  String homePublicNewSongsEmpty(Object provider) {
    return '$provider has no public new songs right now.';
  }

  @override
  String get homePublicNewSongsFailure =>
      'Public new songs could not be loaded.';

  @override
  String homeNewSongsServiceFailure(Object provider) {
    return '$provider new songs are temporarily unavailable.';
  }

  @override
  String homeNewSongsInvalidResponse(Object provider) {
    return '$provider returned a new-song response this client does not recognize.';
  }

  @override
  String get homeNewSongsRunning =>
      'Wait for the active new-song request to finish.';

  @override
  String get homeMusicPlaylist => 'Music playlist';

  @override
  String homeMusicPlaylistSemantics(Object title) {
    return '$title, music playlist';
  }

  @override
  String get libraryPlaylistType => 'Playlist';

  @override
  String get libraryTrackCountColumn => 'Tracks';

  @override
  String get libraryBackToPlaylists => 'Back to playlists';

  @override
  String get libraryRefreshingPlaylist => 'Refreshing playlist';

  @override
  String get libraryRefreshPlaylist => 'Refresh playlist';

  @override
  String get libraryPlaylistEmptyTitle => 'This playlist is empty';

  @override
  String libraryPlaylistEmptyDetail(Object provider) {
    return 'Tracks added in $provider will appear here.';
  }

  @override
  String libraryPlaylistCountSummary(num count, Object provider) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0 · $provider';
  }

  @override
  String libraryPlaylistEnd(Object total) {
    return 'All $total tracks are loaded';
  }

  @override
  String get libraryRefreshPlaylistFailure =>
      'Couldn’t refresh this playlist. The previous tracks are still shown.';

  @override
  String get likedTitle => 'Liked';

  @override
  String get likedProgramsUnavailableTitle =>
      'Liked audio programs aren’t connected yet';

  @override
  String get likedProgramsUnavailableDetail =>
      'The current account-library capability includes songs, playlists, albums, and artists, but not audio-program favorites.';

  @override
  String get likedVideosUnavailableTitle => 'Liked videos aren’t connected yet';

  @override
  String get likedVideosUnavailableDetail =>
      'Music videos linked to songs are not the same as the account’s liked videos, so they are not mixed here.';

  @override
  String get likedPlaylistUnavailableTitle =>
      'Couldn’t find the Liked Songs playlist';

  @override
  String likedPlaylistUnavailableDetail(Object provider) {
    return '$provider did not return its built-in Liked Songs playlist. Other favorites are still available from the tabs above.';
  }

  @override
  String get likedLoadingTitle => 'Loading Liked Songs…';

  @override
  String likedLoadingDetail(Object provider) {
    return 'Reading favorites from $provider.';
  }

  @override
  String get likedEmptyTitle => 'No Liked Songs yet';

  @override
  String likedEmptyDetail(Object provider) {
    return 'Songs you like in $provider will appear here.';
  }

  @override
  String get likedSearchingAllTitle => 'Searching the entire playlist…';

  @override
  String get likedNoTrackMatchTitle => 'No matching tracks';

  @override
  String likedSearchProgress(Object processed, Object total) {
    return 'Checked $processed of $total tracks. Matches update while pages load.';
  }

  @override
  String likedSearchFinishedNoMatch(Object omitted, Object total) {
    return 'Searched all $total tracks$omitted; try another keyword.';
  }

  @override
  String get likedContinueSearch => 'Continue search';

  @override
  String get likedQueueAdded => 'Added to playback queue';

  @override
  String likedSongsTab(Object count) {
    return 'Songs $count';
  }

  @override
  String get likedSongsTabWithoutCount => 'Songs';

  @override
  String likedPlaylistsTab(Object count) {
    return 'Playlists $count';
  }

  @override
  String get likedAlbumsTab => 'Albums';

  @override
  String get likedProgramsTab => 'Audio programs';

  @override
  String get likedVideosTab => 'Videos';

  @override
  String get likedNoPlaylistMatch => 'No matching playlists';

  @override
  String get likedNoOtherPlaylists => 'No other playlists yet';

  @override
  String get likedTryAnotherKeyword => 'Try another keyword.';

  @override
  String get likedCreatedPlaylists => 'Created Playlists';

  @override
  String get likedSavedPlaylists => 'Saved Playlists';

  @override
  String get likedOtherPlaylists => 'Other Playlists';

  @override
  String likedPlaylistCollectionDetail(Object provider) {
    return 'Playlists you create or save in $provider will appear here.';
  }

  @override
  String likedPlaylistSectionCount(Object count, Object title) {
    return '$title $count';
  }

  @override
  String likedPlaylistSemantics(Object title) {
    return '$title, playlist';
  }

  @override
  String likedTrackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get likedPlayAll => 'Play all';

  @override
  String get likedRefreshing => 'Refreshing';

  @override
  String get likedRefreshSongs => 'Refresh Liked Songs';

  @override
  String get likedSearchEntirePlaylist => 'Search entire playlist';

  @override
  String get likedSearchPlaylists => 'Search playlists';

  @override
  String get likedSearchLoadedAlbums => 'Search loaded albums';

  @override
  String get likedProgramsSearchUnavailable =>
      'Liked audio programs aren’t connected yet';

  @override
  String get likedVideosSearchUnavailable =>
      'Liked videos aren’t connected yet';

  @override
  String get likedMultipleArtistsDetail =>
      'This track includes multiple artists. Choose the artist to open.';

  @override
  String get likedRetryLoad => 'Retry loading';

  @override
  String likedReadStatus(Object available, Object processed, Object total) {
    return 'Read $processed / $total tracks; $available can be shown';
  }

  @override
  String likedSearchInterruptedStatus(Object processed, Object total) {
    return 'Search interrupted · checked $processed / $total tracks';
  }

  @override
  String get likedSearchInterruptedTitle => 'Search interrupted';

  @override
  String likedSearchInterruptedDetail(Object processed, Object total) {
    return 'Checked $processed of $total tracks. Retry to search the remaining tracks.';
  }

  @override
  String likedOmittedSearchSuffix(Object count) {
    return '; $count tracks have no searchable identity';
  }

  @override
  String likedOmittedTracksDetail(Object count) {
    return '$count tracks have no usable identity. They were skipped without stopping later pages.';
  }

  @override
  String likedExactResults(Object count) {
    return '$count tracks';
  }

  @override
  String likedApproximateResults(Object count) {
    return '$count possible results';
  }

  @override
  String likedSearchingStatus(Object processed, Object results, Object total) {
    return 'Found $results · checking $processed / $total tracks';
  }

  @override
  String likedApproximateOnlyStatus(Object results) {
    return 'No exact matches · showing $results';
  }

  @override
  String likedMixedResults(Object approximate, Object count) {
    return '$count tracks ($approximate possible results)';
  }

  @override
  String likedSearchCompleteStatus(Object results, Object total) {
    return 'Searched all $total tracks · found $results';
  }

  @override
  String get likedFailureNetworkTitle => 'Network unavailable';

  @override
  String get likedFailureNetworkDetail =>
      'Check your connection and try again.';

  @override
  String likedFailureServiceTitle(Object provider) {
    return '$provider is temporarily unavailable';
  }

  @override
  String get likedFailureServiceDetail =>
      'Your session remains unchanged. Try again later.';

  @override
  String get likedFailureSignedOutTitle => 'Sign-in expired';

  @override
  String get likedFailureSignedOutDetail =>
      'Sign in again to load Liked Songs.';

  @override
  String get likedFailureAuthenticationTitle => 'Sign in required';

  @override
  String likedFailureAuthenticationDetail(Object provider) {
    return 'Sign in to $provider to continue.';
  }

  @override
  String get likedFailureInvalidTitle => 'Couldn’t safely read Liked Songs';

  @override
  String get likedFailureInvalidDetail =>
      'Try again. Partial results were not shown.';

  @override
  String get likedFailureCoreTitle => 'Couldn’t load Liked Songs';

  @override
  String get likedFailureCoreDetail =>
      'Try again, or restart the app and retry.';

  @override
  String get likedFailureGenericDetail => 'Try again.';

  @override
  String get likedRefreshNetworkFailure =>
      'Refresh failed: check your network.';

  @override
  String likedRefreshServiceFailure(Object provider) {
    return '$provider cannot refresh right now.';
  }

  @override
  String get likedRefreshInvalidResponse =>
      'The refresh result could not be read safely.';

  @override
  String get likedRefreshFailure =>
      'Refresh failed; the previous result is still shown.';

  @override
  String get recentTitle => 'Recently played';

  @override
  String get recentCloudSubtitle =>
      'QQ Music account playback history · newest first';

  @override
  String get recentCloudNotConnectedShort =>
      'QQ Music cloud history isn’t connected yet';

  @override
  String recentProcessedStatus(
    Object action,
    Object approximate,
    Object omitted,
    Object processed,
    Object total,
  ) {
    return '$action $processed$total tracks$approximate$omitted';
  }

  @override
  String get recentLoadedAction => 'Loaded';

  @override
  String get recentSearchedAction => 'Searched';

  @override
  String recentTotalPart(Object total) {
    return ' / $total';
  }

  @override
  String recentApproximatePart(Object count) {
    return ' · $count approximate matches';
  }

  @override
  String recentOmittedPart(Object count) {
    return ' · $count tracks cannot be shown';
  }

  @override
  String recentSongsTab(Object count) {
    return 'Songs $count';
  }

  @override
  String recentSongsTabApproximate(Object count) {
    return 'Songs $count+';
  }

  @override
  String get recentSongsTabWithoutCount => 'Songs';

  @override
  String get recentSearchHint => 'Search recently played';

  @override
  String get recentRefreshSnapshotFailure =>
      'Refresh failed; the previous records are still shown.';

  @override
  String get recentPlayTooltip => 'Play recently played';

  @override
  String get recentRefreshTooltip => 'Refresh recently played';

  @override
  String get recentUnavailableTitle =>
      'Cross-device playback history is unavailable';

  @override
  String get recentUnavailableDetail =>
      'This version has not connected QQ Music cloud recent play yet.\nOnce connected, playback history for this account will appear here.';

  @override
  String get recentLoadingTitle => 'Reading recently played…';

  @override
  String get recentSignInTitle => 'Sign in to QQ Music again';

  @override
  String get recentSignInDetail =>
      'Sign in to the same account before reading cloud playback history.';

  @override
  String get recentUnavailableTemporaryTitle =>
      'Recently played is temporarily unavailable';

  @override
  String get recentTryLater => 'Try again later.';

  @override
  String get recentEmptyTitle => 'No cloud playback history yet';

  @override
  String get recentEmptyDetail =>
      'Refresh to read the records returned by QQ Music again.';

  @override
  String get recentSearchingAll => 'Searching all playback history…';

  @override
  String get recentNoMatch => 'No matching tracks';

  @override
  String get recentAppendFailure =>
      'Later records could not be loaded. Loaded tracks remain playable.';

  @override
  String get recentContinueLoading => 'Continue loading';

  @override
  String get recentAddToQueue => 'Add to playback queue';

  @override
  String get recentChooseArtistDetail =>
      'This track includes multiple artists. Choose the artist to open.';

  @override
  String libraryShowingTracks(Object shown, Object total) {
    return 'Showing $shown of $total tracks';
  }

  @override
  String get libraryEndPlaylist => 'End of playlist';

  @override
  String libraryFailureReachTitle(Object provider) {
    return 'Couldn’t reach $provider';
  }

  @override
  String get libraryFailureReachDetail =>
      'Your session is still active. Check your connection and try again.';

  @override
  String libraryFailureUnavailableTitle(Object provider) {
    return '$provider is unavailable';
  }

  @override
  String get libraryFailureUnavailableDetail =>
      'The playlist could not be loaded right now. Your session was kept.';

  @override
  String get libraryFailureReadTitle => 'Couldn’t read this playlist';

  @override
  String libraryFailureReadDetail(Object provider) {
    return '$provider returned data this build could not safely present.';
  }

  @override
  String get libraryFailureRejectedTitle => 'Your saved session was rejected';

  @override
  String libraryFailureRejectedDetail(Object provider) {
    return '$provider no longer accepts it, so the stored session was removed.';
  }

  @override
  String libraryFailureRejectedCleanupDetail(Object provider) {
    return '$provider rejected it, but secure storage could not remove it.';
  }

  @override
  String get libraryFailureSignInTitle => 'Sign in to open this playlist';

  @override
  String get libraryFailureAccountChangedDetail =>
      'The account state changed before the request finished.';

  @override
  String get libraryFailureCoreTitle => 'The music core is unavailable';

  @override
  String get libraryFailureCoreDetail =>
      'This playlist could not be loaded safely.';

  @override
  String get libraryFailureRunningTitle =>
      'A playlist request is already running';

  @override
  String get libraryFailureRunningDetail =>
      'Wait for it to finish, then try again.';

  @override
  String get libraryFailureGenericTitle => 'Couldn’t load this playlist';

  @override
  String get libraryFailureGenericDetail => 'Try again or sign in again.';

  @override
  String get navHome => 'Home';

  @override
  String get navDiscover => 'Discover';

  @override
  String get navSearch => 'Search';

  @override
  String get navLiked => 'Liked';

  @override
  String get navRecentPlays => 'Recently played';

  @override
  String get navOnlineMusicSection => 'ONLINE MUSIC';

  @override
  String get navMyMusicSection => 'MY MUSIC';

  @override
  String get navYourPlaylistsSection => 'YOUR PLAYLISTS';

  @override
  String get navSettingsSection => 'SETTINGS';

  @override
  String shellSearchProvider(Object provider) {
    return 'Search $provider';
  }

  @override
  String get shellSignOut => 'Sign out';

  @override
  String get shellSignIn => 'Sign in';

  @override
  String shellSignInToProvider(Object provider) {
    return 'Sign in to $provider';
  }

  @override
  String shellLoadingProviderAccount(Object provider) {
    return 'Loading $provider account…';
  }

  @override
  String shellProviderClient(Object provider) {
    return '$provider client';
  }

  @override
  String get shellBackToMusic => 'Back to music';

  @override
  String get shellBackToFavoriteArtists => 'Back to favorite artists';

  @override
  String get shellBackToPlaylist => 'Back to playlist';

  @override
  String get shellBackToAlbum => 'Back to album';

  @override
  String get shellBackToPreviousPage => 'Back to previous page';

  @override
  String get shellBackToSearchResults => 'Back to search results';

  @override
  String get shellBackToArtist => 'Back to artist';

  @override
  String get shellBackToNewAlbums => 'Back to new albums';

  @override
  String get shellBackToFavoriteAlbums => 'Back to favorite albums';

  @override
  String get libraryYourPlaylists => 'Your playlists';

  @override
  String libraryPlaylistsSavedCount(num count, Object provider) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count playlists saved on $provider',
      one: '1 playlist saved on $provider',
    );
    return '$_temp0';
  }

  @override
  String libraryPlaylistsSavedProvider(Object provider) {
    return 'Saved on $provider';
  }

  @override
  String get libraryRefreshingPlaylists => 'Refreshing playlists';

  @override
  String get libraryRefreshPlaylists => 'Refresh playlists';

  @override
  String libraryPlaylistCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get libraryLoadingPlaylists => 'Loading your playlists…';

  @override
  String get libraryNoPlaylistsTitle => 'No playlists yet';

  @override
  String libraryNoPlaylistsDetail(Object provider) {
    return 'Playlists you create or save in $provider will appear here.';
  }

  @override
  String get librarySignInTitle => 'Sign in to see your music';

  @override
  String librarySignInDetail(Object provider) {
    return 'Your $provider playlists, Liked Songs, albums, and artists will appear here.';
  }

  @override
  String get librarySignOutConfirmTitle => 'Sign out on this device?';

  @override
  String librarySignOutConfirmDetail(Object provider) {
    return 'This will stop playback and remove the saved $provider session from this device.';
  }

  @override
  String get librarySignOutFailure =>
      'Couldn’t sign out. Your local session is unchanged.';

  @override
  String get libraryQualitySaveFailure =>
      'Couldn’t save playback quality. Nothing changed.';

  @override
  String get libraryRefreshFailure =>
      'Couldn’t refresh playlists. The previous results are still shown.';

  @override
  String get libraryFailureReachCollectionDetail =>
      'Your session is still active. Check your connection and try again.';

  @override
  String get libraryFailureServiceCollectionDetail =>
      'Your session was kept unchanged. Try loading your playlists again later.';

  @override
  String get libraryFailureCompleteTitle =>
      'Couldn’t read the complete library';

  @override
  String libraryFailureCompleteDetail(Object provider) {
    return '$provider returned a collection this build could not safely finish. No partial list is shown.';
  }

  @override
  String get libraryFailureSignInPlaylistsTitle =>
      'Sign in to load your playlists';

  @override
  String get libraryFailureRequestChangedDetail =>
      'The account state changed before this library request finished.';

  @override
  String get libraryFailureCoreCollectionDetail =>
      'Your library could not be loaded safely. Try again after restarting.';

  @override
  String get libraryFailureRunningCollectionTitle =>
      'A library request is already running';

  @override
  String get libraryFailureGenericCollectionTitle =>
      'Couldn’t load your playlists';

  @override
  String libraryFailureGenericCollectionDetail(Object provider) {
    return 'Try again or sign in with a fresh $provider session.';
  }

  @override
  String get favoriteAlbumsTitle => 'Favorite albums';

  @override
  String get favoriteArtistsTitle => 'Favorite artists';

  @override
  String favoriteSavedCount(Object count, Object provider) {
    return '$count saved on $provider';
  }

  @override
  String favoriteSavedProvider(Object provider) {
    return 'Saved on $provider';
  }

  @override
  String get favoriteAlbumsRefreshing => 'Refreshing favorite albums';

  @override
  String get favoriteAlbumsRefresh => 'Refresh favorite albums';

  @override
  String get favoriteArtistsRefreshing => 'Refreshing favorite artists';

  @override
  String get favoriteArtistsRefresh => 'Refresh favorite artists';

  @override
  String get favoriteAlbumsLoading => 'Loading favorite albums';

  @override
  String get favoriteArtistsLoading => 'Loading favorite artists';

  @override
  String get favoriteAlbumsEmptyTitle => 'No favorite albums yet';

  @override
  String favoriteAlbumsEmptyDetail(Object provider) {
    return 'Albums you save in $provider will appear here.';
  }

  @override
  String get favoriteArtistsEmptyTitle => 'No favorite artists yet';

  @override
  String favoriteArtistsEmptyDetail(Object provider) {
    return 'Artists you follow in $provider will appear here.';
  }

  @override
  String get favoriteAlbumsSearchEmptyTitle => 'No matching albums';

  @override
  String get favoriteAlbumsSearchEmptyDetail =>
      'Try another keyword. Search covers the favorite albums already loaded.';

  @override
  String get favoriteAlbumsFailureTitle => 'Couldn’t load favorite albums';

  @override
  String get favoriteArtistsFailureTitle => 'Couldn’t load favorite artists';

  @override
  String get favoriteAlbumsSignInTitle => 'Sign in to see favorite albums';

  @override
  String get favoriteAlbumsSignInDetail =>
      'Sign in again to load your favorite albums.';

  @override
  String get favoriteArtistsSignInTitle => 'Sign in to see favorite artists';

  @override
  String get favoriteArtistsSignInDetail =>
      'Sign in again to load your favorite artists.';

  @override
  String favoriteSessionRejectedTitle(Object provider) {
    return '$provider session rejected';
  }

  @override
  String favoriteSessionRejectedCleanupDetail(Object provider) {
    return '$provider rejected this session, and its saved copy could not be removed.';
  }

  @override
  String favoriteSessionRejectedDetail(Object provider) {
    return '$provider no longer accepts this saved session.';
  }

  @override
  String favoriteAlbumSemantics(Object title) {
    return '$title, album';
  }

  @override
  String favoriteArtistSemantics(Object name) {
    return '$name, artist';
  }

  @override
  String favoriteFailureNetwork(Object provider) {
    return 'Couldn’t reach $provider. Check the connection and try again.';
  }

  @override
  String favoriteAlbumsFailureService(Object provider) {
    return '$provider could not load favorite albums right now.';
  }

  @override
  String favoriteArtistsFailureService(Object provider) {
    return '$provider could not load favorite artists right now.';
  }

  @override
  String favoriteAlbumsFailureInvalid(Object provider) {
    return '$provider returned an unreadable favorite-album page.';
  }

  @override
  String favoriteArtistsFailureInvalid(Object provider) {
    return '$provider returned an unreadable favorite-artist page.';
  }

  @override
  String get favoriteFailureCore => 'The music core is unavailable. Try again.';

  @override
  String get favoriteAlbumsFailureRunning =>
      'A favorite-album request is already running.';

  @override
  String get favoriteArtistsFailureRunning =>
      'A favorite-artist request is already running.';

  @override
  String get favoriteFailureSignIn => 'Sign in again to continue.';

  @override
  String get albumType => 'Album';

  @override
  String get albumLoadingTracks => 'Loading album tracks';

  @override
  String get albumEmptyTitle => 'This album has no available tracks';

  @override
  String albumEmptyDetail(Object provider) {
    return '$provider returned an empty album track list.';
  }

  @override
  String get albumFailureTitle => 'Couldn’t load this album';

  @override
  String albumAboutTitle(Object title) {
    return 'About $title';
  }

  @override
  String get albumChooseArtistTitle => 'Choose an artist';

  @override
  String albumTrackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String albumProviderSummary(Object provider) {
    return '$provider album';
  }

  @override
  String get albumAboutAction => 'About this album';

  @override
  String get albumRetryDetails => 'Retry details';

  @override
  String get albumMultipleArtistsDetail =>
      'This album credits more than one artist.';

  @override
  String get albumEnd => 'End of album';

  @override
  String get albumFailureNetwork => 'Check your connection and try again.';

  @override
  String albumFailureService(Object provider) {
    return '$provider album browsing is temporarily unavailable.';
  }

  @override
  String get albumFailureCancelled => 'The album request was cancelled.';

  @override
  String get catalogFailureCore =>
      'The local music core is unavailable. Restart the app and try again.';

  @override
  String albumFailureUnexpected(Object provider) {
    return '$provider returned an unexpected album response.';
  }

  @override
  String get albumDetailsFailureNetwork => 'Album details are offline.';

  @override
  String get albumDetailsFailureService =>
      'Album details are temporarily unavailable.';

  @override
  String get albumDetailsFailureCancelled =>
      'Album detail loading was cancelled.';

  @override
  String get albumDetailsFailureCore => 'Album details could not start.';

  @override
  String get albumDetailsFailureGeneric => 'Album details could not be read.';

  @override
  String get artistType => 'Artist';

  @override
  String get artistTracksSection => 'Tracks';

  @override
  String get artistAlbumsSection => 'Albums';

  @override
  String get artistLoadingTracks => 'Loading artist tracks';

  @override
  String get artistEmptyTracksTitle => 'This artist has no available tracks';

  @override
  String artistEmptyTracksDetail(Object provider) {
    return '$provider returned an empty artist track list.';
  }

  @override
  String get artistFailureTitle => 'Couldn’t load this artist';

  @override
  String get artistLoadingAlbums => 'Loading artist albums';

  @override
  String get artistEmptyAlbumsTitle => 'This artist has no available albums';

  @override
  String artistEmptyAlbumsDetail(Object provider) {
    return '$provider returned an empty artist album list.';
  }

  @override
  String get artistAlbumsFailureTitle => 'Couldn’t load this artist’s albums';

  @override
  String artistCountSummary(Object count, Object type) {
    return '$count $type';
  }

  @override
  String artistTrackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String artistAlbumCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String artistAlbumSemantics(Object title) {
    return '$title, album';
  }

  @override
  String get artistEndAlbums => 'End of artist albums';

  @override
  String get artistEndTracks => 'End of artist tracks';

  @override
  String artistFailureService(Object provider) {
    return '$provider artist browsing is temporarily unavailable.';
  }

  @override
  String get artistFailureCancelled => 'The artist request was cancelled.';

  @override
  String artistFailureUnexpected(Object provider) {
    return '$provider returned an unexpected artist response.';
  }

  @override
  String artistAlbumsFailureService(Object provider) {
    return '$provider artist-album browsing is temporarily unavailable.';
  }

  @override
  String get artistAlbumsFailureCancelled =>
      'The artist-album request was cancelled.';

  @override
  String artistAlbumsFailureUnexpected(Object provider) {
    return '$provider returned an unexpected artist-album response.';
  }

  @override
  String get queueTitle => 'Queue';

  @override
  String queueTrackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '1 track',
    );
    return '$_temp0';
  }

  @override
  String get queueClear => 'Clear';

  @override
  String get queueClose => 'Close queue';

  @override
  String get queueEmpty =>
      'The queue is empty. Choose a track from a playlist.';

  @override
  String get queueRemove => 'Remove from queue';

  @override
  String get queueClearTitle => 'Clear queue?';

  @override
  String get queueClearOneDetail =>
      'This will remove the queued track and stop playback.';

  @override
  String queueClearManyDetail(Object count) {
    return 'This will remove all $count tracks and stop playback.';
  }

  @override
  String get queueFailureInvalidTrack =>
      'A queue entry could not be represented safely.';

  @override
  String get queueFailureInvalidPosition =>
      'That queue position is no longer available.';

  @override
  String get queueFailureCore => 'The music core could not update the queue.';

  @override
  String get queueFailureInvalidResponse =>
      'The music core returned an invalid queue state.';

  @override
  String get playbackQualityMenuStandard => 'Standard · MP3 128 kbps';

  @override
  String get playbackQualityMenuHigh => 'HQ · MP3 320 kbps';

  @override
  String get playbackQualityMenuLossless => 'SQ · FLAC lossless';

  @override
  String playbackQualitySelectedNext(Object quality) {
    return '$quality selected. It applies when the next track starts.';
  }

  @override
  String playbackQualityPlaying(Object quality) {
    return 'Playing $quality quality.';
  }

  @override
  String playbackQualityFallback(Object actual, Object preferred) {
    return '$preferred is unavailable for this track. Playing $actual instead.';
  }

  @override
  String playbackQualityTooltipPreferred(Object quality) {
    return 'Playback quality: $quality';
  }

  @override
  String playbackQualityTooltipCurrent(
    Object actual,
    Object fallback,
    Object preferred,
  ) {
    return 'Playback quality: $preferred. Current source: $actual$fallback';
  }

  @override
  String get playbackQualityFallbackSuffix => ' fallback';

  @override
  String get playbackActualLow => 'Low';

  @override
  String get playbackSignIn => 'Sign in';

  @override
  String get playbackOpenNowPlaying => 'Open now playing';

  @override
  String playbackOpenNowPlayingFor(Object title) {
    return 'Open now playing for $title';
  }

  @override
  String get playbackPrevious => 'Previous';

  @override
  String get playbackNext => 'Next';

  @override
  String get playbackStop => 'Stop';

  @override
  String get playbackPause => 'Pause';

  @override
  String get playbackResume => 'Resume';

  @override
  String get playbackRetry => 'Try again';

  @override
  String get playbackShuffleOn => 'Shuffle on. Turn off shuffle';

  @override
  String get playbackShuffleOff => 'Shuffle off. Turn on shuffle';

  @override
  String get playbackRepeatOff => 'Repeat off. Set repeat all';

  @override
  String get playbackRepeatAll => 'Repeat all. Set repeat one';

  @override
  String get playbackRepeatOne => 'Repeat one. Turn off repeat';

  @override
  String get playbackBrowseCurrentTrack => 'Browse current track';

  @override
  String playbackOpenCreditedArtist(Object title) {
    return 'Open credited artist for $title';
  }

  @override
  String playbackOpenAlbum(Object title) {
    return 'Open album for $title';
  }

  @override
  String playbackBrowseAlbumArtists(Object title) {
    return 'Browse album and credited artists for $title';
  }

  @override
  String playbackChooseCreditedArtist(Object title) {
    return 'Choose a credited artist for $title';
  }

  @override
  String playbackProgressSemantics(Object duration, Object position) {
    return '$position of $duration';
  }

  @override
  String playbackTrackStatusSemantics(Object artist, Object status) {
    return '$artist · $status';
  }

  @override
  String get playbackShowQueue => 'Show queue';

  @override
  String get playbackVolume => 'Volume';

  @override
  String playbackVolumePercent(Object percent) {
    return '$percent percent';
  }

  @override
  String get playbackShowLyrics => 'Show lyrics';

  @override
  String playbackArtworkSemantics(Object title) {
    return 'Artwork for $title';
  }

  @override
  String get playbackReady => 'Ready to play';

  @override
  String get playbackFindingSource => 'Finding a playable source…';

  @override
  String get playbackLoadingAudio => 'Loading audio…';

  @override
  String get playbackPlaying => 'Playing';

  @override
  String get playbackPaused => 'Paused';

  @override
  String get playbackStopped => 'Stopped';

  @override
  String get playbackFinished => 'Finished';

  @override
  String get playbackEngineFailure => 'Playback failed. Try this track again.';

  @override
  String get playbackQueueInvalidTrack => 'A queue track was invalid.';

  @override
  String get playbackAuthRequired =>
      'Sign in to try account-authorized playback.';

  @override
  String playbackCredentialRejected(Object provider) {
    return 'Your $provider session was rejected and removed.';
  }

  @override
  String get playbackCredentialCleanupFailure =>
      'Your session was rejected, but secure storage could not remove it.';

  @override
  String playbackSourceUnavailable(Object provider) {
    return '$provider did not provide a playable source.';
  }

  @override
  String playbackNetworkFailure(Object provider) {
    return 'Couldn’t reach $provider. Try again.';
  }

  @override
  String playbackServiceUnavailable(Object provider) {
    return '$provider playback is unavailable right now.';
  }

  @override
  String playbackInvalidResponse(Object provider) {
    return '$provider returned a source this build could not safely play.';
  }

  @override
  String get playbackCoreUnavailable =>
      'The music core could not resolve this track.';

  @override
  String get playbackRequestRunning =>
      'Another media request is still running.';

  @override
  String get playbackResolutionFailure => 'This track could not be resolved.';

  @override
  String get nowPlayingTitle => 'Now Playing';

  @override
  String get nowPlayingBack => 'Back to previous page';

  @override
  String get nowPlayingOpenMusicVideo => 'Open music video';

  @override
  String get nowPlayingOpenComments => 'Open comments';

  @override
  String get nowPlayingComments => 'Comments';

  @override
  String get nowPlayingEmptyTitle => 'Nothing is playing';

  @override
  String get nowPlayingEmptyDetail =>
      'Choose a track from your library, Search, or Discover.';

  @override
  String get nowPlayingBackToMusic => 'Back to music';

  @override
  String get nowPlayingLyricsUnavailable =>
      'Lyrics are unavailable in this playback session.';

  @override
  String get lyricsTitle => 'Lyrics';

  @override
  String get lyricsClose => 'Close lyrics';

  @override
  String get lyricsIdleTitle => 'Start a track to see its lyrics';

  @override
  String get lyricsIdleDetail =>
      'Synchronized lyrics will follow the current queue track.';

  @override
  String get lyricsUnavailableTitle => 'No synchronized lyrics';

  @override
  String lyricsUnavailableDetail(Object provider) {
    return '$provider did not provide lyrics for this track.';
  }

  @override
  String get lyricsSignInTitle => 'Sign in to load lyrics';

  @override
  String lyricsSignInDetail(Object provider) {
    return 'Your current session cannot request $provider lyrics.';
  }

  @override
  String lyricsSessionRejectedTitle(Object provider) {
    return '$provider session rejected';
  }

  @override
  String get lyricsSessionRejectedDetail =>
      'Sign in again before requesting lyrics.';

  @override
  String get lyricsFollowCurrent => 'Follow current line';

  @override
  String lyricsSegmentProgress(Object percent) {
    return '$percent% complete';
  }

  @override
  String get lyricsLoading => 'Loading synchronized lyrics…';

  @override
  String lyricsAnnouncement(Object detail, Object title) {
    return '$title. $detail';
  }

  @override
  String lyricsFailureNetworkTitle(Object provider) {
    return 'Couldn’t reach $provider';
  }

  @override
  String get lyricsFailureServiceTitle => 'Lyrics are unavailable right now';

  @override
  String get lyricsFailureRunningTitle =>
      'Another lyric request is still running';

  @override
  String get lyricsFailureGenericTitle => 'Couldn’t load synchronized lyrics';

  @override
  String get lyricsFailureNetworkDetail =>
      'Your session is unchanged. Check your connection and try again.';

  @override
  String get lyricsFailureServiceDetail =>
      'Your session is unchanged. Try requesting this track again later.';

  @override
  String get lyricsFailureRunningDetail =>
      'Wait for the current request to finish before trying again.';

  @override
  String get lyricsFailureReplacedDetail =>
      'The lyric request was replaced before it completed.';

  @override
  String lyricsFailureInvalidDetail(Object provider) {
    return '$provider returned lyrics this build could not safely present.';
  }

  @override
  String get commentsTitle => 'Comments';

  @override
  String get commentsClose => 'Close comments';

  @override
  String get commentsLoading => 'Loading comments';

  @override
  String get commentsEmptyTitle => 'No comments yet';

  @override
  String commentsEmptyDetail(Object provider) {
    return '$provider did not return comments for this track.';
  }

  @override
  String get commentsFailureTitle => 'Couldn’t load comments';

  @override
  String get commentsHot => 'Hot comments';

  @override
  String get commentsNewest => 'Newest';

  @override
  String commentsLoadMoreFailure(Object detail) {
    return 'Couldn’t load more comments. $detail';
  }

  @override
  String get commentsLoadMore => 'Load more';

  @override
  String get commentsFailureNetwork => 'Check your connection and try again.';

  @override
  String commentsFailureService(Object provider) {
    return '$provider comments are temporarily unavailable.';
  }

  @override
  String commentsFailureInvalid(Object provider) {
    return '$provider returned comment data this version cannot read.';
  }

  @override
  String get commentsFailureCore =>
      'The native comment service is unavailable in this build.';

  @override
  String get commentsFailureRunning =>
      'Another comment request is still finishing. Try again.';

  @override
  String get commentsFailureCancelled => 'The comment request was cancelled.';

  @override
  String get musicVideoTitle => 'Music video';

  @override
  String get musicVideoClose => 'Close music video';

  @override
  String get musicVideoLoading => 'Loading music video';

  @override
  String get musicVideoEmptyTitle => 'No music video for this track';

  @override
  String musicVideoEmptyDetail(Object provider) {
    return '$provider did not associate an MV with this track.';
  }

  @override
  String get musicVideoUnavailableTitle => 'Music video unavailable';

  @override
  String get musicVideoFailureTitle => 'Couldn’t play music video';

  @override
  String get musicVideoStoppedTitle => 'Music video stopped';

  @override
  String get musicVideoStoppedDetail =>
      'Music playback or the current queue track changed.';

  @override
  String get musicVideoControlsSemantics => 'Music video playback controls';

  @override
  String get musicVideoPause => 'Pause music video';

  @override
  String get musicVideoPlay => 'Play music video';

  @override
  String musicVideoFailureSource(Object provider) {
    return '$provider did not provide a supported playable MV source.';
  }

  @override
  String musicVideoFailureNetwork(Object provider) {
    return 'The MV request could not reach $provider. Check your connection.';
  }

  @override
  String musicVideoFailureService(Object provider) {
    return '$provider could not serve this MV right now.';
  }

  @override
  String musicVideoFailureInvalid(Object provider) {
    return '$provider returned MV data the app could not safely use.';
  }

  @override
  String get musicVideoFailureCancelled => 'The MV request was cancelled.';

  @override
  String get musicVideoFailureRunning =>
      'Another MV request is already running. Try again shortly.';

  @override
  String get musicVideoFailureCore =>
      'The MV player could not start this video.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSearchLabel => 'Search settings';

  @override
  String get settingsBackTooltip => 'Back';

  @override
  String get settingsBackToSettingsTooltip => 'Back to settings';

  @override
  String get settingsSearchResultsTitle => 'Search results';

  @override
  String settingsSearchNoMatch(String query) {
    return 'No settings match ‘$query’.';
  }

  @override
  String settingsSearchMatchSummary(int count, String query) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections match ‘$query’.',
      one: '1 section matches ‘$query’.',
    );
    return '$_temp0';
  }

  @override
  String get settingsSaveFailure => 'Couldn’t save settings on this device.';

  @override
  String get settingsChooseCategory => 'Choose a settings category';

  @override
  String settingsCategorySemantics(
    String label,
    String description,
    String summary,
  ) {
    return '$label. $description. $summary';
  }

  @override
  String get settingsAppearanceLabel => 'Appearance';

  @override
  String get settingsAppearanceCompactLabel => 'Theme mode';

  @override
  String get settingsAppearanceDescription => 'Theme mode and color palette';

  @override
  String get settingsAppearanceBody =>
      'Choose the brightness and color palette used by fura music.';

  @override
  String get settingsAppearanceSummarySystem => 'Following the system theme';

  @override
  String get settingsAppearanceSummaryLight => 'Light theme';

  @override
  String get settingsAppearanceSummaryDark => 'Dark theme';

  @override
  String get settingsAppearanceSearchKeywords =>
      'appearance|theme|system|light|dark|color|palette|Monet|wallpaper|accent|brand';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsColorSourceLabel => 'Color palette';

  @override
  String get settingsColorSourceBody =>
      'Choose where the Material 3 palette comes from.';

  @override
  String get settingsColorSourceSystem => 'System colors (Monet)';

  @override
  String get settingsColorSourceSystemDescription =>
      'Use wallpaper or OS accent colors where supported. The current music service palette is used as a fallback.';

  @override
  String get settingsColorSourceSystemSummary => 'System colors';

  @override
  String get settingsColorSourceBrand => 'Brand impression';

  @override
  String settingsColorSourceBrandDescription(String provider) {
    return 'Use colors inspired by $provider, kept consistent across devices.';
  }

  @override
  String get settingsColorSourceBrandSummary => 'Brand impression colors';

  @override
  String get settingsMusicServiceLabel => 'Music service';

  @override
  String get settingsMusicServiceDescription => 'Catalog and account source';

  @override
  String get settingsMusicServiceBody =>
      'Choose the service used for browsing, search, recommendations, and your account library.';

  @override
  String get settingsMusicServiceSearchKeywords =>
      'provider|music service|source|QQ Music|NetEase Cloud Music';

  @override
  String get providerQqMusic => 'QQ Music';

  @override
  String get providerNeteaseCloudMusic => 'NetEase Cloud Music';

  @override
  String get providerGenericMusicService => 'Music service';

  @override
  String get providerQqMusicSettingsDescription =>
      'First-class service and default';

  @override
  String get providerNeteaseSettingsDescription =>
      'Built-in service with capability-aware features';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageDescription =>
      'Display language and system preference';

  @override
  String get settingsLanguageBody =>
      'Choose the language used by fura music. Provider content such as song and playlist names is not translated.';

  @override
  String get settingsLanguageSearchKeywords =>
      'language|locale|system|English|Simplified Chinese|Chinese';

  @override
  String get settingsLanguageFollowSystem => 'Follow system';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSimplifiedChinese => 'Simplified Chinese';

  @override
  String get settingsLanguageSummarySystem => 'Following the system language';

  @override
  String get settingsLanguageSummaryEnglish => 'English';

  @override
  String get settingsLanguageSummarySimplifiedChinese => 'Simplified Chinese';

  @override
  String get settingsPlaybackLabel => 'Playback';

  @override
  String get settingsPlaybackCompactLabel => 'Audio quality';

  @override
  String get settingsPlaybackSectionLabel => 'Playback quality';

  @override
  String get settingsPlaybackDescription => 'Preferred streaming quality';

  @override
  String get settingsPlaybackBody =>
      'Preferred quality when supported by the current music service. The player always reports the actual quality used.';

  @override
  String get settingsPlaybackSearchKeywords =>
      'playback|quality|audio|standard|high|music source|HQ|SQ';

  @override
  String get playbackQualityStandard => 'Standard';

  @override
  String get playbackQualityHigh => 'HQ';

  @override
  String get playbackQualityLossless => 'SQ';

  @override
  String get playbackQualitySummaryStandard => 'Standard quality';

  @override
  String get playbackQualitySummaryHigh => 'High quality';

  @override
  String get playbackQualitySummaryLossless => 'SQ lossless quality';

  @override
  String get commonLocateCurrentTrack => 'Locate current track';

  @override
  String partialResultsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Some items could not be displayed. $count unsafe items were skipped; the remaining results are shown.',
      one: 'Some items could not be displayed. 1 unsafe item was skipped; the remaining results are shown.',
    );
    return '$_temp0';
  }
}
