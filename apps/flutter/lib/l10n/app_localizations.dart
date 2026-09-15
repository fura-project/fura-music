import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  /// The product display name shown in the window title.
  ///
  /// In en, this message translates to:
  /// **'fura music'**
  String get appTitle;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// No description provided for @commonClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @commonLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get commonLoadMore;

  /// No description provided for @commonTryLoadingMoreAgain.
  ///
  /// In en, this message translates to:
  /// **'Try loading more again'**
  String get commonTryLoadingMoreAgain;

  /// No description provided for @commonAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get commonAddToQueue;

  /// No description provided for @commonMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get commonMoreActions;

  /// No description provided for @commonPlayFromHere.
  ///
  /// In en, this message translates to:
  /// **'Play from here'**
  String get commonPlayFromHere;

  /// No description provided for @commonOpenAlbum.
  ///
  /// In en, this message translates to:
  /// **'Open album'**
  String get commonOpenAlbum;

  /// No description provided for @commonOpenArtist.
  ///
  /// In en, this message translates to:
  /// **'Open artist'**
  String get commonOpenArtist;

  /// No description provided for @commonChooseArtist.
  ///
  /// In en, this message translates to:
  /// **'Choose artist'**
  String get commonChooseArtist;

  /// No description provided for @commonPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// Accessible common track semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, {artists}'**
  String commonTrackSemantics(Object artists, Object title);

  /// Accessible common announcement message.
  ///
  /// In en, this message translates to:
  /// **'{title}. {detail}'**
  String commonAnnouncement(Object detail, Object title);

  /// Localized common selected value message.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String commonSelectedValue(Object label, Object value);

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonScrollToLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Scroll to load more'**
  String get commonScrollToLoadMore;

  /// No description provided for @tableTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get tableTitle;

  /// No description provided for @tableArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get tableArtist;

  /// No description provided for @tableAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get tableAlbum;

  /// No description provided for @tableDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get tableDuration;

  /// No description provided for @trackUnknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown artist'**
  String get trackUnknownArtist;

  /// Tooltip for a menu that opens the album or credited artists for a track.
  ///
  /// In en, this message translates to:
  /// **'Browse context for {trackTitle}'**
  String trackBrowseContextTooltip(String trackTitle);

  /// Tooltip for adding one named track to the playback queue.
  ///
  /// In en, this message translates to:
  /// **'Add {trackTitle} to queue'**
  String trackAddToQueueTooltip(String trackTitle);

  /// Accessible label for track artwork.
  ///
  /// In en, this message translates to:
  /// **'Artwork for {trackTitle}'**
  String trackArtworkSemantics(String trackTitle);

  /// No description provided for @trackChooseArtistTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an artist'**
  String get trackChooseArtistTitle;

  /// No description provided for @trackMultipleArtistsDetail.
  ///
  /// In en, this message translates to:
  /// **'This track credits more than one artist.'**
  String get trackMultipleArtistsDetail;

  /// Accessible label for an actionable metadata value.
  ///
  /// In en, this message translates to:
  /// **'{action}: {value}'**
  String metadataActionSemantics(String action, String value);

  /// No description provided for @librarySectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get librarySectionLabel;

  /// No description provided for @libraryLikedSongs.
  ///
  /// In en, this message translates to:
  /// **'Liked songs'**
  String get libraryLikedSongs;

  /// No description provided for @libraryPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get libraryPlaylists;

  /// No description provided for @libraryAlbums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get libraryAlbums;

  /// No description provided for @libraryArtists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get libraryArtists;

  /// Tooltip and accessibility name for dismissing a non-blocking library refresh message.
  ///
  /// In en, this message translates to:
  /// **'Dismiss refresh message'**
  String get libraryRefreshDismissTooltip;

  /// Tooltip and accessibility name for closing the authentication dialog.
  ///
  /// In en, this message translates to:
  /// **'Close sign in'**
  String get authCloseTooltip;

  /// Authentication dialog heading for the selected music provider.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {provider}'**
  String authSignInTitle(String provider);

  /// No description provided for @authIntroductionMultiple.
  ///
  /// In en, this message translates to:
  /// **'Authorize with QQ or WeChat QR. Passwords are never collected.'**
  String get authIntroductionMultiple;

  /// Authentication explanation for a provider with one QR method.
  ///
  /// In en, this message translates to:
  /// **'Use the official {provider} app to scan this code. Passwords are never collected.'**
  String authIntroductionSingle(String provider);

  /// No description provided for @authScanWithQq.
  ///
  /// In en, this message translates to:
  /// **'Scan with QQ'**
  String get authScanWithQq;

  /// No description provided for @authScanWithWechat.
  ///
  /// In en, this message translates to:
  /// **'Scan with WeChat'**
  String get authScanWithWechat;

  /// Action for opening a provider-specific QR sign-in flow.
  ///
  /// In en, this message translates to:
  /// **'Scan with {provider}'**
  String authScanWithProvider(String provider);

  /// No description provided for @authCreatingCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Creating a secure code…'**
  String get authCreatingCodeTitle;

  /// Progress while creating a provider QR sign-in code.
  ///
  /// In en, this message translates to:
  /// **'Connecting directly to {provider}.'**
  String authConnectingProvider(String provider);

  /// No description provided for @authConnectingQq.
  ///
  /// In en, this message translates to:
  /// **'Connecting directly to QQ authorization.'**
  String get authConnectingQq;

  /// No description provided for @authConnectingWechat.
  ///
  /// In en, this message translates to:
  /// **'Connecting directly to WeChat and QQ Music.'**
  String get authConnectingWechat;

  /// No description provided for @authCheckingSavedSession.
  ///
  /// In en, this message translates to:
  /// **'Checking your saved session…'**
  String get authCheckingSavedSession;

  /// No description provided for @authSavedSessionFound.
  ///
  /// In en, this message translates to:
  /// **'Saved session found'**
  String get authSavedSessionFound;

  /// Progress while verifying a stored provider credential.
  ///
  /// In en, this message translates to:
  /// **'Confirming it directly with {provider} before restoring access.'**
  String authConfirmingSavedSession(String provider);

  /// Explains why a locally valid stored session is not yet authenticated.
  ///
  /// In en, this message translates to:
  /// **'It passed local checks but still needs {provider} verification.'**
  String authSavedSessionNeedsVerification(String provider);

  /// No description provided for @authChooseMethod.
  ///
  /// In en, this message translates to:
  /// **'Choose a sign-in method'**
  String get authChooseMethod;

  /// No description provided for @authSignedOutStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed out, but saved session remains'**
  String get authSignedOutStorageTitle;

  /// Warns that sign-out completed in memory but saved credential deletion failed.
  ///
  /// In en, this message translates to:
  /// **'The active {provider} session was cleared, but secure storage could not remove its saved copy. It may appear again after restart.'**
  String authSignedOutStorageDetail(String provider);

  /// No description provided for @authSavedSessionExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved session expired'**
  String get authSavedSessionExpiredTitle;

  /// Authentication saved session expired detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider}’s advertised lifetime has ended. Sign in again to continue.'**
  String authSavedSessionExpiredDetail(Object provider);

  /// No description provided for @authSavedSessionOtherVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved session is from another version'**
  String get authSavedSessionOtherVersionTitle;

  /// No description provided for @authSavedSessionOtherVersionDetail.
  ///
  /// In en, this message translates to:
  /// **'This build left it unchanged instead of guessing. You can replace it by signing in again.'**
  String get authSavedSessionOtherVersionDetail;

  /// No description provided for @authStorageUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure storage is unavailable'**
  String get authStorageUnavailableTitle;

  /// No description provided for @authStorageUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'You can sign in for this run, but the session may not survive restart.'**
  String get authStorageUnavailableDetail;

  /// No description provided for @authCoreUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'The music core is unavailable'**
  String get authCoreUnavailableTitle;

  /// No description provided for @authRestoreCoreUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'The stored session could not be checked safely. Try again after restart.'**
  String get authRestoreCoreUnavailableDetail;

  /// No description provided for @authSavedSessionUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved session could not be read'**
  String get authSavedSessionUnreadableTitle;

  /// No description provided for @authSavedSessionUnreadableDetail.
  ///
  /// In en, this message translates to:
  /// **'It was left unchanged instead of being treated as a valid login. You can replace it by signing in again.'**
  String get authSavedSessionUnreadableDetail;

  /// No description provided for @authRemovingSavedSession.
  ///
  /// In en, this message translates to:
  /// **'Removing saved session…'**
  String get authRemovingSavedSession;

  /// No description provided for @authRemoveSavedSessionAgain.
  ///
  /// In en, this message translates to:
  /// **'Try removing it again'**
  String get authRemoveSavedSessionAgain;

  /// No description provided for @authTryVerificationAgain.
  ///
  /// In en, this message translates to:
  /// **'Try verification again'**
  String get authTryVerificationAgain;

  /// No description provided for @authSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get authSignInAgain;

  /// No description provided for @authSavedSessionRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved session was rejected'**
  String get authSavedSessionRejectedTitle;

  /// User-facing auth saved session rejected detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} no longer accepts it, so the stored session was removed.'**
  String authSavedSessionRejectedDetail(Object provider);

  /// User-facing auth saved session rejected cleanup detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} no longer accepts it, but secure storage could not remove it. It may appear again after restart.'**
  String authSavedSessionRejectedCleanupDetail(Object provider);

  /// Authentication could not reach provider title message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach {provider}'**
  String authCouldNotReachProviderTitle(Object provider);

  /// No description provided for @authSavedSessionNetworkDetail.
  ///
  /// In en, this message translates to:
  /// **'The saved session is still available. Check your connection and try again.'**
  String get authSavedSessionNetworkDetail;

  /// Authentication provider unavailable title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} is unavailable'**
  String authProviderUnavailableTitle(Object provider);

  /// No description provided for @authSavedSessionServiceDetail.
  ///
  /// In en, this message translates to:
  /// **'The saved session was kept unchanged. Try verification again later.'**
  String get authSavedSessionServiceDetail;

  /// Authentication provider changed response title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} changed its response'**
  String authProviderChangedResponseTitle(Object provider);

  /// No description provided for @authSavedSessionInvalidResponseDetail.
  ///
  /// In en, this message translates to:
  /// **'The saved session was kept instead of being treated as signed out.'**
  String get authSavedSessionInvalidResponseDetail;

  /// No description provided for @authSavedSessionVerifyCoreDetail.
  ///
  /// In en, this message translates to:
  /// **'The saved session could not be verified safely. Try again after restart.'**
  String get authSavedSessionVerifyCoreDetail;

  /// No description provided for @authSavedSessionNotCurrentTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved session is no longer current'**
  String get authSavedSessionNotCurrentTitle;

  /// No description provided for @authSignInAgainDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to continue.'**
  String get authSignInAgainDetail;

  /// No description provided for @authConfirmPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm on your phone'**
  String get authConfirmPhoneTitle;

  /// No description provided for @authReconnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get authReconnectingTitle;

  /// Authentication state shown after a single-method provider QR code has been scanned.
  ///
  /// In en, this message translates to:
  /// **'The code was scanned. Approve the sign-in in the official app.'**
  String get authCodeScannedProviderDetail;

  /// No description provided for @authCodeScannedQqDetail.
  ///
  /// In en, this message translates to:
  /// **'The code was scanned. Approve the sign-in in QQ.'**
  String get authCodeScannedQqDetail;

  /// No description provided for @authCodeScannedWechatDetail.
  ///
  /// In en, this message translates to:
  /// **'The code was scanned. Approve the sign-in in WeChat.'**
  String get authCodeScannedWechatDetail;

  /// No description provided for @authReconnectingDetail.
  ///
  /// In en, this message translates to:
  /// **'Your code is still active. We’ll retry the connection.'**
  String get authReconnectingDetail;

  /// Authentication open provider scan detail message.
  ///
  /// In en, this message translates to:
  /// **'Open {provider}, choose Scan, then point your camera here.'**
  String authOpenProviderScanDetail(Object provider);

  /// No description provided for @authOpenQqScanDetail.
  ///
  /// In en, this message translates to:
  /// **'Open QQ, choose Scan, then point your camera here.'**
  String get authOpenQqScanDetail;

  /// No description provided for @authOpenWechatScanDetail.
  ///
  /// In en, this message translates to:
  /// **'Open WeChat, choose Scan, then point your camera here.'**
  String get authOpenWechatScanDetail;

  /// Accessible auth provider qr semantics message.
  ///
  /// In en, this message translates to:
  /// **'{provider} sign-in QR code'**
  String authProviderQrSemantics(Object provider);

  /// Screen-reader label for the QQ sign-in QR image.
  ///
  /// In en, this message translates to:
  /// **'QQ sign-in QR code'**
  String get authQqQrSemantics;

  /// Screen-reader label for the WeChat sign-in QR image.
  ///
  /// In en, this message translates to:
  /// **'WeChat sign-in QR code'**
  String get authWechatQrSemantics;

  /// No description provided for @authQqLogin.
  ///
  /// In en, this message translates to:
  /// **'QQ login'**
  String get authQqLogin;

  /// No description provided for @authWechatLogin.
  ///
  /// In en, this message translates to:
  /// **'WeChat login'**
  String get authWechatLogin;

  /// No description provided for @authQuickLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick login'**
  String get authQuickLoginTitle;

  /// No description provided for @authQuickLoginDetail.
  ///
  /// In en, this message translates to:
  /// **'Use an account already signed in to desktop QQ.'**
  String get authQuickLoginDetail;

  /// No description provided for @authNewCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get authNewCode;

  /// No description provided for @authOpenQrExternally.
  ///
  /// In en, this message translates to:
  /// **'Open in system browser or NetEase app'**
  String get authOpenQrExternally;

  /// No description provided for @authOpeningQrExternally.
  ///
  /// In en, this message translates to:
  /// **'Opening confirmation page…'**
  String get authOpeningQrExternally;

  /// No description provided for @authOpenQrExternallyFailed.
  ///
  /// In en, this message translates to:
  /// **'The system could not open this confirmation page. Scan the QR code on another device.'**
  String get authOpenQrExternallyFailed;

  /// No description provided for @authSignedInTitle.
  ///
  /// In en, this message translates to:
  /// **'You’re signed in'**
  String get authSignedInTitle;

  /// Authentication saving session detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} accepted this session. Saving it to platform secure storage…'**
  String authSavingSessionDetail(Object provider);

  /// No description provided for @authSavedSessionReadyDetail.
  ///
  /// In en, this message translates to:
  /// **'This session is stored securely and ready for this run.'**
  String get authSavedSessionReadyDetail;

  /// No description provided for @authSessionOnlyDetail.
  ///
  /// In en, this message translates to:
  /// **'You’re signed in for this session, but secure storage was unavailable. You’ll need to sign in again after restart.'**
  String get authSessionOnlyDetail;

  /// Authentication storage not confirmed detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} accepted this session. Secure storage has not been confirmed.'**
  String authStorageNotConfirmedDetail(Object provider);

  /// No description provided for @authCodeExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'This code expired'**
  String get authCodeExpiredTitle;

  /// No description provided for @authCodeExpiredDetail.
  ///
  /// In en, this message translates to:
  /// **'Create a fresh code to continue signing in.'**
  String get authCodeExpiredDetail;

  /// No description provided for @authNotApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in wasn’t approved'**
  String get authNotApprovedTitle;

  /// No description provided for @authNotApprovedDetail.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed on your account. You can try again.'**
  String get authNotApprovedDetail;

  /// QR sign-in title when the provider requires an unsupported additional verification.
  ///
  /// In en, this message translates to:
  /// **'{provider} requires an additional security check'**
  String authSecurityVerificationTitle(Object provider);

  /// No description provided for @authSecurityVerificationDetail.
  ///
  /// In en, this message translates to:
  /// **'This QR sign-in triggered the provider’s security verification. Fura will not bypass it; create a fresh code and try again later.'**
  String get authSecurityVerificationDetail;

  /// Sign-in title when the provider requires an interactive second verification.
  ///
  /// In en, this message translates to:
  /// **'{provider} requires a second verification step'**
  String authSecondaryVerificationTitle(Object provider);

  /// No description provided for @authSecondaryVerificationDetail.
  ///
  /// In en, this message translates to:
  /// **'Continue on the official NetEase website to complete the provider-controlled verification.'**
  String get authSecondaryVerificationDetail;

  /// No description provided for @authServiceRejectedDetail.
  ///
  /// In en, this message translates to:
  /// **'The service did not accept this request. Try again in a moment.'**
  String get authServiceRejectedDetail;

  /// No description provided for @authRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was rejected'**
  String get authRejectedTitle;

  /// No description provided for @authRejectedDetail.
  ///
  /// In en, this message translates to:
  /// **'The authorization was not accepted. Choose a method and try again.'**
  String get authRejectedDetail;

  /// No description provided for @authNetworkFailuresTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection keeps dropping'**
  String get authNetworkFailuresTitle;

  /// No description provided for @authNetworkFailuresDetail.
  ///
  /// In en, this message translates to:
  /// **'Check your network, then create a fresh code.'**
  String get authNetworkFailuresDetail;

  /// No description provided for @authInvalidResponseDetail.
  ///
  /// In en, this message translates to:
  /// **'This client stopped safely instead of guessing. Try a new code later.'**
  String get authInvalidResponseDetail;

  /// No description provided for @authCouldNotContinueTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t continue sign-in'**
  String get authCouldNotContinueTitle;

  /// No description provided for @authCouldNotContinueDetail.
  ///
  /// In en, this message translates to:
  /// **'Try this session again or create a new code.'**
  String get authCouldNotContinueDetail;

  /// Accessible auth announcement semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}. {detail}'**
  String authAnnouncementSemantics(Object detail, Object title);

  /// No description provided for @authCheckingDesktopQq.
  ///
  /// In en, this message translates to:
  /// **'Checking desktop QQ…'**
  String get authCheckingDesktopQq;

  /// No description provided for @authOpenDesktopQqDetail.
  ///
  /// In en, this message translates to:
  /// **'Open and sign in to desktop QQ to use quick login.'**
  String get authOpenDesktopQqDetail;

  /// No description provided for @authNoDesktopAccount.
  ///
  /// In en, this message translates to:
  /// **'No signed-in desktop QQ account was found.'**
  String get authNoDesktopAccount;

  /// No description provided for @authDesktopClientUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ is not available. Open QQ and try again.'**
  String get authDesktopClientUnavailable;

  /// No description provided for @authDesktopNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ authorization could not reach QQ Music.'**
  String get authDesktopNetworkFailure;

  /// No description provided for @authDesktopServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'QQ authorization is temporarily unavailable.'**
  String get authDesktopServiceUnavailable;

  /// No description provided for @authDesktopRejected.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ did not approve this authorization.'**
  String get authDesktopRejected;

  /// No description provided for @authDesktopInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ returned a response this build could not verify.'**
  String get authDesktopInvalidResponse;

  /// No description provided for @authDesktopAttemptInactive.
  ///
  /// In en, this message translates to:
  /// **'This quick-login attempt is no longer active. Retry discovery.'**
  String get authDesktopAttemptInactive;

  /// No description provided for @authDesktopAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ authorization is already in progress.'**
  String get authDesktopAlreadyRunning;

  /// No description provided for @authDesktopCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The music core could not start desktop QQ authorization.'**
  String get authDesktopCoreUnavailable;

  /// No description provided for @authDesktopUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Desktop QQ quick login is unavailable.'**
  String get authDesktopUnavailable;

  /// No description provided for @authUsePhoneCode.
  ///
  /// In en, this message translates to:
  /// **'Use phone code'**
  String get authUsePhoneCode;

  /// No description provided for @authUseQrCode.
  ///
  /// In en, this message translates to:
  /// **'Use QR code'**
  String get authUseQrCode;

  /// No description provided for @authUseOfficialWebsite.
  ///
  /// In en, this message translates to:
  /// **'Continue on NetEase website'**
  String get authUseOfficialWebsite;

  /// No description provided for @authOfficialWebTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete sign-in with NetEase'**
  String get authOfficialWebTitle;

  /// No description provided for @authOfficialWebDetail.
  ///
  /// In en, this message translates to:
  /// **'Use the official login window. Fura will import only the resulting session and verify it before saving.'**
  String get authOfficialWebDetail;

  /// No description provided for @authOfficialWebErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Official NetEase sign-in did not finish'**
  String get authOfficialWebErrorTitle;

  /// No description provided for @authOfficialWebUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The official login window is not available on this device.'**
  String get authOfficialWebUnavailable;

  /// No description provided for @authOfficialWebRejected.
  ///
  /// In en, this message translates to:
  /// **'NetEase did not accept the completed website session.'**
  String get authOfficialWebRejected;

  /// No description provided for @authOfficialWebNetwork.
  ///
  /// In en, this message translates to:
  /// **'The completed website session could not be verified because the connection failed.'**
  String get authOfficialWebNetwork;

  /// No description provided for @authOfficialWebServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NetEase accepted the website interaction but its account verification service is unavailable.'**
  String get authOfficialWebServiceUnavailable;

  /// No description provided for @authOfficialWebInvalidCredential.
  ///
  /// In en, this message translates to:
  /// **'The official window did not return a session Fura can validate.'**
  String get authOfficialWebInvalidCredential;

  /// No description provided for @authOfficialWebAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'An official NetEase login window is already open.'**
  String get authOfficialWebAlreadyRunning;

  /// No description provided for @authOfficialWebFailed.
  ///
  /// In en, this message translates to:
  /// **'The official login window could not complete safely. No session was saved.'**
  String get authOfficialWebFailed;

  /// No description provided for @authOfficialWebLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the official NetEase sign-in page'**
  String get authOfficialWebLoading;

  /// No description provided for @authOfficialWebWaiting.
  ///
  /// In en, this message translates to:
  /// **'Complete sign-in on the official page. Fura will verify the resulting session before saving it.'**
  String get authOfficialWebWaiting;

  /// No description provided for @authOfficialWebSystemBrowserWaiting.
  ///
  /// In en, this message translates to:
  /// **'A private system-browser window is open. Complete sign-in there; Fura will close it after securely reading and verifying the resulting session.'**
  String get authOfficialWebSystemBrowserWaiting;

  /// No description provided for @authOfficialWebVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying your NetEase account'**
  String get authOfficialWebVerifying;

  /// No description provided for @authOfficialWebTimedOut.
  ///
  /// In en, this message translates to:
  /// **'The official login session timed out. Start a new attempt.'**
  String get authOfficialWebTimedOut;

  /// No description provided for @authOfficialWebCleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Fura could not clear the temporary website session. No credential was saved.'**
  String get authOfficialWebCleanupFailed;

  /// No description provided for @authSignedOutWebCleanupTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed out, but website cleanup needs attention'**
  String get authSignedOutWebCleanupTitle;

  /// Explains that provider and vault sign-out succeeded while temporary official-login website data cleanup could not be confirmed.
  ///
  /// In en, this message translates to:
  /// **'The {providerName} account and saved session were removed, but Fura could not confirm that the temporary website data was cleared.'**
  String authSignedOutWebCleanupDetail(String providerName);

  /// No description provided for @authPhoneCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with a phone code'**
  String get authPhoneCodeTitle;

  /// No description provided for @authPhoneCodeDetail.
  ///
  /// In en, this message translates to:
  /// **'Request a one-time code for the phone number linked to NetEase Cloud Music.'**
  String get authPhoneCodeDetail;

  /// No description provided for @authCountryCode.
  ///
  /// In en, this message translates to:
  /// **'Country code'**
  String get authCountryCode;

  /// No description provided for @authPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get authPhoneNumber;

  /// No description provided for @authSmsCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get authSmsCode;

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get authResendCode;

  /// Countdown before another SMS code can be requested.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String authResendCodeIn(int seconds);

  /// No description provided for @authCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent. Check your messages.'**
  String get authCodeSent;

  /// No description provided for @authSmsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSmsSignIn;

  /// No description provided for @authSendingCode.
  ///
  /// In en, this message translates to:
  /// **'Sending code…'**
  String get authSendingCode;

  /// No description provided for @authCheckingSmsCode.
  ///
  /// In en, this message translates to:
  /// **'Checking code…'**
  String get authCheckingSmsCode;

  /// No description provided for @authSmsRiskWarning.
  ///
  /// In en, this message translates to:
  /// **'NetEase may still require an additional security check. Fura will stop and report it instead of bypassing the check.'**
  String get authSmsRiskWarning;

  /// No description provided for @authSmsInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid country code, phone number, and verification code using digits only.'**
  String get authSmsInvalidInput;

  /// No description provided for @authSmsCodeRejected.
  ///
  /// In en, this message translates to:
  /// **'That verification code was not accepted. Check it and try again.'**
  String get authSmsCodeRejected;

  /// No description provided for @authSmsRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests were made. Wait before requesting another code.'**
  String get authSmsRateLimited;

  /// No description provided for @authSmsSecurityVerification.
  ///
  /// In en, this message translates to:
  /// **'NetEase requires an additional security check for this phone login. Fura cannot bypass it.'**
  String get authSmsSecurityVerification;

  /// No description provided for @authSmsSecondaryVerification.
  ///
  /// In en, this message translates to:
  /// **'NetEase requires an interactive second verification. Continue on the official website to finish sign-in.'**
  String get authSmsSecondaryVerification;

  /// No description provided for @authSmsNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach NetEase. Check your connection and try again.'**
  String get authSmsNetworkFailure;

  /// No description provided for @authSmsServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NetEase phone login is temporarily unavailable. Try again later or use QR sign-in.'**
  String get authSmsServiceUnavailable;

  /// No description provided for @authSmsInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'NetEase returned a response this version could not verify. No login was installed.'**
  String get authSmsInvalidResponse;

  /// No description provided for @authSmsAlreadyRunning.
  ///
  /// In en, this message translates to:
  /// **'A phone login request is already in progress.'**
  String get authSmsAlreadyRunning;

  /// No description provided for @authSmsAttemptReplaced.
  ///
  /// In en, this message translates to:
  /// **'This phone login is no longer current. Request a new code.'**
  String get authSmsAttemptReplaced;

  /// No description provided for @authSmsCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The music core could not continue phone login.'**
  String get authSmsCoreUnavailable;

  /// No description provided for @searchSongHint.
  ///
  /// In en, this message translates to:
  /// **'Song, artist, or album name'**
  String get searchSongHint;

  /// No description provided for @searchArtistHint.
  ///
  /// In en, this message translates to:
  /// **'Artist name'**
  String get searchArtistHint;

  /// No description provided for @searchAlbumHint.
  ///
  /// In en, this message translates to:
  /// **'Album name'**
  String get searchAlbumHint;

  /// No description provided for @searchPlaylistHint.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get searchPlaylistHint;

  /// No description provided for @searchTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Search type'**
  String get searchTypeLabel;

  /// No description provided for @searchTracksType.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get searchTracksType;

  /// No description provided for @searchArtistsType.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get searchArtistsType;

  /// No description provided for @searchAlbumsType.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get searchAlbumsType;

  /// No description provided for @searchPlaylistsType.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get searchPlaylistsType;

  /// Tooltip and accessibility name for leaving Search and returning to the music shell.
  ///
  /// In en, this message translates to:
  /// **'Back to your music'**
  String get searchBackTooltip;

  /// Search provider title message.
  ///
  /// In en, this message translates to:
  /// **'Search {provider}'**
  String searchProviderTitle(Object provider);

  /// Search find tracks title message.
  ///
  /// In en, this message translates to:
  /// **'Find tracks on {provider}'**
  String searchFindTracksTitle(Object provider);

  /// No description provided for @searchTrackPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search by song, artist, or album name.'**
  String get searchTrackPrompt;

  /// Search loading tracks message.
  ///
  /// In en, this message translates to:
  /// **'Searching {provider} tracks'**
  String searchLoadingTracks(Object provider);

  /// No description provided for @searchNoTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'No tracks found'**
  String get searchNoTracksTitle;

  /// No description provided for @searchNoResultsDetail.
  ///
  /// In en, this message translates to:
  /// **'Try a different spelling or a broader search.'**
  String get searchNoResultsDetail;

  /// No description provided for @searchEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit search'**
  String get searchEditAction;

  /// Search find artists title message.
  ///
  /// In en, this message translates to:
  /// **'Find artists on {provider}'**
  String searchFindArtistsTitle(Object provider);

  /// No description provided for @searchArtistPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search by an artist or group name.'**
  String get searchArtistPrompt;

  /// Search loading artists message.
  ///
  /// In en, this message translates to:
  /// **'Searching {provider} artists'**
  String searchLoadingArtists(Object provider);

  /// No description provided for @searchNoArtistsTitle.
  ///
  /// In en, this message translates to:
  /// **'No artists found'**
  String get searchNoArtistsTitle;

  /// Search find albums title message.
  ///
  /// In en, this message translates to:
  /// **'Find albums on {provider}'**
  String searchFindAlbumsTitle(Object provider);

  /// No description provided for @searchAlbumPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search by an album name.'**
  String get searchAlbumPrompt;

  /// Search loading albums message.
  ///
  /// In en, this message translates to:
  /// **'Searching {provider} albums'**
  String searchLoadingAlbums(Object provider);

  /// No description provided for @searchNoAlbumsTitle.
  ///
  /// In en, this message translates to:
  /// **'No albums found'**
  String get searchNoAlbumsTitle;

  /// Search find playlists title message.
  ///
  /// In en, this message translates to:
  /// **'Find playlists on {provider}'**
  String searchFindPlaylistsTitle(Object provider);

  /// No description provided for @searchPlaylistPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search by a public playlist name.'**
  String get searchPlaylistPrompt;

  /// Search loading playlists message.
  ///
  /// In en, this message translates to:
  /// **'Searching {provider} playlists'**
  String searchLoadingPlaylists(Object provider);

  /// No description provided for @searchNoPlaylistsTitle.
  ///
  /// In en, this message translates to:
  /// **'No playlists found'**
  String get searchNoPlaylistsTitle;

  /// User-facing search failure title message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t search {provider}'**
  String searchFailureTitle(Object provider);

  /// No description provided for @queueAddedMessage.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get queueAddedMessage;

  /// No description provided for @queueUpdateFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update the queue'**
  String get queueUpdateFailureMessage;

  /// Track search result count and query.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result for “{query}”} other{{count} results for “{query}”}}'**
  String searchResultCount(int count, String query);

  /// Pluralized search artist result count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Artist for ‘{query}’} other{{count} Artists for ‘{query}’}}'**
  String searchArtistResultCount(num count, Object query);

  /// Pluralized search album result count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Album for ‘{query}’} other{{count} Albums for ‘{query}’}}'**
  String searchAlbumResultCount(num count, Object query);

  /// Pluralized search playlist result count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Playlist for ‘{query}’} other{{count} Playlists for ‘{query}’}}'**
  String searchPlaylistResultCount(num count, Object query);

  /// No description provided for @searchArtistResultType.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get searchArtistResultType;

  /// No description provided for @searchAlbumResultType.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get searchAlbumResultType;

  /// No description provided for @searchPlaylistResultType.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get searchPlaylistResultType;

  /// Pluralized track count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String trackCount(num count);

  /// No description provided for @searchBrowseCreditedArtists.
  ///
  /// In en, this message translates to:
  /// **'Browse credited artists'**
  String get searchBrowseCreditedArtists;

  /// Search open named album message.
  ///
  /// In en, this message translates to:
  /// **'Open {albumTitle}'**
  String searchOpenNamedAlbum(Object albumTitle);

  /// No description provided for @searchEndOfResults.
  ///
  /// In en, this message translates to:
  /// **'End of results'**
  String get searchEndOfResults;

  /// No description provided for @searchNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get searchNetworkFailure;

  /// No description provided for @searchServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This music service’s search is temporarily unavailable.'**
  String get searchServiceUnavailable;

  /// No description provided for @searchCancelled.
  ///
  /// In en, this message translates to:
  /// **'The search was cancelled.'**
  String get searchCancelled;

  /// No description provided for @searchCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The local music core is unavailable. Restart the app and try again.'**
  String get searchCoreUnavailable;

  /// No description provided for @searchUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected search response.'**
  String get searchUnexpectedResponse;

  /// No description provided for @searchArtistServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Artist search is temporarily unavailable.'**
  String get searchArtistServiceUnavailable;

  /// No description provided for @searchArtistCancelled.
  ///
  /// In en, this message translates to:
  /// **'The artist search was cancelled.'**
  String get searchArtistCancelled;

  /// No description provided for @searchArtistUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected artist search response.'**
  String get searchArtistUnexpectedResponse;

  /// No description provided for @searchAlbumServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Album search is temporarily unavailable.'**
  String get searchAlbumServiceUnavailable;

  /// No description provided for @searchAlbumCancelled.
  ///
  /// In en, this message translates to:
  /// **'The album search was cancelled.'**
  String get searchAlbumCancelled;

  /// No description provided for @searchAlbumUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected album search response.'**
  String get searchAlbumUnexpectedResponse;

  /// No description provided for @searchPlaylistServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Playlist search is temporarily unavailable.'**
  String get searchPlaylistServiceUnavailable;

  /// No description provided for @searchPlaylistCancelled.
  ///
  /// In en, this message translates to:
  /// **'The playlist search was cancelled.'**
  String get searchPlaylistCancelled;

  /// No description provided for @searchPlaylistUnexpectedResponse.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected playlist search response.'**
  String get searchPlaylistUnexpectedResponse;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverTitle;

  /// Tooltip and accessibility name for leaving Discover and returning to the music shell.
  ///
  /// In en, this message translates to:
  /// **'Back to your music'**
  String get discoverBackTooltip;

  /// Localized discover subtitle with radar message.
  ///
  /// In en, this message translates to:
  /// **'Playlists, charts, Radar, and new releases from {provider}'**
  String discoverSubtitleWithRadar(Object provider);

  /// Localized discover subtitle without radar message.
  ///
  /// In en, this message translates to:
  /// **'Playlists, charts, and new releases from {provider}'**
  String discoverSubtitleWithoutRadar(Object provider);

  /// No description provided for @discoverPlaylistsTab.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get discoverPlaylistsTab;

  /// No description provided for @discoverRankingsTab.
  ///
  /// In en, this message translates to:
  /// **'Rankings'**
  String get discoverRankingsTab;

  /// No description provided for @discoverRadarTab.
  ///
  /// In en, this message translates to:
  /// **'Radar'**
  String get discoverRadarTab;

  /// No description provided for @discoverNewAlbumsTab.
  ///
  /// In en, this message translates to:
  /// **'New albums'**
  String get discoverNewAlbumsTab;

  /// No description provided for @discoverNewSongsTab.
  ///
  /// In en, this message translates to:
  /// **'New songs'**
  String get discoverNewSongsTab;

  /// No description provided for @discoverLoadingRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Loading recommended playlists'**
  String get discoverLoadingRecommendations;

  /// No description provided for @discoverNoRecommendationsTitle.
  ///
  /// In en, this message translates to:
  /// **'No recommendations right now'**
  String get discoverNoRecommendationsTitle;

  /// Localized discover no recommendations detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an empty recommended-playlist page.'**
  String discoverNoRecommendationsDetail(Object provider);

  /// No description provided for @discoverRecommendationsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load recommendations'**
  String get discoverRecommendationsFailureTitle;

  /// Localized discover loading rankings message.
  ///
  /// In en, this message translates to:
  /// **'Loading {provider} Rankings'**
  String discoverLoadingRankings(Object provider);

  /// No description provided for @discoverNoRankingsTitle.
  ///
  /// In en, this message translates to:
  /// **'No rankings right now'**
  String get discoverNoRankingsTitle;

  /// Localized discover no rankings detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned no current rankings.'**
  String discoverNoRankingsDetail(Object provider);

  /// No description provided for @discoverRankingsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load rankings'**
  String get discoverRankingsFailureTitle;

  /// No description provided for @discoverLoadingRadar.
  ///
  /// In en, this message translates to:
  /// **'Loading QQ Music Radar'**
  String get discoverLoadingRadar;

  /// No description provided for @discoverNoRadarTitle.
  ///
  /// In en, this message translates to:
  /// **'No Radar tracks right now'**
  String get discoverNoRadarTitle;

  /// No description provided for @discoverNoRadarDetail.
  ///
  /// In en, this message translates to:
  /// **'QQ Music returned an empty Radar track page.'**
  String get discoverNoRadarDetail;

  /// No description provided for @discoverRadarFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load Radar'**
  String get discoverRadarFailureTitle;

  /// No description provided for @discoverReloadRadar.
  ///
  /// In en, this message translates to:
  /// **'Reload Radar'**
  String get discoverReloadRadar;

  /// No description provided for @discoverRefreshRadar.
  ///
  /// In en, this message translates to:
  /// **'Refresh Radar'**
  String get discoverRefreshRadar;

  /// No description provided for @discoverLoadingNewAlbums.
  ///
  /// In en, this message translates to:
  /// **'Loading new albums'**
  String get discoverLoadingNewAlbums;

  /// No description provided for @discoverNoNewAlbumsTitle.
  ///
  /// In en, this message translates to:
  /// **'No new albums right now'**
  String get discoverNoNewAlbumsTitle;

  /// Localized discover no new albums detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned no albums here.'**
  String discoverNoNewAlbumsDetail(Object provider);

  /// No description provided for @discoverNewAlbumsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load new albums'**
  String get discoverNewAlbumsFailureTitle;

  /// No description provided for @discoverLoadingNewSongs.
  ///
  /// In en, this message translates to:
  /// **'Loading New Songs'**
  String get discoverLoadingNewSongs;

  /// No description provided for @discoverNoNewSongsTitle.
  ///
  /// In en, this message translates to:
  /// **'No new songs right now'**
  String get discoverNoNewSongsTitle;

  /// Localized discover no new songs detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned no tracks here.'**
  String discoverNoNewSongsDetail(Object provider);

  /// No description provided for @discoverNewSongsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load new songs'**
  String get discoverNewSongsFailureTitle;

  /// No description provided for @discoverEndNewAlbums.
  ///
  /// In en, this message translates to:
  /// **'End of new albums'**
  String get discoverEndNewAlbums;

  /// No description provided for @discoverEndRadar.
  ///
  /// In en, this message translates to:
  /// **'End of Radar recommendations'**
  String get discoverEndRadar;

  /// No description provided for @discoverEndRecommendations.
  ///
  /// In en, this message translates to:
  /// **'End of recommendations'**
  String get discoverEndRecommendations;

  /// No description provided for @discoverMusicServicePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Music service playlist'**
  String get discoverMusicServicePlaylist;

  /// No description provided for @discoverCurrentRanking.
  ///
  /// In en, this message translates to:
  /// **'Current ranking'**
  String get discoverCurrentRanking;

  /// No description provided for @discoverAlbumType.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get discoverAlbumType;

  /// No description provided for @discoverRecommendationServiceFailure.
  ///
  /// In en, this message translates to:
  /// **'Recommendations are temporarily unavailable.'**
  String get discoverRecommendationServiceFailure;

  /// No description provided for @discoverRecommendationCancelled.
  ///
  /// In en, this message translates to:
  /// **'The recommendation request was cancelled.'**
  String get discoverRecommendationCancelled;

  /// No description provided for @discoverRecommendationUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected recommendation response.'**
  String get discoverRecommendationUnexpected;

  /// No description provided for @discoverRadarAuthenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to load QQ Music Radar Tracks.'**
  String get discoverRadarAuthenticationRequired;

  /// No description provided for @discoverRadarCredentialRejected.
  ///
  /// In en, this message translates to:
  /// **'Your QQ Music session expired. Sign in again to continue.'**
  String get discoverRadarCredentialRejected;

  /// No description provided for @discoverRadarCredentialCleanupFailure.
  ///
  /// In en, this message translates to:
  /// **'Your QQ Music session expired, but its saved copy could not be removed. Sign in again after checking secure storage.'**
  String get discoverRadarCredentialCleanupFailure;

  /// No description provided for @discoverRadarServiceFailure.
  ///
  /// In en, this message translates to:
  /// **'QQ Music Radar is temporarily unavailable.'**
  String get discoverRadarServiceFailure;

  /// No description provided for @discoverRadarAccountChanged.
  ///
  /// In en, this message translates to:
  /// **'The signed-in account changed while Radar was loading.'**
  String get discoverRadarAccountChanged;

  /// No description provided for @discoverRadarCancelled.
  ///
  /// In en, this message translates to:
  /// **'The Radar request was cancelled.'**
  String get discoverRadarCancelled;

  /// No description provided for @discoverRadarUnexpected.
  ///
  /// In en, this message translates to:
  /// **'QQ Music returned an unexpected Radar response.'**
  String get discoverRadarUnexpected;

  /// No description provided for @discoverNewAlbumServiceFailure.
  ///
  /// In en, this message translates to:
  /// **'New albums are temporarily unavailable.'**
  String get discoverNewAlbumServiceFailure;

  /// No description provided for @discoverNewAlbumCancelled.
  ///
  /// In en, this message translates to:
  /// **'The new-album request was cancelled.'**
  String get discoverNewAlbumCancelled;

  /// No description provided for @discoverNewAlbumUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected new-album response.'**
  String get discoverNewAlbumUnexpected;

  /// No description provided for @discoverNewSongServiceFailure.
  ///
  /// In en, this message translates to:
  /// **'New songs are temporarily unavailable.'**
  String get discoverNewSongServiceFailure;

  /// No description provided for @discoverNewSongCancelled.
  ///
  /// In en, this message translates to:
  /// **'The new-song request was cancelled.'**
  String get discoverNewSongCancelled;

  /// No description provided for @discoverNewSongUnexpected.
  ///
  /// In en, this message translates to:
  /// **'The music service returned an unexpected new-song response.'**
  String get discoverNewSongUnexpected;

  /// No description provided for @discoverRegionMainlandChina.
  ///
  /// In en, this message translates to:
  /// **'Mainland China'**
  String get discoverRegionMainlandChina;

  /// No description provided for @discoverRegionHongKongTaiwan.
  ///
  /// In en, this message translates to:
  /// **'Hong Kong / Taiwan'**
  String get discoverRegionHongKongTaiwan;

  /// No description provided for @discoverRegionWestern.
  ///
  /// In en, this message translates to:
  /// **'Western'**
  String get discoverRegionWestern;

  /// No description provided for @discoverRegionKorea.
  ///
  /// In en, this message translates to:
  /// **'Korea'**
  String get discoverRegionKorea;

  /// No description provided for @discoverRegionJapan.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get discoverRegionJapan;

  /// No description provided for @discoverRegionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get discoverRegionOther;

  /// No description provided for @discoverCategoryLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get discoverCategoryLatest;

  /// No description provided for @rankingTitle.
  ///
  /// In en, this message translates to:
  /// **'Ranking'**
  String get rankingTitle;

  /// Tooltip and accessibility name for returning from a ranking detail page.
  ///
  /// In en, this message translates to:
  /// **'Back to rankings'**
  String get rankingBackTooltip;

  /// No description provided for @rankingLoadingTracks.
  ///
  /// In en, this message translates to:
  /// **'Loading ranking tracks'**
  String get rankingLoadingTracks;

  /// Empty state when a ranking contains no playable tracks.
  ///
  /// In en, this message translates to:
  /// **'This ranking has no available tracks'**
  String get rankingEmptyTitle;

  /// Localized ranking empty detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an empty current-ranking track list.'**
  String rankingEmptyDetail(Object provider);

  /// No description provided for @rankingFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this ranking'**
  String get rankingFailureTitle;

  /// No description provided for @rankingEyebrow.
  ///
  /// In en, this message translates to:
  /// **'QQ MUSIC RANKING'**
  String get rankingEyebrow;

  /// Localized ranking showing tracks message.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} tracks'**
  String rankingShowingTracks(Object shown, Object total);

  /// No description provided for @rankingEnd.
  ///
  /// In en, this message translates to:
  /// **'End of current ranking'**
  String get rankingEnd;

  /// User-facing ranking service failure message.
  ///
  /// In en, this message translates to:
  /// **'{provider} rankings are temporarily unavailable.'**
  String rankingServiceFailure(Object provider);

  /// No description provided for @rankingCancelled.
  ///
  /// In en, this message translates to:
  /// **'The ranking request was cancelled.'**
  String get rankingCancelled;

  /// Localized ranking unexpected message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unexpected ranking response.'**
  String rankingUnexpected(Object provider);

  /// No description provided for @commonNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get commonNetworkFailure;

  /// No description provided for @commonCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The local music core is unavailable. Restart the app and try again.'**
  String get commonCoreUnavailable;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get commonSeeAll;

  /// Accessible common unavailable semantics message.
  ///
  /// In en, this message translates to:
  /// **'{label}, unavailable'**
  String commonUnavailableSemantics(Object label);

  /// Screen-reader group label for the personalized recommendation region.
  ///
  /// In en, this message translates to:
  /// **'Home recommendations'**
  String get homeRecommendationsSemantics;

  /// No description provided for @homeRefreshPartialFailure.
  ///
  /// In en, this message translates to:
  /// **'Some recommendations could not refresh. You can retry each section.'**
  String get homeRefreshPartialFailure;

  /// Localized home refresh success message.
  ///
  /// In en, this message translates to:
  /// **'Recommendations refreshed. {provider} may return the same picks.'**
  String homeRefreshSuccess(Object provider);

  /// No description provided for @homeRefreshWarning.
  ///
  /// In en, this message translates to:
  /// **'Some picks could not refresh. Showing the last available recommendations; use Refresh to retry.'**
  String get homeRefreshWarning;

  /// No description provided for @homePlaylistTreasures.
  ///
  /// In en, this message translates to:
  /// **'Your playlist treasures'**
  String get homePlaylistTreasures;

  /// No description provided for @homePopularPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Popular playlists'**
  String get homePopularPlaylists;

  /// No description provided for @homeRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing…'**
  String get homeRefreshing;

  /// No description provided for @homePersonalFm.
  ///
  /// In en, this message translates to:
  /// **'Personal FM'**
  String get homePersonalFm;

  /// No description provided for @homeSongsPickedForYou.
  ///
  /// In en, this message translates to:
  /// **'Songs picked for you'**
  String get homeSongsPickedForYou;

  /// No description provided for @homeNewSongs.
  ///
  /// In en, this message translates to:
  /// **'New songs'**
  String get homeNewSongs;

  /// No description provided for @homeFreshReleases.
  ///
  /// In en, this message translates to:
  /// **'Fresh releases'**
  String get homeFreshReleases;

  /// No description provided for @homePublicPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Public playlists'**
  String get homePublicPlaylists;

  /// No description provided for @homeMoreFromListening.
  ///
  /// In en, this message translates to:
  /// **'More from your listening'**
  String get homeMoreFromListening;

  /// No description provided for @homeChangePicks.
  ///
  /// In en, this message translates to:
  /// **'Change picks'**
  String get homeChangePicks;

  /// No description provided for @homeRecommendTab.
  ///
  /// In en, this message translates to:
  /// **'Recommend'**
  String get homeRecommendTab;

  /// No description provided for @homeMusicTab.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get homeMusicTab;

  /// No description provided for @homeAudiobooksTab.
  ///
  /// In en, this message translates to:
  /// **'Audiobooks'**
  String get homeAudiobooksTab;

  /// No description provided for @homeAudiobooksUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Audiobooks are not available'**
  String get homeAudiobooksUnavailable;

  /// No description provided for @homePodcastsTab.
  ///
  /// In en, this message translates to:
  /// **'Podcasts'**
  String get homePodcastsTab;

  /// No description provided for @homePodcastsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Podcasts are outside the current product scope'**
  String get homePodcastsUnavailable;

  /// No description provided for @homeSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get homeSignOut;

  /// Localized home sign in to provider message.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {provider}'**
  String homeSignInToProvider(Object provider);

  /// No description provided for @homeForYouEyebrow.
  ///
  /// In en, this message translates to:
  /// **'FOR YOU'**
  String get homeForYouEyebrow;

  /// No description provided for @homePublicSpotlightEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PUBLIC SPOTLIGHT'**
  String get homePublicSpotlightEyebrow;

  /// No description provided for @homeSelectedForYou.
  ///
  /// In en, this message translates to:
  /// **'Selected for you'**
  String get homeSelectedForYou;

  /// No description provided for @homeTodaysPick.
  ///
  /// In en, this message translates to:
  /// **'Today’s pick'**
  String get homeTodaysPick;

  /// No description provided for @homeLoadingRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Loading recommendations…'**
  String get homeLoadingRecommendations;

  /// No description provided for @homeRecommendationsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recommendations are unavailable. Please try again.'**
  String get homeRecommendationsUnavailable;

  /// No description provided for @homeNoRecommendations.
  ///
  /// In en, this message translates to:
  /// **'No recommendations right now. You can browse Discover.'**
  String get homeNoRecommendations;

  /// No description provided for @homePopularPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Popular playlist'**
  String get homePopularPlaylist;

  /// No description provided for @homeDailyTracks.
  ///
  /// In en, this message translates to:
  /// **'Daily tracks'**
  String get homeDailyTracks;

  /// No description provided for @homeDailyRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Daily recommendation'**
  String get homeDailyRecommendation;

  /// No description provided for @homeRadar.
  ///
  /// In en, this message translates to:
  /// **'Radar'**
  String get homeRadar;

  /// No description provided for @homeMusicService.
  ///
  /// In en, this message translates to:
  /// **'Music service'**
  String get homeMusicService;

  /// Accessible home track play semantics message.
  ///
  /// In en, this message translates to:
  /// **'{label}, {trackTitle}, {artists}. Play'**
  String homeTrackPlaySemantics(
    Object artists,
    Object label,
    Object trackTitle,
  );

  /// No description provided for @homePreviousSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Previous spotlight'**
  String get homePreviousSpotlight;

  /// No description provided for @homePauseSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Pause spotlight rotation'**
  String get homePauseSpotlight;

  /// No description provided for @homeResumeSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Resume spotlight rotation'**
  String get homeResumeSpotlight;

  /// No description provided for @homeNextSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Next spotlight'**
  String get homeNextSpotlight;

  /// Localized home retry section message.
  ///
  /// In en, this message translates to:
  /// **'Retry {title}'**
  String homeRetrySection(Object title);

  /// No description provided for @homeLoadingPublicPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Loading public playlists'**
  String get homeLoadingPublicPlaylists;

  /// No description provided for @homeNoPublicPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No public playlists right now'**
  String get homeNoPublicPlaylists;

  /// Localized home no public playlists detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not return any public playlist recommendations.'**
  String homeNoPublicPlaylistsDetail(Object provider);

  /// No description provided for @homePublicPlaylistsFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load public playlists'**
  String get homePublicPlaylistsFailure;

  /// No description provided for @homeNoAdditionalPublicPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No additional public playlists right now'**
  String get homeNoAdditionalPublicPlaylists;

  /// No description provided for @homeAvailablePublicShown.
  ///
  /// In en, this message translates to:
  /// **'The available public recommendations are shown above.'**
  String get homeAvailablePublicShown;

  /// No description provided for @homeLoadingPublicNewSongs.
  ///
  /// In en, this message translates to:
  /// **'Loading public new songs'**
  String get homeLoadingPublicNewSongs;

  /// No description provided for @homeNoNewSongs.
  ///
  /// In en, this message translates to:
  /// **'No new songs right now'**
  String get homeNoNewSongs;

  /// Localized home no new songs detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not return a public new-song collection.'**
  String homeNoNewSongsDetail(Object provider);

  /// No description provided for @homeNewSongsFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load new songs'**
  String get homeNewSongsFailure;

  /// No description provided for @homeLoadingYourPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Loading your playlists'**
  String get homeLoadingYourPlaylists;

  /// No description provided for @homeNoPersonalizedPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No personalized playlists right now'**
  String get homeNoPersonalizedPlaylists;

  /// No description provided for @homeNoPersonalizedPlaylistsDetail.
  ///
  /// In en, this message translates to:
  /// **'Try refreshing later, or browse public playlists in Discover.'**
  String get homeNoPersonalizedPlaylistsDetail;

  /// Accessible home personalized playlist semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, personalized playlist'**
  String homePersonalizedPlaylistSemantics(Object title);

  /// No description provided for @homeDiscoverAction.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get homeDiscoverAction;

  /// No description provided for @homeDailyAction.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get homeDailyAction;

  /// No description provided for @homeRankingsAction.
  ///
  /// In en, this message translates to:
  /// **'Rankings'**
  String get homeRankingsAction;

  /// No description provided for @homeLikedAction.
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get homeLikedAction;

  /// No description provided for @homeLoadingPersonalFm.
  ///
  /// In en, this message translates to:
  /// **'Loading Personal FM'**
  String get homeLoadingPersonalFm;

  /// No description provided for @homeLoadingPersonalizedSongs.
  ///
  /// In en, this message translates to:
  /// **'Loading personalized songs'**
  String get homeLoadingPersonalizedSongs;

  /// Empty state for a provider Personal FM recommendation.
  ///
  /// In en, this message translates to:
  /// **'Personal FM has no songs right now'**
  String get homePersonalFmEmpty;

  /// Empty state for personalized song recommendations.
  ///
  /// In en, this message translates to:
  /// **'No personalized songs right now'**
  String get homePersonalizedSongsEmpty;

  /// Supporting copy for the personalized-song empty state.
  ///
  /// In en, this message translates to:
  /// **'Public playlists and your Library remain available.'**
  String get homePersonalizedSongsEmptyDetail;

  /// No description provided for @homePersonalFmFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load Personal FM'**
  String get homePersonalFmFailure;

  /// No description provided for @homePersonalizedSongsFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load personalized songs'**
  String get homePersonalizedSongsFailure;

  /// No description provided for @homeOtherSectionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'Other Home sections are still available.'**
  String get homeOtherSectionsAvailable;

  /// Localized home loading related songs message.
  ///
  /// In en, this message translates to:
  /// **'Loading songs related to {seed}'**
  String homeLoadingRelatedSongs(Object seed);

  /// No description provided for @homeRecentListening.
  ///
  /// In en, this message translates to:
  /// **'your recent listening'**
  String get homeRecentListening;

  /// No description provided for @homeStartListeningTitle.
  ///
  /// In en, this message translates to:
  /// **'Start listening to discover more'**
  String get homeStartListeningTitle;

  /// No description provided for @homeStartListeningDetail.
  ///
  /// In en, this message translates to:
  /// **'After listening in fura, picks inspired by a recently heard song appear here. Listening history stays in this session.'**
  String get homeStartListeningDetail;

  /// No description provided for @homeNoRelatedSongs.
  ///
  /// In en, this message translates to:
  /// **'No related songs right now'**
  String get homeNoRelatedSongs;

  /// Localized home no related songs detail message.
  ///
  /// In en, this message translates to:
  /// **'The track’s music service returned no related songs for “{seed}”.'**
  String homeNoRelatedSongsDetail(Object seed);

  /// Localized home because listened message.
  ///
  /// In en, this message translates to:
  /// **'Because you listened to “{seed}”'**
  String homeBecauseListened(Object seed);

  /// No description provided for @homeRecentSong.
  ///
  /// In en, this message translates to:
  /// **'a recent song'**
  String get homeRecentSong;

  /// Localized home add track to queue message.
  ///
  /// In en, this message translates to:
  /// **'Add {trackTitle} to queue'**
  String homeAddTrackToQueue(Object trackTitle);

  /// No description provided for @homeMoreRecommendationsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'More recommendations aren’t available'**
  String get homeMoreRecommendationsUnavailable;

  /// No description provided for @homePrimaryRecommendationShown.
  ///
  /// In en, this message translates to:
  /// **'The primary recommendation state is shown above.'**
  String get homePrimaryRecommendationShown;

  /// No description provided for @homePreviousPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Previous playlists'**
  String get homePreviousPlaylists;

  /// No description provided for @homeNextPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Next playlists'**
  String get homeNextPlaylists;

  /// No description provided for @homePersonalizedInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlist response not recognized'**
  String get homePersonalizedInvalidTitle;

  /// No description provided for @homePersonalizedOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlists are offline'**
  String get homePersonalizedOfflineTitle;

  /// No description provided for @homePersonalizedUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlists are temporarily unavailable'**
  String get homePersonalizedUnavailableTitle;

  /// No description provided for @homePersonalizedReplacedTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlist request was replaced'**
  String get homePersonalizedReplacedTitle;

  /// No description provided for @homePersonalizedCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlist request was cancelled'**
  String get homePersonalizedCancelledTitle;

  /// No description provided for @homePersonalizedRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalized playlists are already loading'**
  String get homePersonalizedRunningTitle;

  /// No description provided for @homePersonalizedFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load personalized playlists'**
  String get homePersonalizedFailureTitle;

  /// Localized home personalized invalid detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned a personalized-playlist structure this client does not recognize. No account content was recorded.'**
  String homePersonalizedInvalidDetail(Object provider);

  /// No description provided for @homeNetworkRetryDetail.
  ///
  /// In en, this message translates to:
  /// **'Check the network connection, then try again.'**
  String get homeNetworkRetryDetail;

  /// Localized home personalized service detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} rejected or could not serve this request. Try again later.'**
  String homePersonalizedServiceDetail(Object provider);

  /// No description provided for @homePersonalizedReplacedDetail.
  ///
  /// In en, this message translates to:
  /// **'A newer authenticated recommendation request replaced this one.'**
  String get homePersonalizedReplacedDetail;

  /// No description provided for @homePersonalizedCancelledDetail.
  ///
  /// In en, this message translates to:
  /// **'The request ended before personalized playlists were returned.'**
  String get homePersonalizedCancelledDetail;

  /// No description provided for @homePersonalizedRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Wait for the active personalized-playlist request to finish.'**
  String get homePersonalizedRunningDetail;

  /// No description provided for @homePublicAndSearchAvailable.
  ///
  /// In en, this message translates to:
  /// **'Public recommendations and Search are still available.'**
  String get homePublicAndSearchAvailable;

  /// No description provided for @homeRelatedInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'This song can’t seed recommendations'**
  String get homeRelatedInvalidTitle;

  /// No description provided for @homeRelatedOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Related songs are offline'**
  String get homeRelatedOfflineTitle;

  /// No description provided for @homeRelatedUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Related songs are temporarily unavailable'**
  String get homeRelatedUnavailableTitle;

  /// No description provided for @homeRelatedInvalidResponseTitle.
  ///
  /// In en, this message translates to:
  /// **'Related-song response not recognized'**
  String get homeRelatedInvalidResponseTitle;

  /// No description provided for @homeRelatedCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Related-song request was cancelled'**
  String get homeRelatedCancelledTitle;

  /// No description provided for @homeRelatedRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Related songs are already loading'**
  String get homeRelatedRunningTitle;

  /// No description provided for @homeRelatedFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load related songs'**
  String get homeRelatedFailureTitle;

  /// Localized home related invalid track detail message.
  ///
  /// In en, this message translates to:
  /// **'“{seed}” has no usable music-service identity.'**
  String homeRelatedInvalidTrackDetail(Object seed);

  /// No description provided for @homeThisSong.
  ///
  /// In en, this message translates to:
  /// **'This song'**
  String get homeThisSong;

  /// No description provided for @homeRelatedServiceDetail.
  ///
  /// In en, this message translates to:
  /// **'The track’s music service could not serve related songs for this seed right now.'**
  String get homeRelatedServiceDetail;

  /// No description provided for @homeRelatedInvalidResponseDetail.
  ///
  /// In en, this message translates to:
  /// **'The track’s music service returned a related-song structure this client does not recognize.'**
  String get homeRelatedInvalidResponseDetail;

  /// No description provided for @homeRelatedCancelledDetail.
  ///
  /// In en, this message translates to:
  /// **'The seed changed before related songs were returned.'**
  String get homeRelatedCancelledDetail;

  /// No description provided for @homeRelatedRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Wait for the active related-song request to finish.'**
  String get homeRelatedRunningDetail;

  /// No description provided for @homeRelatedCoreDetail.
  ///
  /// In en, this message translates to:
  /// **'The related-song Core capability could not be reached.'**
  String get homeRelatedCoreDetail;

  /// No description provided for @homePublicLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading public recommendations…'**
  String get homePublicLoading;

  /// No description provided for @homePublicNoAdditional.
  ///
  /// In en, this message translates to:
  /// **'No additional public recommendation is available right now.'**
  String get homePublicNoAdditional;

  /// Localized home public empty message.
  ///
  /// In en, this message translates to:
  /// **'{provider} has no public recommendation available right now.'**
  String homePublicEmpty(Object provider);

  /// No description provided for @homePublicFailure.
  ///
  /// In en, this message translates to:
  /// **'Public recommendations could not be loaded.'**
  String get homePublicFailure;

  /// No description provided for @homeLoadingDailyTracks.
  ///
  /// In en, this message translates to:
  /// **'Loading your daily tracks…'**
  String get homeLoadingDailyTracks;

  /// No description provided for @homeLoadingDaily30.
  ///
  /// In en, this message translates to:
  /// **'Loading your Daily 30…'**
  String get homeLoadingDaily30;

  /// No description provided for @homeDailyTracksUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Daily tracks are unavailable right now.'**
  String get homeDailyTracksUnavailable;

  /// No description provided for @homeDaily30Unavailable.
  ///
  /// In en, this message translates to:
  /// **'Daily 30 is unavailable right now.'**
  String get homeDaily30Unavailable;

  /// No description provided for @homeDailyTracksFailure.
  ///
  /// In en, this message translates to:
  /// **'Daily tracks could not be loaded.'**
  String get homeDailyTracksFailure;

  /// No description provided for @homeDaily30Failure.
  ///
  /// In en, this message translates to:
  /// **'Daily 30 could not be loaded.'**
  String get homeDaily30Failure;

  /// No description provided for @homeRadarLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your Radar recommendations…'**
  String get homeRadarLoading;

  /// No description provided for @homeRadarUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Radar is unavailable right now.'**
  String get homeRadarUnavailable;

  /// Empty state for QQ Music Radar recommendations; do not reuse for another provider capability.
  ///
  /// In en, this message translates to:
  /// **'QQ Music has no Radar recommendation right now.'**
  String get homeRadarEmpty;

  /// No description provided for @homeRadarFailure.
  ///
  /// In en, this message translates to:
  /// **'Radar recommendations could not be loaded.'**
  String get homeRadarFailure;

  /// No description provided for @homePublicNewSongsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading public new songs…'**
  String get homePublicNewSongsLoading;

  /// No description provided for @homePublicNewSongsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No public new song is available right now.'**
  String get homePublicNewSongsUnavailable;

  /// Localized home public new songs empty message.
  ///
  /// In en, this message translates to:
  /// **'{provider} has no public new songs right now.'**
  String homePublicNewSongsEmpty(Object provider);

  /// No description provided for @homePublicNewSongsFailure.
  ///
  /// In en, this message translates to:
  /// **'Public new songs could not be loaded.'**
  String get homePublicNewSongsFailure;

  /// User-facing home new songs service failure message.
  ///
  /// In en, this message translates to:
  /// **'{provider} new songs are temporarily unavailable.'**
  String homeNewSongsServiceFailure(Object provider);

  /// Localized home new songs invalid response message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned a new-song response this client does not recognize.'**
  String homeNewSongsInvalidResponse(Object provider);

  /// No description provided for @homeNewSongsRunning.
  ///
  /// In en, this message translates to:
  /// **'Wait for the active new-song request to finish.'**
  String get homeNewSongsRunning;

  /// No description provided for @homeMusicPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Music playlist'**
  String get homeMusicPlaylist;

  /// Accessible home music playlist semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, music playlist'**
  String homeMusicPlaylistSemantics(Object title);

  /// No description provided for @libraryPlaylistType.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get libraryPlaylistType;

  /// No description provided for @libraryTrackCountColumn.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get libraryTrackCountColumn;

  /// No description provided for @libraryBackToPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Back to playlists'**
  String get libraryBackToPlaylists;

  /// No description provided for @libraryRefreshingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Refreshing playlist'**
  String get libraryRefreshingPlaylist;

  /// No description provided for @libraryRefreshPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Refresh playlist'**
  String get libraryRefreshPlaylist;

  /// Empty state title for an account playlist with no tracks.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get libraryPlaylistEmptyTitle;

  /// Localized library playlist empty detail message.
  ///
  /// In en, this message translates to:
  /// **'Tracks added in {provider} will appear here.'**
  String libraryPlaylistEmptyDetail(Object provider);

  /// Pluralized library playlist count summary message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}} · {provider}'**
  String libraryPlaylistCountSummary(num count, Object provider);

  /// Localized library playlist end message.
  ///
  /// In en, this message translates to:
  /// **'All {total} tracks are loaded'**
  String libraryPlaylistEnd(Object total);

  /// No description provided for @libraryRefreshPlaylistFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh this playlist. The previous tracks are still shown.'**
  String get libraryRefreshPlaylistFailure;

  /// No description provided for @likedTitle.
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get likedTitle;

  /// No description provided for @likedProgramsUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Liked audio programs aren’t connected yet'**
  String get likedProgramsUnavailableTitle;

  /// No description provided for @likedProgramsUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'The current account-library capability includes songs, playlists, albums, and artists, but not audio-program favorites.'**
  String get likedProgramsUnavailableDetail;

  /// No description provided for @likedVideosUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Liked videos aren’t connected yet'**
  String get likedVideosUnavailableTitle;

  /// No description provided for @likedVideosUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'Music videos linked to songs are not the same as the account’s liked videos, so they are not mixed here.'**
  String get likedVideosUnavailableDetail;

  /// No description provided for @likedPlaylistUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t find the Liked Songs playlist'**
  String get likedPlaylistUnavailableTitle;

  /// Localized liked playlist unavailable detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not return its built-in Liked Songs playlist. Other favorites are still available from the tabs above.'**
  String likedPlaylistUnavailableDetail(Object provider);

  /// No description provided for @likedLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading Liked Songs…'**
  String get likedLoadingTitle;

  /// Localized liked loading detail message.
  ///
  /// In en, this message translates to:
  /// **'Reading favorites from {provider}.'**
  String likedLoadingDetail(Object provider);

  /// Empty state title for the account's Liked Songs collection.
  ///
  /// In en, this message translates to:
  /// **'No Liked Songs yet'**
  String get likedEmptyTitle;

  /// Localized liked empty detail message.
  ///
  /// In en, this message translates to:
  /// **'Songs you like in {provider} will appear here.'**
  String likedEmptyDetail(Object provider);

  /// No description provided for @likedSearchingAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Searching the entire playlist…'**
  String get likedSearchingAllTitle;

  /// No description provided for @likedNoTrackMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching tracks'**
  String get likedNoTrackMatchTitle;

  /// Localized liked search progress message.
  ///
  /// In en, this message translates to:
  /// **'Checked {processed} of {total} tracks. Matches update while pages load.'**
  String likedSearchProgress(Object processed, Object total);

  /// Localized liked search finished no match message.
  ///
  /// In en, this message translates to:
  /// **'Searched all {total} tracks{omitted}; try another keyword.'**
  String likedSearchFinishedNoMatch(Object omitted, Object total);

  /// No description provided for @likedContinueSearch.
  ///
  /// In en, this message translates to:
  /// **'Continue search'**
  String get likedContinueSearch;

  /// No description provided for @likedQueueAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to playback queue'**
  String get likedQueueAdded;

  /// Localized liked songs tab message.
  ///
  /// In en, this message translates to:
  /// **'Songs {count}'**
  String likedSongsTab(Object count);

  /// No description provided for @likedSongsTabWithoutCount.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get likedSongsTabWithoutCount;

  /// Localized liked playlists tab message.
  ///
  /// In en, this message translates to:
  /// **'Playlists {count}'**
  String likedPlaylistsTab(Object count);

  /// No description provided for @likedAlbumsTab.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get likedAlbumsTab;

  /// No description provided for @likedProgramsTab.
  ///
  /// In en, this message translates to:
  /// **'Audio programs'**
  String get likedProgramsTab;

  /// No description provided for @likedVideosTab.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get likedVideosTab;

  /// No description provided for @likedNoPlaylistMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching playlists'**
  String get likedNoPlaylistMatch;

  /// No description provided for @likedNoOtherPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No other playlists yet'**
  String get likedNoOtherPlaylists;

  /// No description provided for @likedTryAnotherKeyword.
  ///
  /// In en, this message translates to:
  /// **'Try another keyword.'**
  String get likedTryAnotherKeyword;

  /// No description provided for @likedCreatedPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Created Playlists'**
  String get likedCreatedPlaylists;

  /// No description provided for @likedSavedPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Saved Playlists'**
  String get likedSavedPlaylists;

  /// No description provided for @likedOtherPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Other Playlists'**
  String get likedOtherPlaylists;

  /// Localized liked playlist collection detail message.
  ///
  /// In en, this message translates to:
  /// **'Playlists you create or save in {provider} will appear here.'**
  String likedPlaylistCollectionDetail(Object provider);

  /// Localized liked playlist section count message.
  ///
  /// In en, this message translates to:
  /// **'{title} {count}'**
  String likedPlaylistSectionCount(Object count, Object title);

  /// Accessible liked playlist semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, playlist'**
  String likedPlaylistSemantics(Object title);

  /// Pluralized liked track count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String likedTrackCount(num count);

  /// No description provided for @likedPlayAll.
  ///
  /// In en, this message translates to:
  /// **'Play all'**
  String get likedPlayAll;

  /// No description provided for @likedRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing'**
  String get likedRefreshing;

  /// No description provided for @likedRefreshSongs.
  ///
  /// In en, this message translates to:
  /// **'Refresh Liked Songs'**
  String get likedRefreshSongs;

  /// No description provided for @likedSearchEntirePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Search entire playlist'**
  String get likedSearchEntirePlaylist;

  /// No description provided for @likedSearchPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Search playlists'**
  String get likedSearchPlaylists;

  /// No description provided for @likedSearchLoadedAlbums.
  ///
  /// In en, this message translates to:
  /// **'Search loaded albums'**
  String get likedSearchLoadedAlbums;

  /// No description provided for @likedProgramsSearchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Liked audio programs aren’t connected yet'**
  String get likedProgramsSearchUnavailable;

  /// No description provided for @likedVideosSearchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Liked videos aren’t connected yet'**
  String get likedVideosSearchUnavailable;

  /// No description provided for @likedMultipleArtistsDetail.
  ///
  /// In en, this message translates to:
  /// **'This track includes multiple artists. Choose the artist to open.'**
  String get likedMultipleArtistsDetail;

  /// No description provided for @likedRetryLoad.
  ///
  /// In en, this message translates to:
  /// **'Retry loading'**
  String get likedRetryLoad;

  /// Localized liked read status message.
  ///
  /// In en, this message translates to:
  /// **'Read {processed} / {total} tracks; {available} can be shown'**
  String likedReadStatus(Object available, Object processed, Object total);

  /// Localized liked search interrupted status message.
  ///
  /// In en, this message translates to:
  /// **'Search interrupted · checked {processed} / {total} tracks'**
  String likedSearchInterruptedStatus(Object processed, Object total);

  /// No description provided for @likedSearchInterruptedTitle.
  ///
  /// In en, this message translates to:
  /// **'Search interrupted'**
  String get likedSearchInterruptedTitle;

  /// Localized liked search interrupted detail message.
  ///
  /// In en, this message translates to:
  /// **'Checked {processed} of {total} tracks. Retry to search the remaining tracks.'**
  String likedSearchInterruptedDetail(Object processed, Object total);

  /// Localized liked omitted search suffix message.
  ///
  /// In en, this message translates to:
  /// **'; {count} tracks have no searchable identity'**
  String likedOmittedSearchSuffix(Object count);

  /// Localized liked omitted tracks detail message.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks have no usable identity. They were skipped without stopping later pages.'**
  String likedOmittedTracksDetail(Object count);

  /// Localized liked exact results message.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String likedExactResults(Object count);

  /// Localized liked approximate results message.
  ///
  /// In en, this message translates to:
  /// **'{count} possible results'**
  String likedApproximateResults(Object count);

  /// Localized liked searching status message.
  ///
  /// In en, this message translates to:
  /// **'Found {results} · checking {processed} / {total} tracks'**
  String likedSearchingStatus(Object processed, Object results, Object total);

  /// Localized liked approximate only status message.
  ///
  /// In en, this message translates to:
  /// **'No exact matches · showing {results}'**
  String likedApproximateOnlyStatus(Object results);

  /// Localized liked mixed results message.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks ({approximate} possible results)'**
  String likedMixedResults(Object approximate, Object count);

  /// Localized liked search complete status message.
  ///
  /// In en, this message translates to:
  /// **'Searched all {total} tracks · found {results}'**
  String likedSearchCompleteStatus(Object results, Object total);

  /// No description provided for @likedFailureNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable'**
  String get likedFailureNetworkTitle;

  /// No description provided for @likedFailureNetworkDetail.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get likedFailureNetworkDetail;

  /// User-facing liked failure service title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} is temporarily unavailable'**
  String likedFailureServiceTitle(Object provider);

  /// No description provided for @likedFailureServiceDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session remains unchanged. Try again later.'**
  String get likedFailureServiceDetail;

  /// No description provided for @likedFailureSignedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in expired'**
  String get likedFailureSignedOutTitle;

  /// No description provided for @likedFailureSignedOutDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to load Liked Songs.'**
  String get likedFailureSignedOutDetail;

  /// No description provided for @likedFailureAuthenticationTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get likedFailureAuthenticationTitle;

  /// User-facing liked failure authentication detail message.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {provider} to continue.'**
  String likedFailureAuthenticationDetail(Object provider);

  /// No description provided for @likedFailureInvalidTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t safely read Liked Songs'**
  String get likedFailureInvalidTitle;

  /// No description provided for @likedFailureInvalidDetail.
  ///
  /// In en, this message translates to:
  /// **'Try again. Partial results were not shown.'**
  String get likedFailureInvalidDetail;

  /// No description provided for @likedFailureCoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load Liked Songs'**
  String get likedFailureCoreTitle;

  /// No description provided for @likedFailureCoreDetail.
  ///
  /// In en, this message translates to:
  /// **'Try again, or restart the app and retry.'**
  String get likedFailureCoreDetail;

  /// No description provided for @likedFailureGenericDetail.
  ///
  /// In en, this message translates to:
  /// **'Try again.'**
  String get likedFailureGenericDetail;

  /// No description provided for @likedRefreshNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed: check your network.'**
  String get likedRefreshNetworkFailure;

  /// User-facing liked refresh service failure message.
  ///
  /// In en, this message translates to:
  /// **'{provider} cannot refresh right now.'**
  String likedRefreshServiceFailure(Object provider);

  /// No description provided for @likedRefreshInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The refresh result could not be read safely.'**
  String get likedRefreshInvalidResponse;

  /// No description provided for @likedRefreshFailure.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed; the previous result is still shown.'**
  String get likedRefreshFailure;

  /// No description provided for @recentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get recentTitle;

  /// No description provided for @recentCloudSubtitle.
  ///
  /// In en, this message translates to:
  /// **'QQ Music account playback history · newest first'**
  String get recentCloudSubtitle;

  /// No description provided for @recentCloudNotConnectedShort.
  ///
  /// In en, this message translates to:
  /// **'QQ Music cloud history isn’t connected yet'**
  String get recentCloudNotConnectedShort;

  /// Localized recent processed status message.
  ///
  /// In en, this message translates to:
  /// **'{action} {processed}{total} tracks{approximate}{omitted}'**
  String recentProcessedStatus(
    Object action,
    Object approximate,
    Object omitted,
    Object processed,
    Object total,
  );

  /// No description provided for @recentLoadedAction.
  ///
  /// In en, this message translates to:
  /// **'Loaded'**
  String get recentLoadedAction;

  /// No description provided for @recentSearchedAction.
  ///
  /// In en, this message translates to:
  /// **'Searched'**
  String get recentSearchedAction;

  /// Localized recent total part message.
  ///
  /// In en, this message translates to:
  /// **' / {total}'**
  String recentTotalPart(Object total);

  /// Localized recent approximate part message.
  ///
  /// In en, this message translates to:
  /// **' · {count} approximate matches'**
  String recentApproximatePart(Object count);

  /// Localized recent omitted part message.
  ///
  /// In en, this message translates to:
  /// **' · {count} tracks cannot be shown'**
  String recentOmittedPart(Object count);

  /// Localized recent songs tab message.
  ///
  /// In en, this message translates to:
  /// **'Songs {count}'**
  String recentSongsTab(Object count);

  /// Localized recent songs tab approximate message.
  ///
  /// In en, this message translates to:
  /// **'Songs {count}+'**
  String recentSongsTabApproximate(Object count);

  /// No description provided for @recentSongsTabWithoutCount.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get recentSongsTabWithoutCount;

  /// No description provided for @recentSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search recently played'**
  String get recentSearchHint;

  /// No description provided for @recentRefreshSnapshotFailure.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed; the previous records are still shown.'**
  String get recentRefreshSnapshotFailure;

  /// Tooltip and accessibility name for playing the recently played collection.
  ///
  /// In en, this message translates to:
  /// **'Play recently played'**
  String get recentPlayTooltip;

  /// Tooltip and accessibility name for refreshing recently played records.
  ///
  /// In en, this message translates to:
  /// **'Refresh recently played'**
  String get recentRefreshTooltip;

  /// No description provided for @recentUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Cross-device playback history is unavailable'**
  String get recentUnavailableTitle;

  /// No description provided for @recentUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'This version has not connected QQ Music cloud recent play yet.\nOnce connected, playback history for this account will appear here.'**
  String get recentUnavailableDetail;

  /// No description provided for @recentLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading recently played…'**
  String get recentLoadingTitle;

  /// No description provided for @recentSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to QQ Music again'**
  String get recentSignInTitle;

  /// No description provided for @recentSignInDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in to the same account before reading cloud playback history.'**
  String get recentSignInDetail;

  /// No description provided for @recentUnavailableTemporaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently played is temporarily unavailable'**
  String get recentUnavailableTemporaryTitle;

  /// No description provided for @recentTryLater.
  ///
  /// In en, this message translates to:
  /// **'Try again later.'**
  String get recentTryLater;

  /// Empty state title for verified cloud recent-play history.
  ///
  /// In en, this message translates to:
  /// **'No cloud playback history yet'**
  String get recentEmptyTitle;

  /// Supporting copy for a successful but empty cloud recent-play response.
  ///
  /// In en, this message translates to:
  /// **'Refresh to read the records returned by QQ Music again.'**
  String get recentEmptyDetail;

  /// No description provided for @recentSearchingAll.
  ///
  /// In en, this message translates to:
  /// **'Searching all playback history…'**
  String get recentSearchingAll;

  /// No description provided for @recentNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching tracks'**
  String get recentNoMatch;

  /// No description provided for @recentAppendFailure.
  ///
  /// In en, this message translates to:
  /// **'Later records could not be loaded. Loaded tracks remain playable.'**
  String get recentAppendFailure;

  /// No description provided for @recentContinueLoading.
  ///
  /// In en, this message translates to:
  /// **'Continue loading'**
  String get recentContinueLoading;

  /// No description provided for @recentAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to playback queue'**
  String get recentAddToQueue;

  /// No description provided for @recentChooseArtistDetail.
  ///
  /// In en, this message translates to:
  /// **'This track includes multiple artists. Choose the artist to open.'**
  String get recentChooseArtistDetail;

  /// Localized library showing tracks message.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} tracks'**
  String libraryShowingTracks(Object shown, Object total);

  /// No description provided for @libraryEndPlaylist.
  ///
  /// In en, this message translates to:
  /// **'End of playlist'**
  String get libraryEndPlaylist;

  /// User-facing library failure reach title message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach {provider}'**
  String libraryFailureReachTitle(Object provider);

  /// No description provided for @libraryFailureReachDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session is still active. Check your connection and try again.'**
  String get libraryFailureReachDetail;

  /// User-facing library failure unavailable title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} is unavailable'**
  String libraryFailureUnavailableTitle(Object provider);

  /// No description provided for @libraryFailureUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'The playlist could not be loaded right now. Your session was kept.'**
  String get libraryFailureUnavailableDetail;

  /// No description provided for @libraryFailureReadTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read this playlist'**
  String get libraryFailureReadTitle;

  /// User-facing library failure read detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned data this build could not safely present.'**
  String libraryFailureReadDetail(Object provider);

  /// No description provided for @libraryFailureRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your saved session was rejected'**
  String get libraryFailureRejectedTitle;

  /// User-facing library failure rejected detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} no longer accepts it, so the stored session was removed.'**
  String libraryFailureRejectedDetail(Object provider);

  /// User-facing library failure rejected cleanup detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} rejected it, but secure storage could not remove it.'**
  String libraryFailureRejectedCleanupDetail(Object provider);

  /// No description provided for @libraryFailureSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to open this playlist'**
  String get libraryFailureSignInTitle;

  /// No description provided for @libraryFailureAccountChangedDetail.
  ///
  /// In en, this message translates to:
  /// **'The account state changed before the request finished.'**
  String get libraryFailureAccountChangedDetail;

  /// No description provided for @libraryFailureCoreTitle.
  ///
  /// In en, this message translates to:
  /// **'The music core is unavailable'**
  String get libraryFailureCoreTitle;

  /// No description provided for @libraryFailureCoreDetail.
  ///
  /// In en, this message translates to:
  /// **'This playlist could not be loaded safely.'**
  String get libraryFailureCoreDetail;

  /// No description provided for @libraryFailureRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'A playlist request is already running'**
  String get libraryFailureRunningTitle;

  /// No description provided for @libraryFailureRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Wait for it to finish, then try again.'**
  String get libraryFailureRunningDetail;

  /// No description provided for @libraryFailureGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this playlist'**
  String get libraryFailureGenericTitle;

  /// No description provided for @libraryFailureGenericDetail.
  ///
  /// In en, this message translates to:
  /// **'Try again or sign in again.'**
  String get libraryFailureGenericDetail;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get navDiscover;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navLiked.
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get navLiked;

  /// No description provided for @navRecentPlays.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get navRecentPlays;

  /// No description provided for @navOnlineMusicSection.
  ///
  /// In en, this message translates to:
  /// **'ONLINE MUSIC'**
  String get navOnlineMusicSection;

  /// No description provided for @navMyMusicSection.
  ///
  /// In en, this message translates to:
  /// **'MY MUSIC'**
  String get navMyMusicSection;

  /// No description provided for @navYourPlaylistsSection.
  ///
  /// In en, this message translates to:
  /// **'YOUR PLAYLISTS'**
  String get navYourPlaylistsSection;

  /// No description provided for @navSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get navSettingsSection;

  /// Localized shell search provider message.
  ///
  /// In en, this message translates to:
  /// **'Search {provider}'**
  String shellSearchProvider(Object provider);

  /// No description provided for @shellSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get shellSignOut;

  /// No description provided for @shellSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get shellSignIn;

  /// Localized shell sign in to provider message.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {provider}'**
  String shellSignInToProvider(Object provider);

  /// Localized shell loading provider account message.
  ///
  /// In en, this message translates to:
  /// **'Loading {provider} account…'**
  String shellLoadingProviderAccount(Object provider);

  /// Localized shell provider client message.
  ///
  /// In en, this message translates to:
  /// **'{provider} client'**
  String shellProviderClient(Object provider);

  /// No description provided for @shellBackToMusic.
  ///
  /// In en, this message translates to:
  /// **'Back to music'**
  String get shellBackToMusic;

  /// No description provided for @shellBackToFavoriteArtists.
  ///
  /// In en, this message translates to:
  /// **'Back to favorite artists'**
  String get shellBackToFavoriteArtists;

  /// No description provided for @shellBackToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Back to playlist'**
  String get shellBackToPlaylist;

  /// No description provided for @shellBackToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Back to album'**
  String get shellBackToAlbum;

  /// No description provided for @shellBackToPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Back to previous page'**
  String get shellBackToPreviousPage;

  /// No description provided for @shellBackToSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Back to search results'**
  String get shellBackToSearchResults;

  /// No description provided for @shellBackToArtist.
  ///
  /// In en, this message translates to:
  /// **'Back to artist'**
  String get shellBackToArtist;

  /// No description provided for @shellBackToNewAlbums.
  ///
  /// In en, this message translates to:
  /// **'Back to new albums'**
  String get shellBackToNewAlbums;

  /// No description provided for @shellBackToFavoriteAlbums.
  ///
  /// In en, this message translates to:
  /// **'Back to favorite albums'**
  String get shellBackToFavoriteAlbums;

  /// No description provided for @libraryYourPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get libraryYourPlaylists;

  /// Pluralized library playlists saved count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 playlist saved on {provider}} other{{count} playlists saved on {provider}}}'**
  String libraryPlaylistsSavedCount(num count, Object provider);

  /// Localized library playlists saved provider message.
  ///
  /// In en, this message translates to:
  /// **'Saved on {provider}'**
  String libraryPlaylistsSavedProvider(Object provider);

  /// No description provided for @libraryRefreshingPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Refreshing playlists'**
  String get libraryRefreshingPlaylists;

  /// No description provided for @libraryRefreshPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Refresh playlists'**
  String get libraryRefreshPlaylists;

  /// Pluralized library playlist count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String libraryPlaylistCount(num count);

  /// No description provided for @libraryLoadingPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Loading your playlists…'**
  String get libraryLoadingPlaylists;

  /// No description provided for @libraryNoPlaylistsTitle.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get libraryNoPlaylistsTitle;

  /// Localized library no playlists detail message.
  ///
  /// In en, this message translates to:
  /// **'Playlists you create or save in {provider} will appear here.'**
  String libraryNoPlaylistsDetail(Object provider);

  /// No description provided for @librarySignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see your music'**
  String get librarySignInTitle;

  /// Localized library sign in detail message.
  ///
  /// In en, this message translates to:
  /// **'Your {provider} playlists, Liked Songs, albums, and artists will appear here.'**
  String librarySignInDetail(Object provider);

  /// Title of the destructive confirmation that signs out and removes the saved session from this device.
  ///
  /// In en, this message translates to:
  /// **'Sign out on this device?'**
  String get librarySignOutConfirmTitle;

  /// Localized library sign out confirm detail message.
  ///
  /// In en, this message translates to:
  /// **'This will stop playback and remove the saved {provider} session from this device.'**
  String librarySignOutConfirmDetail(Object provider);

  /// No description provided for @librarySignOutFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t sign out. Your local session is unchanged.'**
  String get librarySignOutFailure;

  /// No description provided for @libraryQualitySaveFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save playback quality. Nothing changed.'**
  String get libraryQualitySaveFailure;

  /// No description provided for @libraryRefreshFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh playlists. The previous results are still shown.'**
  String get libraryRefreshFailure;

  /// No description provided for @libraryFailureReachCollectionDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session is still active. Check your connection and try again.'**
  String get libraryFailureReachCollectionDetail;

  /// No description provided for @libraryFailureServiceCollectionDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session was kept unchanged. Try loading your playlists again later.'**
  String get libraryFailureServiceCollectionDetail;

  /// No description provided for @libraryFailureCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read the complete library'**
  String get libraryFailureCompleteTitle;

  /// User-facing library failure complete detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned a collection this build could not safely finish. No partial list is shown.'**
  String libraryFailureCompleteDetail(Object provider);

  /// No description provided for @libraryFailureSignInPlaylistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to load your playlists'**
  String get libraryFailureSignInPlaylistsTitle;

  /// No description provided for @libraryFailureRequestChangedDetail.
  ///
  /// In en, this message translates to:
  /// **'The account state changed before this library request finished.'**
  String get libraryFailureRequestChangedDetail;

  /// No description provided for @libraryFailureCoreCollectionDetail.
  ///
  /// In en, this message translates to:
  /// **'Your library could not be loaded safely. Try again after restarting.'**
  String get libraryFailureCoreCollectionDetail;

  /// No description provided for @libraryFailureRunningCollectionTitle.
  ///
  /// In en, this message translates to:
  /// **'A library request is already running'**
  String get libraryFailureRunningCollectionTitle;

  /// No description provided for @libraryFailureGenericCollectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your playlists'**
  String get libraryFailureGenericCollectionTitle;

  /// User-facing library failure generic collection detail message.
  ///
  /// In en, this message translates to:
  /// **'Try again or sign in with a fresh {provider} session.'**
  String libraryFailureGenericCollectionDetail(Object provider);

  /// No description provided for @favoriteAlbumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorite albums'**
  String get favoriteAlbumsTitle;

  /// No description provided for @favoriteArtistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorite artists'**
  String get favoriteArtistsTitle;

  /// Localized favorite saved count message.
  ///
  /// In en, this message translates to:
  /// **'{count} saved on {provider}'**
  String favoriteSavedCount(Object count, Object provider);

  /// Localized favorite saved provider message.
  ///
  /// In en, this message translates to:
  /// **'Saved on {provider}'**
  String favoriteSavedProvider(Object provider);

  /// No description provided for @favoriteAlbumsRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing favorite albums'**
  String get favoriteAlbumsRefreshing;

  /// No description provided for @favoriteAlbumsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh favorite albums'**
  String get favoriteAlbumsRefresh;

  /// No description provided for @favoriteArtistsRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing favorite artists'**
  String get favoriteArtistsRefreshing;

  /// No description provided for @favoriteArtistsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh favorite artists'**
  String get favoriteArtistsRefresh;

  /// No description provided for @favoriteAlbumsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading favorite albums'**
  String get favoriteAlbumsLoading;

  /// No description provided for @favoriteArtistsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading favorite artists'**
  String get favoriteArtistsLoading;

  /// Empty state title for the account's favorite albums.
  ///
  /// In en, this message translates to:
  /// **'No favorite albums yet'**
  String get favoriteAlbumsEmptyTitle;

  /// Localized favorite albums empty detail message.
  ///
  /// In en, this message translates to:
  /// **'Albums you save in {provider} will appear here.'**
  String favoriteAlbumsEmptyDetail(Object provider);

  /// Empty state title for the account's favorite artists.
  ///
  /// In en, this message translates to:
  /// **'No favorite artists yet'**
  String get favoriteArtistsEmptyTitle;

  /// Localized favorite artists empty detail message.
  ///
  /// In en, this message translates to:
  /// **'Artists you follow in {provider} will appear here.'**
  String favoriteArtistsEmptyDetail(Object provider);

  /// Empty state title when filtering loaded favorite albums finds no match.
  ///
  /// In en, this message translates to:
  /// **'No matching albums'**
  String get favoriteAlbumsSearchEmptyTitle;

  /// Supporting copy for an empty favorite-album filter result.
  ///
  /// In en, this message translates to:
  /// **'Try another keyword. Search covers the favorite albums already loaded.'**
  String get favoriteAlbumsSearchEmptyDetail;

  /// No description provided for @favoriteAlbumsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load favorite albums'**
  String get favoriteAlbumsFailureTitle;

  /// No description provided for @favoriteArtistsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load favorite artists'**
  String get favoriteArtistsFailureTitle;

  /// No description provided for @favoriteAlbumsSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see favorite albums'**
  String get favoriteAlbumsSignInTitle;

  /// No description provided for @favoriteAlbumsSignInDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to load your favorite albums.'**
  String get favoriteAlbumsSignInDetail;

  /// No description provided for @favoriteArtistsSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to see favorite artists'**
  String get favoriteArtistsSignInTitle;

  /// No description provided for @favoriteArtistsSignInDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to load your favorite artists.'**
  String get favoriteArtistsSignInDetail;

  /// User-facing favorite session rejected title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} session rejected'**
  String favoriteSessionRejectedTitle(Object provider);

  /// User-facing favorite session rejected cleanup detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} rejected this session, and its saved copy could not be removed.'**
  String favoriteSessionRejectedCleanupDetail(Object provider);

  /// User-facing favorite session rejected detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} no longer accepts this saved session.'**
  String favoriteSessionRejectedDetail(Object provider);

  /// Accessible favorite album semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, album'**
  String favoriteAlbumSemantics(Object title);

  /// Accessible favorite artist semantics message.
  ///
  /// In en, this message translates to:
  /// **'{name}, artist'**
  String favoriteArtistSemantics(Object name);

  /// User-facing favorite failure network message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach {provider}. Check the connection and try again.'**
  String favoriteFailureNetwork(Object provider);

  /// User-facing favorite albums failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} could not load favorite albums right now.'**
  String favoriteAlbumsFailureService(Object provider);

  /// User-facing favorite artists failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} could not load favorite artists right now.'**
  String favoriteArtistsFailureService(Object provider);

  /// User-facing favorite albums failure invalid message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unreadable favorite-album page.'**
  String favoriteAlbumsFailureInvalid(Object provider);

  /// User-facing favorite artists failure invalid message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unreadable favorite-artist page.'**
  String favoriteArtistsFailureInvalid(Object provider);

  /// No description provided for @favoriteFailureCore.
  ///
  /// In en, this message translates to:
  /// **'The music core is unavailable. Try again.'**
  String get favoriteFailureCore;

  /// No description provided for @favoriteAlbumsFailureRunning.
  ///
  /// In en, this message translates to:
  /// **'A favorite-album request is already running.'**
  String get favoriteAlbumsFailureRunning;

  /// No description provided for @favoriteArtistsFailureRunning.
  ///
  /// In en, this message translates to:
  /// **'A favorite-artist request is already running.'**
  String get favoriteArtistsFailureRunning;

  /// No description provided for @favoriteFailureSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to continue.'**
  String get favoriteFailureSignIn;

  /// No description provided for @albumType.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get albumType;

  /// No description provided for @albumLoadingTracks.
  ///
  /// In en, this message translates to:
  /// **'Loading album tracks'**
  String get albumLoadingTracks;

  /// Empty state title when an album has no available tracks.
  ///
  /// In en, this message translates to:
  /// **'This album has no available tracks'**
  String get albumEmptyTitle;

  /// Localized album empty detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an empty album track list.'**
  String albumEmptyDetail(Object provider);

  /// No description provided for @albumFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this album'**
  String get albumFailureTitle;

  /// Localized album about title message.
  ///
  /// In en, this message translates to:
  /// **'About {title}'**
  String albumAboutTitle(Object title);

  /// No description provided for @albumChooseArtistTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an artist'**
  String get albumChooseArtistTitle;

  /// Pluralized album track count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String albumTrackCount(num count);

  /// Localized album provider summary message.
  ///
  /// In en, this message translates to:
  /// **'{provider} album'**
  String albumProviderSummary(Object provider);

  /// No description provided for @albumAboutAction.
  ///
  /// In en, this message translates to:
  /// **'About this album'**
  String get albumAboutAction;

  /// No description provided for @albumRetryDetails.
  ///
  /// In en, this message translates to:
  /// **'Retry details'**
  String get albumRetryDetails;

  /// No description provided for @albumMultipleArtistsDetail.
  ///
  /// In en, this message translates to:
  /// **'This album credits more than one artist.'**
  String get albumMultipleArtistsDetail;

  /// No description provided for @albumEnd.
  ///
  /// In en, this message translates to:
  /// **'End of album'**
  String get albumEnd;

  /// No description provided for @albumFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get albumFailureNetwork;

  /// User-facing album failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} album browsing is temporarily unavailable.'**
  String albumFailureService(Object provider);

  /// No description provided for @albumFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The album request was cancelled.'**
  String get albumFailureCancelled;

  /// No description provided for @catalogFailureCore.
  ///
  /// In en, this message translates to:
  /// **'The local music core is unavailable. Restart the app and try again.'**
  String get catalogFailureCore;

  /// User-facing album failure unexpected message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unexpected album response.'**
  String albumFailureUnexpected(Object provider);

  /// No description provided for @albumDetailsFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Album details are offline.'**
  String get albumDetailsFailureNetwork;

  /// No description provided for @albumDetailsFailureService.
  ///
  /// In en, this message translates to:
  /// **'Album details are temporarily unavailable.'**
  String get albumDetailsFailureService;

  /// No description provided for @albumDetailsFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'Album detail loading was cancelled.'**
  String get albumDetailsFailureCancelled;

  /// No description provided for @albumDetailsFailureCore.
  ///
  /// In en, this message translates to:
  /// **'Album details could not start.'**
  String get albumDetailsFailureCore;

  /// No description provided for @albumDetailsFailureGeneric.
  ///
  /// In en, this message translates to:
  /// **'Album details could not be read.'**
  String get albumDetailsFailureGeneric;

  /// No description provided for @artistType.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get artistType;

  /// No description provided for @artistTracksSection.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get artistTracksSection;

  /// No description provided for @artistAlbumsSection.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get artistAlbumsSection;

  /// No description provided for @artistLoadingTracks.
  ///
  /// In en, this message translates to:
  /// **'Loading artist tracks'**
  String get artistLoadingTracks;

  /// Empty state title when an artist has no available tracks.
  ///
  /// In en, this message translates to:
  /// **'This artist has no available tracks'**
  String get artistEmptyTracksTitle;

  /// Localized artist empty tracks detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an empty artist track list.'**
  String artistEmptyTracksDetail(Object provider);

  /// No description provided for @artistFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this artist'**
  String get artistFailureTitle;

  /// No description provided for @artistLoadingAlbums.
  ///
  /// In en, this message translates to:
  /// **'Loading artist albums'**
  String get artistLoadingAlbums;

  /// Empty state title when an artist has no available albums.
  ///
  /// In en, this message translates to:
  /// **'This artist has no available albums'**
  String get artistEmptyAlbumsTitle;

  /// Localized artist empty albums detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an empty artist album list.'**
  String artistEmptyAlbumsDetail(Object provider);

  /// No description provided for @artistAlbumsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this artist’s albums'**
  String get artistAlbumsFailureTitle;

  /// Localized artist count summary message.
  ///
  /// In en, this message translates to:
  /// **'{count} {type}'**
  String artistCountSummary(Object count, Object type);

  /// Pluralized artist track count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String artistTrackCount(num count);

  /// Pluralized artist album count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 album} other{{count} albums}}'**
  String artistAlbumCount(num count);

  /// Accessible artist album semantics message.
  ///
  /// In en, this message translates to:
  /// **'{title}, album'**
  String artistAlbumSemantics(Object title);

  /// No description provided for @artistEndAlbums.
  ///
  /// In en, this message translates to:
  /// **'End of artist albums'**
  String get artistEndAlbums;

  /// No description provided for @artistEndTracks.
  ///
  /// In en, this message translates to:
  /// **'End of artist tracks'**
  String get artistEndTracks;

  /// User-facing artist failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} artist browsing is temporarily unavailable.'**
  String artistFailureService(Object provider);

  /// No description provided for @artistFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The artist request was cancelled.'**
  String get artistFailureCancelled;

  /// User-facing artist failure unexpected message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unexpected artist response.'**
  String artistFailureUnexpected(Object provider);

  /// User-facing artist albums failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} artist-album browsing is temporarily unavailable.'**
  String artistAlbumsFailureService(Object provider);

  /// No description provided for @artistAlbumsFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The artist-album request was cancelled.'**
  String get artistAlbumsFailureCancelled;

  /// User-facing artist albums failure unexpected message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned an unexpected artist-album response.'**
  String artistAlbumsFailureUnexpected(Object provider);

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueTitle;

  /// Pluralized queue track count message.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 track} other{{count} tracks}}'**
  String queueTrackCount(num count);

  /// No description provided for @queueClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get queueClear;

  /// No description provided for @queueClose.
  ///
  /// In en, this message translates to:
  /// **'Close queue'**
  String get queueClose;

  /// Empty state for the playback queue.
  ///
  /// In en, this message translates to:
  /// **'The queue is empty. Choose a track from a playlist.'**
  String get queueEmpty;

  /// No description provided for @queueRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get queueRemove;

  /// Title of the destructive confirmation that removes all queued tracks and stops playback.
  ///
  /// In en, this message translates to:
  /// **'Clear queue?'**
  String get queueClearTitle;

  /// No description provided for @queueClearOneDetail.
  ///
  /// In en, this message translates to:
  /// **'This will remove the queued track and stop playback.'**
  String get queueClearOneDetail;

  /// Localized queue clear many detail message.
  ///
  /// In en, this message translates to:
  /// **'This will remove all {count} tracks and stop playback.'**
  String queueClearManyDetail(Object count);

  /// No description provided for @queueFailureInvalidTrack.
  ///
  /// In en, this message translates to:
  /// **'A queue entry could not be represented safely.'**
  String get queueFailureInvalidTrack;

  /// No description provided for @queueFailureInvalidPosition.
  ///
  /// In en, this message translates to:
  /// **'That queue position is no longer available.'**
  String get queueFailureInvalidPosition;

  /// No description provided for @queueFailureCore.
  ///
  /// In en, this message translates to:
  /// **'The music core could not update the queue.'**
  String get queueFailureCore;

  /// No description provided for @queueFailureInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The music core returned an invalid queue state.'**
  String get queueFailureInvalidResponse;

  /// Playback-quality menu label; keep MP3 and kbps as technical abbreviations.
  ///
  /// In en, this message translates to:
  /// **'Standard · MP3 128 kbps'**
  String get playbackQualityMenuStandard;

  /// Playback-quality menu label; keep HQ, MP3, and kbps as technical abbreviations.
  ///
  /// In en, this message translates to:
  /// **'HQ · MP3 320 kbps'**
  String get playbackQualityMenuHigh;

  /// Playback-quality menu label; keep SQ and FLAC as technical abbreviations.
  ///
  /// In en, this message translates to:
  /// **'SQ · FLAC lossless'**
  String get playbackQualityMenuLossless;

  /// Playback quality selected next message.
  ///
  /// In en, this message translates to:
  /// **'{quality} selected. It applies when the next track starts.'**
  String playbackQualitySelectedNext(Object quality);

  /// Playback quality playing message.
  ///
  /// In en, this message translates to:
  /// **'Playing {quality} quality.'**
  String playbackQualityPlaying(Object quality);

  /// Playback quality fallback message.
  ///
  /// In en, this message translates to:
  /// **'{preferred} is unavailable for this track. Playing {actual} instead.'**
  String playbackQualityFallback(Object actual, Object preferred);

  /// Playback quality tooltip preferred message.
  ///
  /// In en, this message translates to:
  /// **'Playback quality: {quality}'**
  String playbackQualityTooltipPreferred(Object quality);

  /// Playback quality tooltip current message.
  ///
  /// In en, this message translates to:
  /// **'Playback quality: {preferred}. Current source: {actual}{fallback}'**
  String playbackQualityTooltipCurrent(
    Object actual,
    Object fallback,
    Object preferred,
  );

  /// Short suffix appended inside the playback-quality accessibility tooltip when the actual source differs from the preference.
  ///
  /// In en, this message translates to:
  /// **' fallback'**
  String get playbackQualityFallbackSuffix;

  /// No description provided for @playbackActualLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get playbackActualLow;

  /// No description provided for @playbackSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get playbackSignIn;

  /// No description provided for @playbackOpenNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Open now playing'**
  String get playbackOpenNowPlaying;

  /// Playback open now playing for message.
  ///
  /// In en, this message translates to:
  /// **'Open now playing for {title}'**
  String playbackOpenNowPlayingFor(Object title);

  /// No description provided for @playbackPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get playbackPrevious;

  /// No description provided for @playbackNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get playbackNext;

  /// No description provided for @playbackStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get playbackStop;

  /// No description provided for @playbackPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get playbackPause;

  /// No description provided for @playbackResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get playbackResume;

  /// No description provided for @playbackRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get playbackRetry;

  /// No description provided for @playbackShuffleOn.
  ///
  /// In en, this message translates to:
  /// **'Shuffle on. Turn off shuffle'**
  String get playbackShuffleOn;

  /// No description provided for @playbackShuffleOff.
  ///
  /// In en, this message translates to:
  /// **'Shuffle off. Turn on shuffle'**
  String get playbackShuffleOff;

  /// No description provided for @playbackRepeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat off. Set repeat all'**
  String get playbackRepeatOff;

  /// No description provided for @playbackRepeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat all. Set repeat one'**
  String get playbackRepeatAll;

  /// No description provided for @playbackRepeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat one. Turn off repeat'**
  String get playbackRepeatOne;

  /// No description provided for @playbackBrowseCurrentTrack.
  ///
  /// In en, this message translates to:
  /// **'Browse current track'**
  String get playbackBrowseCurrentTrack;

  /// Playback open credited artist message.
  ///
  /// In en, this message translates to:
  /// **'Open credited artist for {title}'**
  String playbackOpenCreditedArtist(Object title);

  /// Playback open album message.
  ///
  /// In en, this message translates to:
  /// **'Open album for {title}'**
  String playbackOpenAlbum(Object title);

  /// Playback browse album artists message.
  ///
  /// In en, this message translates to:
  /// **'Browse album and credited artists for {title}'**
  String playbackBrowseAlbumArtists(Object title);

  /// Playback choose credited artist message.
  ///
  /// In en, this message translates to:
  /// **'Choose a credited artist for {title}'**
  String playbackChooseCreditedArtist(Object title);

  /// Accessible playback progress semantics message.
  ///
  /// In en, this message translates to:
  /// **'{position} of {duration}'**
  String playbackProgressSemantics(Object duration, Object position);

  /// Accessible playback track status semantics message.
  ///
  /// In en, this message translates to:
  /// **'{artist} · {status}'**
  String playbackTrackStatusSemantics(Object artist, Object status);

  /// No description provided for @playbackShowQueue.
  ///
  /// In en, this message translates to:
  /// **'Show queue'**
  String get playbackShowQueue;

  /// No description provided for @playbackVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get playbackVolume;

  /// Playback volume percent message.
  ///
  /// In en, this message translates to:
  /// **'{percent} percent'**
  String playbackVolumePercent(Object percent);

  /// No description provided for @playbackShowLyrics.
  ///
  /// In en, this message translates to:
  /// **'Show lyrics'**
  String get playbackShowLyrics;

  /// Accessible playback artwork semantics message.
  ///
  /// In en, this message translates to:
  /// **'Artwork for {title}'**
  String playbackArtworkSemantics(Object title);

  /// No description provided for @playbackReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to play'**
  String get playbackReady;

  /// No description provided for @playbackFindingSource.
  ///
  /// In en, this message translates to:
  /// **'Finding a playable source…'**
  String get playbackFindingSource;

  /// No description provided for @playbackLoadingAudio.
  ///
  /// In en, this message translates to:
  /// **'Loading audio…'**
  String get playbackLoadingAudio;

  /// No description provided for @playbackPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get playbackPlaying;

  /// No description provided for @playbackPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get playbackPaused;

  /// No description provided for @playbackStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get playbackStopped;

  /// No description provided for @playbackFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get playbackFinished;

  /// No description provided for @playbackEngineFailure.
  ///
  /// In en, this message translates to:
  /// **'Playback failed. Try this track again.'**
  String get playbackEngineFailure;

  /// No description provided for @playbackQueueInvalidTrack.
  ///
  /// In en, this message translates to:
  /// **'A queue track was invalid.'**
  String get playbackQueueInvalidTrack;

  /// No description provided for @playbackAuthRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to try account-authorized playback.'**
  String get playbackAuthRequired;

  /// User-facing playback credential rejected message.
  ///
  /// In en, this message translates to:
  /// **'Your {provider} session was rejected and removed.'**
  String playbackCredentialRejected(Object provider);

  /// No description provided for @playbackCredentialCleanupFailure.
  ///
  /// In en, this message translates to:
  /// **'Your session was rejected, but secure storage could not remove it.'**
  String get playbackCredentialCleanupFailure;

  /// Playback source unavailable message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not provide a playable source.'**
  String playbackSourceUnavailable(Object provider);

  /// User-facing playback network failure message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach {provider}. Try again.'**
  String playbackNetworkFailure(Object provider);

  /// Playback service unavailable message.
  ///
  /// In en, this message translates to:
  /// **'{provider} playback is unavailable right now.'**
  String playbackServiceUnavailable(Object provider);

  /// Playback invalid response message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned a source this build could not safely play.'**
  String playbackInvalidResponse(Object provider);

  /// No description provided for @playbackCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The music core could not resolve this track.'**
  String get playbackCoreUnavailable;

  /// No description provided for @playbackRequestRunning.
  ///
  /// In en, this message translates to:
  /// **'Another media request is still running.'**
  String get playbackRequestRunning;

  /// No description provided for @playbackResolutionFailure.
  ///
  /// In en, this message translates to:
  /// **'This track could not be resolved.'**
  String get playbackResolutionFailure;

  /// No description provided for @nowPlayingTitle.
  ///
  /// In en, this message translates to:
  /// **'Now Playing'**
  String get nowPlayingTitle;

  /// No description provided for @nowPlayingBack.
  ///
  /// In en, this message translates to:
  /// **'Back to previous page'**
  String get nowPlayingBack;

  /// No description provided for @nowPlayingOpenMusicVideo.
  ///
  /// In en, this message translates to:
  /// **'Open music video'**
  String get nowPlayingOpenMusicVideo;

  /// No description provided for @nowPlayingOpenComments.
  ///
  /// In en, this message translates to:
  /// **'Open comments'**
  String get nowPlayingOpenComments;

  /// No description provided for @nowPlayingComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get nowPlayingComments;

  /// Empty state title for the expanded Now Playing page.
  ///
  /// In en, this message translates to:
  /// **'Nothing is playing'**
  String get nowPlayingEmptyTitle;

  /// Supporting copy for the expanded Now Playing empty state.
  ///
  /// In en, this message translates to:
  /// **'Choose a track from your library, Search, or Discover.'**
  String get nowPlayingEmptyDetail;

  /// No description provided for @nowPlayingBackToMusic.
  ///
  /// In en, this message translates to:
  /// **'Back to music'**
  String get nowPlayingBackToMusic;

  /// No description provided for @nowPlayingLyricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Lyrics are unavailable in this playback session.'**
  String get nowPlayingLyricsUnavailable;

  /// No description provided for @lyricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyricsTitle;

  /// No description provided for @lyricsClose.
  ///
  /// In en, this message translates to:
  /// **'Close lyrics'**
  String get lyricsClose;

  /// No description provided for @lyricsIdleTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a track to see its lyrics'**
  String get lyricsIdleTitle;

  /// No description provided for @lyricsIdleDetail.
  ///
  /// In en, this message translates to:
  /// **'Synchronized lyrics will follow the current queue track.'**
  String get lyricsIdleDetail;

  /// No description provided for @lyricsUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'No synchronized lyrics'**
  String get lyricsUnavailableTitle;

  /// Localized lyrics unavailable detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not provide lyrics for this track.'**
  String lyricsUnavailableDetail(Object provider);

  /// No description provided for @lyricsSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to load lyrics'**
  String get lyricsSignInTitle;

  /// Localized lyrics sign in detail message.
  ///
  /// In en, this message translates to:
  /// **'Your current session cannot request {provider} lyrics.'**
  String lyricsSignInDetail(Object provider);

  /// User-facing lyrics session rejected title message.
  ///
  /// In en, this message translates to:
  /// **'{provider} session rejected'**
  String lyricsSessionRejectedTitle(Object provider);

  /// No description provided for @lyricsSessionRejectedDetail.
  ///
  /// In en, this message translates to:
  /// **'Sign in again before requesting lyrics.'**
  String get lyricsSessionRejectedDetail;

  /// No description provided for @lyricsFollowCurrent.
  ///
  /// In en, this message translates to:
  /// **'Follow current line'**
  String get lyricsFollowCurrent;

  /// Localized lyrics segment progress message.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String lyricsSegmentProgress(Object percent);

  /// No description provided for @lyricsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading synchronized lyrics…'**
  String get lyricsLoading;

  /// Accessible lyrics announcement message.
  ///
  /// In en, this message translates to:
  /// **'{title}. {detail}'**
  String lyricsAnnouncement(Object detail, Object title);

  /// User-facing lyrics failure network title message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach {provider}'**
  String lyricsFailureNetworkTitle(Object provider);

  /// No description provided for @lyricsFailureServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics are unavailable right now'**
  String get lyricsFailureServiceTitle;

  /// No description provided for @lyricsFailureRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Another lyric request is still running'**
  String get lyricsFailureRunningTitle;

  /// No description provided for @lyricsFailureGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load synchronized lyrics'**
  String get lyricsFailureGenericTitle;

  /// No description provided for @lyricsFailureNetworkDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session is unchanged. Check your connection and try again.'**
  String get lyricsFailureNetworkDetail;

  /// No description provided for @lyricsFailureServiceDetail.
  ///
  /// In en, this message translates to:
  /// **'Your session is unchanged. Try requesting this track again later.'**
  String get lyricsFailureServiceDetail;

  /// No description provided for @lyricsFailureRunningDetail.
  ///
  /// In en, this message translates to:
  /// **'Wait for the current request to finish before trying again.'**
  String get lyricsFailureRunningDetail;

  /// No description provided for @lyricsFailureReplacedDetail.
  ///
  /// In en, this message translates to:
  /// **'The lyric request was replaced before it completed.'**
  String get lyricsFailureReplacedDetail;

  /// User-facing lyrics failure invalid detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned lyrics this build could not safely present.'**
  String lyricsFailureInvalidDetail(Object provider);

  /// No description provided for @commentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commentsTitle;

  /// No description provided for @commentsClose.
  ///
  /// In en, this message translates to:
  /// **'Close comments'**
  String get commentsClose;

  /// No description provided for @commentsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading comments'**
  String get commentsLoading;

  /// Empty state title for a successful response with no track comments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get commentsEmptyTitle;

  /// Localized comments empty detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not return comments for this track.'**
  String commentsEmptyDetail(Object provider);

  /// No description provided for @commentsFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load comments'**
  String get commentsFailureTitle;

  /// No description provided for @commentsHot.
  ///
  /// In en, this message translates to:
  /// **'Hot comments'**
  String get commentsHot;

  /// No description provided for @commentsNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get commentsNewest;

  /// User-facing comments load more failure message.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load more comments. {detail}'**
  String commentsLoadMoreFailure(Object detail);

  /// No description provided for @commentsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get commentsLoadMore;

  /// No description provided for @commentsFailureNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get commentsFailureNetwork;

  /// User-facing comments failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} comments are temporarily unavailable.'**
  String commentsFailureService(Object provider);

  /// User-facing comments failure invalid message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned comment data this version cannot read.'**
  String commentsFailureInvalid(Object provider);

  /// No description provided for @commentsFailureCore.
  ///
  /// In en, this message translates to:
  /// **'The native comment service is unavailable in this build.'**
  String get commentsFailureCore;

  /// No description provided for @commentsFailureRunning.
  ///
  /// In en, this message translates to:
  /// **'Another comment request is still finishing. Try again.'**
  String get commentsFailureRunning;

  /// No description provided for @commentsFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The comment request was cancelled.'**
  String get commentsFailureCancelled;

  /// No description provided for @musicVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Music video'**
  String get musicVideoTitle;

  /// No description provided for @musicVideoClose.
  ///
  /// In en, this message translates to:
  /// **'Close music video'**
  String get musicVideoClose;

  /// No description provided for @musicVideoLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading music video'**
  String get musicVideoLoading;

  /// Empty state title when the current track has no music video.
  ///
  /// In en, this message translates to:
  /// **'No music video for this track'**
  String get musicVideoEmptyTitle;

  /// Localized music video empty detail message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not associate an MV with this track.'**
  String musicVideoEmptyDetail(Object provider);

  /// No description provided for @musicVideoUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Music video unavailable'**
  String get musicVideoUnavailableTitle;

  /// No description provided for @musicVideoFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t play music video'**
  String get musicVideoFailureTitle;

  /// No description provided for @musicVideoStoppedTitle.
  ///
  /// In en, this message translates to:
  /// **'Music video stopped'**
  String get musicVideoStoppedTitle;

  /// No description provided for @musicVideoStoppedDetail.
  ///
  /// In en, this message translates to:
  /// **'Music playback or the current queue track changed.'**
  String get musicVideoStoppedDetail;

  /// Screen-reader group label for music-video transport controls.
  ///
  /// In en, this message translates to:
  /// **'Music video playback controls'**
  String get musicVideoControlsSemantics;

  /// No description provided for @musicVideoPause.
  ///
  /// In en, this message translates to:
  /// **'Pause music video'**
  String get musicVideoPause;

  /// No description provided for @musicVideoPlay.
  ///
  /// In en, this message translates to:
  /// **'Play music video'**
  String get musicVideoPlay;

  /// User-facing music video failure source message.
  ///
  /// In en, this message translates to:
  /// **'{provider} did not provide a supported playable MV source.'**
  String musicVideoFailureSource(Object provider);

  /// User-facing music video failure network message.
  ///
  /// In en, this message translates to:
  /// **'The MV request could not reach {provider}. Check your connection.'**
  String musicVideoFailureNetwork(Object provider);

  /// User-facing music video failure service message.
  ///
  /// In en, this message translates to:
  /// **'{provider} could not serve this MV right now.'**
  String musicVideoFailureService(Object provider);

  /// User-facing music video failure invalid message.
  ///
  /// In en, this message translates to:
  /// **'{provider} returned MV data the app could not safely use.'**
  String musicVideoFailureInvalid(Object provider);

  /// No description provided for @musicVideoFailureCancelled.
  ///
  /// In en, this message translates to:
  /// **'The MV request was cancelled.'**
  String get musicVideoFailureCancelled;

  /// No description provided for @musicVideoFailureRunning.
  ///
  /// In en, this message translates to:
  /// **'Another MV request is already running. Try again shortly.'**
  String get musicVideoFailureRunning;

  /// No description provided for @musicVideoFailureCore.
  ///
  /// In en, this message translates to:
  /// **'The MV player could not start this video.'**
  String get musicVideoFailureCore;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchLabel;

  /// Tooltip and accessibility name for leaving a Settings detail page.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBackTooltip;

  /// Tooltip and accessibility name for returning from compact Settings search.
  ///
  /// In en, this message translates to:
  /// **'Back to settings'**
  String get settingsBackToSettingsTooltip;

  /// No description provided for @settingsSearchResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get settingsSearchResultsTitle;

  /// Shown when Settings search has no matching category.
  ///
  /// In en, this message translates to:
  /// **'No settings match ‘{query}’.'**
  String settingsSearchNoMatch(String query);

  /// Summary of the number of matching Settings categories.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section matches ‘{query}’.} other{{count} sections match ‘{query}’.}}'**
  String settingsSearchMatchSummary(int count, String query);

  /// No description provided for @settingsSaveFailure.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save settings on this device.'**
  String get settingsSaveFailure;

  /// No description provided for @settingsChooseCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose a settings category'**
  String get settingsChooseCategory;

  /// Accessible summary for a Settings category row.
  ///
  /// In en, this message translates to:
  /// **'{label}. {description}. {summary}'**
  String settingsCategorySemantics(
    String label,
    String description,
    String summary,
  );

  /// No description provided for @settingsAppearanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceLabel;

  /// No description provided for @settingsAppearanceCompactLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get settingsAppearanceCompactLabel;

  /// No description provided for @settingsAppearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Theme mode and color palette'**
  String get settingsAppearanceDescription;

  /// No description provided for @settingsAppearanceBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the brightness and color palette used by fura music.'**
  String get settingsAppearanceBody;

  /// No description provided for @settingsAppearanceSummarySystem.
  ///
  /// In en, this message translates to:
  /// **'Following the system theme'**
  String get settingsAppearanceSummarySystem;

  /// No description provided for @settingsAppearanceSummaryLight.
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get settingsAppearanceSummaryLight;

  /// No description provided for @settingsAppearanceSummaryDark.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get settingsAppearanceSummaryDark;

  /// Pipe-delimited localized search aliases for Appearance settings; preserve the pipe separator.
  ///
  /// In en, this message translates to:
  /// **'appearance|theme|system|light|dark|color|palette|Monet|wallpaper|accent|brand'**
  String get settingsAppearanceSearchKeywords;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsColorSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Color palette'**
  String get settingsColorSourceLabel;

  /// No description provided for @settingsColorSourceBody.
  ///
  /// In en, this message translates to:
  /// **'Choose where the Material 3 palette comes from.'**
  String get settingsColorSourceBody;

  /// No description provided for @settingsColorSourceSystem.
  ///
  /// In en, this message translates to:
  /// **'System colors (Monet)'**
  String get settingsColorSourceSystem;

  /// No description provided for @settingsColorSourceSystemDescription.
  ///
  /// In en, this message translates to:
  /// **'Use wallpaper or OS accent colors where supported. The current music service palette is used as a fallback.'**
  String get settingsColorSourceSystemDescription;

  /// No description provided for @settingsColorSourceSystemSummary.
  ///
  /// In en, this message translates to:
  /// **'System colors'**
  String get settingsColorSourceSystemSummary;

  /// No description provided for @settingsColorSourceBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand impression'**
  String get settingsColorSourceBrand;

  /// Appearance setting description for the provider-aware brand impression palette.
  ///
  /// In en, this message translates to:
  /// **'Use colors inspired by {provider}, kept consistent across devices.'**
  String settingsColorSourceBrandDescription(String provider);

  /// No description provided for @settingsColorSourceBrandSummary.
  ///
  /// In en, this message translates to:
  /// **'Brand impression colors'**
  String get settingsColorSourceBrandSummary;

  /// No description provided for @settingsMusicServiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Music service'**
  String get settingsMusicServiceLabel;

  /// No description provided for @settingsMusicServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Catalog and account source'**
  String get settingsMusicServiceDescription;

  /// No description provided for @settingsMusicServiceBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the service used for browsing, search, recommendations, and your account library.'**
  String get settingsMusicServiceBody;

  /// Pipe-delimited localized search aliases for music-provider settings; preserve the pipe separator.
  ///
  /// In en, this message translates to:
  /// **'provider|music service|source|QQ Music|NetEase Cloud Music'**
  String get settingsMusicServiceSearchKeywords;

  /// Localized product-facing name for the QQ Music provider; never use it as a provider identifier.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get providerQqMusic;

  /// Localized product-facing name for the NetEase Cloud Music provider; never use it as a provider identifier.
  ///
  /// In en, this message translates to:
  /// **'NetEase Cloud Music'**
  String get providerNeteaseCloudMusic;

  /// Fallback product-facing label for a music provider whose display name is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Music service'**
  String get providerGenericMusicService;

  /// Settings description for selecting QQ Music without changing its stable provider identity.
  ///
  /// In en, this message translates to:
  /// **'First-class service and default'**
  String get providerQqMusicSettingsDescription;

  /// Settings description for selecting NetEase Cloud Music without changing its stable provider identity.
  ///
  /// In en, this message translates to:
  /// **'Built-in service with capability-aware features'**
  String get providerNeteaseSettingsDescription;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Display language and system preference'**
  String get settingsLanguageDescription;

  /// No description provided for @settingsLanguageBody.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used by fura music. Provider content such as song and playlist names is not translated.'**
  String get settingsLanguageBody;

  /// Pipe-delimited localized search aliases for Language settings; preserve the pipe separator.
  ///
  /// In en, this message translates to:
  /// **'language|locale|system|English|Simplified Chinese|Chinese'**
  String get settingsLanguageSearchKeywords;

  /// No description provided for @settingsLanguageFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsLanguageFollowSystem;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get settingsLanguageSimplifiedChinese;

  /// No description provided for @settingsLanguageSummarySystem.
  ///
  /// In en, this message translates to:
  /// **'Following the system language'**
  String get settingsLanguageSummarySystem;

  /// No description provided for @settingsLanguageSummaryEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageSummaryEnglish;

  /// No description provided for @settingsLanguageSummarySimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get settingsLanguageSummarySimplifiedChinese;

  /// No description provided for @settingsPlaybackLabel.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get settingsPlaybackLabel;

  /// No description provided for @settingsPlaybackCompactLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get settingsPlaybackCompactLabel;

  /// No description provided for @settingsPlaybackSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Playback quality'**
  String get settingsPlaybackSectionLabel;

  /// No description provided for @settingsPlaybackDescription.
  ///
  /// In en, this message translates to:
  /// **'Preferred streaming quality'**
  String get settingsPlaybackDescription;

  /// No description provided for @settingsPlaybackBody.
  ///
  /// In en, this message translates to:
  /// **'Preferred quality when supported by the current music service. The player always reports the actual quality used.'**
  String get settingsPlaybackBody;

  /// Pipe-delimited localized search aliases for playback-quality settings; preserve the pipe separator and technical abbreviations.
  ///
  /// In en, this message translates to:
  /// **'playback|quality|audio|standard|high|music source|HQ|SQ'**
  String get settingsPlaybackSearchKeywords;

  /// User-facing name for the standard playback-quality preference.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get playbackQualityStandard;

  /// User-facing name for the high-quality preference; the HQ abbreviation is intentionally stable.
  ///
  /// In en, this message translates to:
  /// **'HQ'**
  String get playbackQualityHigh;

  /// User-facing name for the lossless preference; the SQ abbreviation is intentionally stable.
  ///
  /// In en, this message translates to:
  /// **'SQ'**
  String get playbackQualityLossless;

  /// Settings summary for the standard playback-quality preference.
  ///
  /// In en, this message translates to:
  /// **'Standard quality'**
  String get playbackQualitySummaryStandard;

  /// Settings summary for the high-quality playback preference.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get playbackQualitySummaryHigh;

  /// Settings summary for the lossless playback preference.
  ///
  /// In en, this message translates to:
  /// **'SQ lossless quality'**
  String get playbackQualitySummaryLossless;

  /// Tooltip for returning a scrolled music list to its currently playing row.
  ///
  /// In en, this message translates to:
  /// **'Locate current track'**
  String get commonLocateCurrentTrack;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
