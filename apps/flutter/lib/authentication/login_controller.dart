import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_external_login.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';

typedef ExternalLoginUriLauncher = Future<bool> Function(Uri uri);

enum LoginStage {
  idle,
  verificationRequired,
  verifyingStoredCredential,
  credentialRejected,
  verificationError,
  signOutStorageCleanupFailed,
  storedCredentialExpired,
  restoreError,
  starting,
  officialWebLogin,
  officialWebError,
  waitingForScan,
  scannedAwaitingConfirmation,
  reconnecting,
  authenticated,
  expired,
  refused,
  timedOut,
  error,
  signOutBrowserCleanupFailed,
}

enum CredentialSaveState { none, saving, saved, failed }

enum DesktopQuickLoginStage {
  disabled,
  idle,
  loading,
  ready,
  noAccounts,
  authorizing,
  error,
}

enum SmsLoginStage {
  hidden,
  ready,
  sendingCode,
  codeSent,
  authenticating,
  error,
}

class LoginController extends ChangeNotifier {
  LoginController(
    this._gateway, {
    this._networkRetryDelay = const Duration(seconds: 1),
    Future<void> Function(Duration)? delay,
    ExternalLoginUriLauncher? externalLoginUriLauncher,
    this.desktopQuickLoginEnabled = false,
    CredentialRestoreResult initialCredentialRestore =
        CredentialRestoreResult.signedOut,
  }) : _delay = delay ?? _defaultDelay,
       _externalLoginUriLauncher =
           externalLoginUriLauncher ?? openNeteaseQrConfirmationExternally,
       _credentialRestoreResult = initialCredentialRestore {
    if (_gateway.hasAuthenticatedCredential) {
      _stage = LoginStage.authenticated;
      return;
    }
    _stage = switch (initialCredentialRestore) {
      CredentialRestoreResult.signedOut => LoginStage.idle,
      CredentialRestoreResult.verificationRequired =>
        LoginStage.verificationRequired,
      CredentialRestoreResult.locallyExpired =>
        LoginStage.storedCredentialExpired,
      CredentialRestoreResult.invalidStoredCredential ||
      CredentialRestoreResult.unsupportedStoredCredential ||
      CredentialRestoreResult.storageUnavailable ||
      CredentialRestoreResult.coreUnavailable => LoginStage.restoreError,
    };
  }

  final QqMusicAuthenticationGateway _gateway;
  final Duration _networkRetryDelay;
  final Future<void> Function(Duration) _delay;
  final ExternalLoginUriLauncher _externalLoginUriLauncher;
  final bool desktopQuickLoginEnabled;
  final Set<int> _pollingGenerations = <int>{};

  LoginStage _stage = LoginStage.idle;
  LoginSession? _session;
  LoginStartOperation? _startOperation;
  CredentialVerificationOperation? _verificationOperation;
  DesktopQuickLoginStartOperation? _desktopQuickStartOperation;
  DesktopQuickLoginSession? _desktopQuickSession;
  SmsCodeRequestOperation? _smsCodeRequestOperation;
  SmsLoginOperation? _smsLoginOperation;
  OfficialWebAuthenticationOperation? _officialWebOperation;
  Uint8List? _qrImageBytes;
  Uri? _qrExternalConfirmationUri;
  bool _openingQrExternally = false;
  bool _externalQrLaunchFailed = false;
  LoginFailure? _failure;
  LoginQrChannel _qrChannel = LoginQrChannel.qq;
  CredentialSaveState _credentialSaveState = CredentialSaveState.none;
  CredentialRestoreResult _credentialRestoreResult;
  CredentialVerificationResult? _credentialVerificationResult;
  Future<CredentialSignOutResult>? _signOutOperation;
  List<DesktopQuickLoginAccount> _desktopQuickAccounts = const [];
  DesktopQuickLoginFailure? _desktopQuickFailure;
  DesktopQuickLoginStage _desktopQuickStage = DesktopQuickLoginStage.idle;
  SmsLoginStage _smsStage = SmsLoginStage.hidden;
  SmsAuthenticationFailure? _smsFailure;
  OfficialWebAuthenticationFailure? _officialWebFailure;
  bool _smsCodeRequested = false;
  int? _desktopQuickSelectionId;
  int _generation = 0;
  int _desktopQuickGeneration = 0;
  bool _disposed = false;

  LoginStage get stage => _stage;
  Uint8List? get qrImageBytes => _qrImageBytes;
  bool get canOpenQrExternally =>
      _qrExternalConfirmationUri != null &&
      (_session?.isActive ?? false) &&
      !_openingQrExternally;
  bool get openingQrExternally => _openingQrExternally;
  bool get externalQrLaunchFailed => _externalQrLaunchFailed;
  LoginFailure? get failure => _failure;
  LoginQrChannel get qrChannel => _qrChannel;
  CredentialSaveState get credentialSaveState => _credentialSaveState;
  CredentialRestoreResult get credentialRestoreResult =>
      _credentialRestoreResult;
  CredentialVerificationResult? get credentialVerificationResult =>
      _credentialVerificationResult;
  List<DesktopQuickLoginAccount> get desktopQuickAccounts =>
      _desktopQuickAccounts;
  DesktopQuickLoginFailure? get desktopQuickFailure => _desktopQuickFailure;
  DesktopQuickLoginStage get desktopQuickStage => supportsDesktopQuickLogin
      ? _desktopQuickStage
      : DesktopQuickLoginStage.disabled;
  SmsLoginStage get smsStage =>
      supportsSmsLogin ? _smsStage : SmsLoginStage.hidden;
  SmsAuthenticationFailure? get smsFailure => _smsFailure;
  OfficialWebAuthenticationFailure? get officialWebFailure =>
      _officialWebFailure;
  Listenable? get officialWebPresentationListenable =>
      _gateway is OfficialWebAuthenticationPresentation
      ? (_gateway as OfficialWebAuthenticationPresentation)
            .officialWebPresentationListenable
      : null;
  OfficialWebLoginPresentationStage get officialWebPresentationStage =>
      _gateway is OfficialWebAuthenticationPresentation
      ? (_gateway as OfficialWebAuthenticationPresentation)
            .officialWebPresentationStage
      : OfficialWebLoginPresentationStage.idle;
  Widget? get officialWebLoginView =>
      _gateway is OfficialWebAuthenticationPresentation
      ? (_gateway as OfficialWebAuthenticationPresentation).officialWebLoginView
      : null;
  bool get smsCodeRequested => _smsCodeRequested;
  bool get supportsSmsLogin => _gateway is SmsAuthenticationGateway;
  bool get supportsOfficialWebLogin =>
      _gateway is OfficialWebAuthenticationGateway &&
      (_gateway as OfficialWebAuthenticationGateway).supportsOfficialWebLogin;
  bool get showingSmsLogin =>
      supportsSmsLogin && _smsStage != SmsLoginStage.hidden;
  int? get desktopQuickSelectionId => _desktopQuickSelectionId;
  String get providerId => (_gateway is ProviderAuthenticationPresentation)
      ? (_gateway as ProviderAuthenticationPresentation).providerId
      : 'qq-music';
  bool get supportsMultipleQrMethods =>
      _gateway is MultiMethodQqMusicAuthenticationGateway ||
      _gateway is! ProviderAuthenticationPresentation;
  bool get canAuthorizeDesktopQuickAccount =>
      _desktopQuickSession?.isActive ?? false;

  bool get supportsDesktopQuickLogin =>
      desktopQuickLoginEnabled &&
      _gateway is DesktopQuickQqMusicAuthenticationGateway;
  bool get canCancel =>
      _stage == LoginStage.starting ||
      _stage == LoginStage.officialWebLogin ||
      (_session?.isActive ?? false);

  bool get canRetry =>
      _stage == LoginStage.error && (_session?.isActive ?? false);

  bool get canRetryCredentialVerification =>
      _stage == LoginStage.verificationError &&
      (_credentialVerificationResult == CredentialVerificationResult.network ||
          _credentialVerificationResult ==
              CredentialVerificationResult.serviceUnavailable ||
          _credentialVerificationResult ==
              CredentialVerificationResult.invalidResponse);

  bool get canRetryOfficialWebVerification =>
      _stage == LoginStage.officialWebError &&
      (_officialWebFailure == OfficialWebAuthenticationFailure.network ||
          _officialWebFailure ==
              OfficialWebAuthenticationFailure.serviceUnavailable ||
          _officialWebFailure ==
              OfficialWebAuthenticationFailure.invalidResponse);

  bool get isSigningOut => _signOutOperation != null;

  bool get canRetrySignOut =>
      (_stage == LoginStage.signOutStorageCleanupFailed ||
          _stage == LoginStage.signOutBrowserCleanupFailed) &&
      !isSigningOut;

  /// Restores only the provider that has just become the active UI context.
  ///
  /// Inactive provider vaults are deliberately not probed at startup. A
  /// generation change makes a late restore or verification result harmless
  /// when the user switches provider again.
  Future<void> restoreCredential() async {
    if (_disposed) return;
    if (_gateway.hasAuthenticatedCredential) {
      _credentialRestoreResult = CredentialRestoreResult.verificationRequired;
      _stage = LoginStage.authenticated;
      _notify();
      return;
    }

    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearOfficialWebLogin();
    _clearSmsAuthentication();
    _clearDesktopQuickLogin();
    _clearQrChallenge();
    _failure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialVerificationResult = null;

    CredentialRestoreResult result;
    try {
      result = await _gateway.restoreCredential();
    } on Object {
      result = CredentialRestoreResult.coreUnavailable;
    }
    if (!_isCurrent(generation)) return;

    _credentialRestoreResult = result;
    _stage = switch (result) {
      CredentialRestoreResult.signedOut => LoginStage.idle,
      CredentialRestoreResult.verificationRequired =>
        LoginStage.verificationRequired,
      CredentialRestoreResult.locallyExpired =>
        LoginStage.storedCredentialExpired,
      CredentialRestoreResult.invalidStoredCredential ||
      CredentialRestoreResult.unsupportedStoredCredential ||
      CredentialRestoreResult.storageUnavailable ||
      CredentialRestoreResult.coreUnavailable => LoginStage.restoreError,
    };
    _notify();
    if (result == CredentialRestoreResult.verificationRequired) {
      await verifyRestoredCredential();
    }
  }

  Future<CredentialSignOutResult> signOut() {
    final activeOperation = _signOutOperation;
    if (activeOperation != null) return activeOperation;

    final previousStage = _stage;
    if (previousStage != LoginStage.authenticated &&
        previousStage != LoginStage.signOutStorageCleanupFailed &&
        previousStage != LoginStage.signOutBrowserCleanupFailed) {
      return Future.value(CredentialSignOutResult.coreUnavailable);
    }

    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _clearDesktopQuickLogin();
    _clearSmsAuthentication();
    _clearOfficialWebLogin();
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    final completer = Completer<CredentialSignOutResult>();
    final operation = completer.future;
    _signOutOperation = operation;
    _notify();
    unawaited(_finishSignOut(operation, completer, generation, previousStage));
    return operation;
  }

  Future<void> _finishSignOut(
    Future<CredentialSignOutResult> operation,
    Completer<CredentialSignOutResult> completer,
    int generation,
    LoginStage previousStage,
  ) async {
    CredentialSignOutResult result;
    try {
      result = await _gateway.signOut();
    } on Object {
      result = CredentialSignOutResult.coreUnavailable;
    }

    if (_isCurrent(generation)) {
      if (result == CredentialSignOutResult.coreUnavailable) {
        _stage = previousStage;
      } else {
        _clearQrChallenge();
        _failure = null;
        _credentialSaveState = CredentialSaveState.none;
        _credentialRestoreResult = CredentialRestoreResult.signedOut;
        _credentialVerificationResult = null;
        _stage = switch (result) {
          CredentialSignOutResult.signedOut => LoginStage.idle,
          CredentialSignOutResult.storageCleanupFailed =>
            LoginStage.signOutStorageCleanupFailed,
          CredentialSignOutResult.browserCleanupFailed =>
            LoginStage.signOutBrowserCleanupFailed,
          CredentialSignOutResult.coreUnavailable => previousStage,
        };
      }
    }

    if (identical(_signOutOperation, operation)) {
      _signOutOperation = null;
    }
    _notify();
    completer.complete(result);
  }

  Future<void> verifyRestoredCredential() async {
    if (_stage != LoginStage.verificationRequired &&
        _stage != LoginStage.verificationError) {
      return;
    }
    final generation = ++_generation;
    _verificationOperation?.cancel();
    final operation = _gateway.beginCredentialVerification();
    _verificationOperation = operation;
    _credentialVerificationResult = null;
    _stage = LoginStage.verifyingStoredCredential;
    _notify();

    final result = await operation.run();
    if (identical(_verificationOperation, operation)) {
      _verificationOperation = null;
    }
    if (!_isCurrent(generation)) return;

    _credentialVerificationResult = result;
    _stage = switch (result) {
      CredentialVerificationResult.authenticated => LoginStage.authenticated,
      CredentialVerificationResult.rejected ||
      CredentialVerificationResult.rejectedStorageCleanupFailed =>
        LoginStage.credentialRejected,
      CredentialVerificationResult.network ||
      CredentialVerificationResult.serviceUnavailable ||
      CredentialVerificationResult.invalidResponse ||
      CredentialVerificationResult.coreUnavailable =>
        LoginStage.verificationError,
      CredentialVerificationResult.noRestoredCredential ||
      CredentialVerificationResult.replaced => LoginStage.idle,
    };
    if (result == CredentialVerificationResult.authenticated) {
      _credentialSaveState = CredentialSaveState.saved;
    }
    if (result == CredentialVerificationResult.noRestoredCredential ||
        result == CredentialVerificationResult.replaced) {
      _credentialRestoreResult = CredentialRestoreResult.signedOut;
    }
    _notify();
  }

  void retryCredentialVerification() {
    if (!canRetryCredentialVerification) return;
    unawaited(verifyRestoredCredential());
  }

  Future<void> loadDesktopQuickAccounts() async {
    if (!supportsDesktopQuickLogin ||
        _desktopQuickStage == DesktopQuickLoginStage.loading ||
        _desktopQuickStage == DesktopQuickLoginStage.authorizing) {
      return;
    }
    final generation = ++_desktopQuickGeneration;
    _desktopQuickStartOperation?.cancel();
    _desktopQuickSession?.cancel();
    _desktopQuickSession = null;
    _desktopQuickAccounts = const [];
    _desktopQuickFailure = null;
    _desktopQuickSelectionId = null;
    _desktopQuickStage = DesktopQuickLoginStage.loading;
    _notify();

    final operation = (_gateway as DesktopQuickQqMusicAuthenticationGateway)
        .beginDesktopQuickLoginStart();
    _desktopQuickStartOperation = operation;
    final result = await operation.run();
    if (identical(_desktopQuickStartOperation, operation)) {
      _desktopQuickStartOperation = null;
    }
    if (!_isCurrentDesktopQuick(generation)) {
      result.session?.cancel();
      return;
    }

    final failure = result.failure;
    final session = result.session;
    if (failure != null) {
      session?.cancel();
      _desktopQuickFailure = failure;
      _desktopQuickStage = DesktopQuickLoginStage.error;
    } else if (session == null || result.accounts.isEmpty) {
      session?.cancel();
      _desktopQuickStage = DesktopQuickLoginStage.noAccounts;
    } else {
      _desktopQuickSession = session;
      _desktopQuickAccounts = List.unmodifiable(result.accounts);
      _desktopQuickStage = DesktopQuickLoginStage.ready;
    }
    _notify();
  }

  Future<void> authorizeDesktopQuickAccount(int selectionId) async {
    final session = _desktopQuickSession;
    if (!supportsDesktopQuickLogin ||
        session == null ||
        !session.isActive ||
        _desktopQuickStage == DesktopQuickLoginStage.authorizing ||
        !_desktopQuickAccounts.any(
          (account) => account.selectionId == selectionId,
        )) {
      return;
    }
    final generation = ++_desktopQuickGeneration;
    _desktopQuickSelectionId = selectionId;
    _desktopQuickFailure = null;
    _desktopQuickStage = DesktopQuickLoginStage.authorizing;
    _notify();

    final update = await session.authorize(selectionId);
    if (!_isCurrentDesktopQuick(generation)) return;
    if (update.authenticated) {
      final authenticationGeneration = ++_generation;
      _verificationOperation?.cancel();
      _verificationOperation = null;
      _startOperation?.cancel();
      _startOperation = null;
      _session?.cancel();
      _session = null;
      _clearQrChallenge();
      _desktopQuickSession = null;
      _desktopQuickAccounts = const [];
      _desktopQuickFailure = null;
      _desktopQuickSelectionId = null;
      _desktopQuickStage = DesktopQuickLoginStage.idle;
      await _finishAuthentication(authenticationGeneration);
      return;
    }

    _desktopQuickFailure =
        update.failure ?? DesktopQuickLoginFailure.invalidResponse;
    if (!update.sessionActive) {
      _desktopQuickSession = null;
    }
    _desktopQuickStage = DesktopQuickLoginStage.error;
    _notify();
  }

  Future<void> start() => supportsDesktopQuickLogin
      ? startDesktopQqAuthorization()
      : startQr(LoginQrChannel.wechat);

  Future<void> startDesktopQqAuthorization() async {
    if (!supportsDesktopQuickLogin) {
      await startQr(LoginQrChannel.qq);
      return;
    }
    unawaited(loadDesktopQuickAccounts());
    await startQr(LoginQrChannel.qq);
  }

  Future<void> startQr(LoginQrChannel channel) async {
    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearOfficialWebLogin();
    _clearSmsAuthentication();
    _clearQrChallenge();
    _failure = null;
    _qrChannel = channel;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.starting;
    _notify();

    final operation = _gateway is MultiMethodQqMusicAuthenticationGateway
        ? (_gateway as MultiMethodQqMusicAuthenticationGateway).beginQrStart(
            channel,
          )
        : _gateway.beginStart();
    _startOperation = operation;
    final result = await operation.run();
    if (identical(_startOperation, operation)) {
      _startOperation = null;
    }
    if (!_isCurrent(generation)) {
      result.session?.cancel();
      return;
    }

    final session = result.session;
    final challenge = result.challenge;
    if (session == null || challenge == null) {
      _failure = result.failure ?? LoginFailure.invalidResponse;
      _stage = LoginStage.error;
      _notify();
      return;
    }

    _session = session;
    _qrImageBytes = challenge.imageBytes;
    _qrExternalConfirmationUri = challenge.externalConfirmationUri;
    _openingQrExternally = false;
    _externalQrLaunchFailed = false;
    _stage = LoginStage.waitingForScan;
    _notify();
    unawaited(_poll(generation));
  }

  void showSmsLogin() {
    if (!supportsSmsLogin || _disposed) return;
    ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearOfficialWebLogin();
    _clearDesktopQuickLogin();
    _clearSmsAuthentication();
    _clearQrChallenge();
    _failure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.idle;
    _smsStage = SmsLoginStage.ready;
    _notify();
  }

  void showQrLogin() => cancel();

  /// Opens the official confirmation page for the current QR challenge while
  /// leaving the Rust-owned session and its polling loop active.
  Future<bool> openQrChallengeExternally() async {
    if (!canOpenQrExternally || _disposed) return false;
    final uri = _qrExternalConfirmationUri!;
    final generation = _generation;
    _openingQrExternally = true;
    _externalQrLaunchFailed = false;
    _notify();

    bool opened;
    try {
      opened = await _externalLoginUriLauncher(uri);
    } on Object {
      opened = false;
    }
    if (!_isCurrent(generation) || uri != _qrExternalConfirmationUri) {
      return opened;
    }
    _openingQrExternally = false;
    _externalQrLaunchFailed = !opened;
    debugPrint(
      'FURA_DIAGNOSTIC netease_qr phase=external_handoff '
      'outcome=${opened ? 'opened' : 'failure'}',
    );
    _notify();
    return opened;
  }

  Future<void> startOfficialWebLogin() async {
    if (!supportsOfficialWebLogin || _disposed) return;
    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearSmsAuthentication();
    _clearDesktopQuickLogin();
    _clearOfficialWebLogin();
    _clearQrChallenge();
    _failure = null;
    _officialWebFailure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.officialWebLogin;
    _notify();

    final operation = (_gateway as OfficialWebAuthenticationGateway)
        .beginOfficialWebLogin();
    _officialWebOperation = operation;
    final outcome = await operation.run();
    if (identical(_officialWebOperation, operation)) {
      _officialWebOperation = null;
    }
    if (!_isCurrent(generation)) return;
    if (outcome.authenticated) {
      await _finishAuthentication(generation);
      return;
    }
    _officialWebFailure =
        outcome.failure ?? OfficialWebAuthenticationFailure.coreUnavailable;
    if (_officialWebFailure == OfficialWebAuthenticationFailure.cancelled ||
        _officialWebFailure == OfficialWebAuthenticationFailure.replaced) {
      _stage = LoginStage.idle;
      _officialWebFailure = null;
    } else {
      _stage = LoginStage.officialWebError;
    }
    _notify();
  }

  Future<void> retryOfficialWebVerification() async {
    if (!canRetryOfficialWebVerification || _disposed) return;
    final generation = ++_generation;
    _verificationOperation?.cancel();
    final operation = _gateway.beginCredentialVerification();
    _verificationOperation = operation;
    _officialWebFailure = null;
    _stage = LoginStage.officialWebLogin;
    _notify();

    final result = await operation.run();
    if (identical(_verificationOperation, operation)) {
      _verificationOperation = null;
    }
    if (!_isCurrent(generation)) return;
    if (result == CredentialVerificationResult.authenticated) {
      await _finishAuthentication(generation);
      return;
    }
    _officialWebFailure = switch (result) {
      CredentialVerificationResult.rejected ||
      CredentialVerificationResult.rejectedStorageCleanupFailed =>
        OfficialWebAuthenticationFailure.rejected,
      CredentialVerificationResult.network =>
        OfficialWebAuthenticationFailure.network,
      CredentialVerificationResult.serviceUnavailable =>
        OfficialWebAuthenticationFailure.serviceUnavailable,
      CredentialVerificationResult.invalidResponse =>
        OfficialWebAuthenticationFailure.invalidResponse,
      CredentialVerificationResult.replaced =>
        OfficialWebAuthenticationFailure.replaced,
      CredentialVerificationResult.noRestoredCredential ||
      CredentialVerificationResult.coreUnavailable =>
        OfficialWebAuthenticationFailure.coreUnavailable,
      CredentialVerificationResult.authenticated => null,
    };
    if (_officialWebFailure == OfficialWebAuthenticationFailure.replaced) {
      _officialWebFailure = null;
      _stage = LoginStage.idle;
    } else {
      _stage = LoginStage.officialWebError;
    }
    _notify();
  }

  Future<void> requestSmsCode({
    required String countryCode,
    required String phone,
  }) async {
    if (!supportsSmsLogin || _disposed) return;
    final generation = ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearOfficialWebLogin();
    _clearDesktopQuickLogin();
    _clearSmsAuthentication();
    _clearQrChallenge();
    _failure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.idle;
    _smsStage = SmsLoginStage.sendingCode;
    _notify();

    final operation = (_gateway as SmsAuthenticationGateway)
        .beginSmsCodeRequest(countryCode: countryCode, phone: phone);
    _smsCodeRequestOperation = operation;
    final outcome = await operation.run();
    if (identical(_smsCodeRequestOperation, operation)) {
      _smsCodeRequestOperation = null;
    }
    if (!_isCurrent(generation)) return;

    if (outcome.success) {
      _smsFailure = null;
      _smsCodeRequested = true;
      _smsStage = SmsLoginStage.codeSent;
    } else {
      _smsFailure = outcome.failure ?? SmsAuthenticationFailure.invalidResponse;
      _smsStage = _smsFailure == SmsAuthenticationFailure.replaced
          ? SmsLoginStage.ready
          : SmsLoginStage.error;
    }
    _notify();
  }

  Future<void> authenticateSmsCode(String code) async {
    if (!supportsSmsLogin || !_smsCodeRequested || _disposed) return;
    final generation = ++_generation;
    _smsLoginOperation?.cancel();
    final operation = (_gateway as SmsAuthenticationGateway).beginSmsLogin(
      code: code,
    );
    _smsLoginOperation = operation;
    _smsFailure = null;
    _smsStage = SmsLoginStage.authenticating;
    _notify();

    final outcome = await operation.run();
    if (identical(_smsLoginOperation, operation)) {
      _smsLoginOperation = null;
    }
    if (!_isCurrent(generation)) return;

    if (outcome.success) {
      _clearSmsAuthentication(cancelProvider: false);
      await _finishAuthentication(generation);
      return;
    }
    _smsFailure = outcome.failure ?? SmsAuthenticationFailure.invalidResponse;
    if (_smsFailure == SmsAuthenticationFailure.replaced) {
      _smsCodeRequested = false;
      _smsStage = SmsLoginStage.ready;
    } else {
      _smsStage = SmsLoginStage.error;
    }
    _notify();
  }

  void retry() {
    if (!canRetry) return;
    _failure = null;
    _stage = LoginStage.waitingForScan;
    _notify();
    unawaited(_poll(_generation));
  }

  void cancel() {
    ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    _clearOfficialWebLogin();
    _clearSmsAuthentication();
    _clearDesktopQuickLogin();
    _clearQrChallenge();
    _failure = null;
    _credentialSaveState = CredentialSaveState.none;
    _credentialRestoreResult = CredentialRestoreResult.signedOut;
    _credentialVerificationResult = null;
    _stage = LoginStage.idle;
    _notify();
  }

  Future<void> _poll(int generation) async {
    if (!_pollingGenerations.add(generation)) return;
    final minimumPollInterval = _gateway is QrLoginPollingPolicy
        ? (_gateway as QrLoginPollingPolicy).minimumQrPollInterval
        : Duration.zero;
    var paceNextPoll = false;
    try {
      while (_isCurrent(generation)) {
        if (paceNextPoll && minimumPollInterval > Duration.zero) {
          await _delay(minimumPollInterval);
          if (!_isCurrent(generation)) return;
        }
        paceNextPoll = false;
        final session = _session;
        if (session == null || !session.isActive) return;

        final update = await session.advance();
        if (!_isCurrent(generation)) return;

        final progress = update.progress;
        if (progress != null) {
          if (await _applyProgress(progress, generation)) return;
          paceNextPoll = true;
          _notify();
          continue;
        }

        final failure = update.failure ?? LoginFailure.invalidResponse;
        if (failure == LoginFailure.network && update.sessionActive) {
          _failure = failure;
          _stage = LoginStage.reconnecting;
          _notify();
          await _delay(_networkRetryDelay);
          continue;
        }

        _failure = failure;
        _stage = failure == LoginFailure.timedOut
            ? LoginStage.timedOut
            : LoginStage.error;
        if (!update.sessionActive) {
          _session = null;
          _clearQrChallenge();
        }
        _notify();
        return;
      }
    } finally {
      _pollingGenerations.remove(generation);
    }
  }

  static Future<void> _defaultDelay(Duration duration) =>
      Future<void>.delayed(duration);

  Future<bool> _applyProgress(LoginProgress progress, int generation) async {
    switch (progress) {
      case LoginProgress.waitingForScan:
        _failure = null;
        _stage = LoginStage.waitingForScan;
        return false;
      case LoginProgress.scannedAwaitingConfirmation:
        _failure = null;
        _stage = LoginStage.scannedAwaitingConfirmation;
        return false;
      case LoginProgress.authenticated:
        _session = null;
        _clearQrChallenge();
        _clearDesktopQuickLogin();
        await _finishAuthentication(generation);
        return true;
      case LoginProgress.expired:
        _stage = LoginStage.expired;
        _session = null;
        _clearQrChallenge();
        _failure = null;
        _notify();
        return true;
      case LoginProgress.refused:
        _stage = LoginStage.refused;
        _session = null;
        _clearQrChallenge();
        _failure = null;
        _notify();
        return true;
      case LoginProgress.timedOut:
        _stage = LoginStage.timedOut;
        _session = null;
        _clearQrChallenge();
        _failure = null;
        _notify();
        return true;
    }
  }

  Future<void> _finishAuthentication(int generation) async {
    _failure = null;
    _stage = LoginStage.authenticated;
    _credentialSaveState = CredentialSaveState.saving;
    _notify();
    final result = await _gateway.persistAuthenticatedCredential();
    if (!_isCurrent(generation)) return;
    _credentialSaveState = result == CredentialPersistenceResult.stored
        ? CredentialSaveState.saved
        : CredentialSaveState.failed;
    _notify();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _isCurrentDesktopQuick(int generation) =>
      !_disposed && generation == _desktopQuickGeneration;

  void _clearDesktopQuickLogin() {
    ++_desktopQuickGeneration;
    _desktopQuickStartOperation?.cancel();
    _desktopQuickStartOperation = null;
    _desktopQuickSession?.cancel();
    _desktopQuickSession = null;
    _desktopQuickAccounts = const [];
    _desktopQuickFailure = null;
    _desktopQuickSelectionId = null;
    _desktopQuickStage = DesktopQuickLoginStage.idle;
  }

  void _clearSmsAuthentication({bool cancelProvider = true}) {
    final hadProviderSession =
        _smsCodeRequested ||
        _smsCodeRequestOperation != null ||
        _smsLoginOperation != null;
    if (cancelProvider) {
      var cancelledAttempt = false;
      cancelledAttempt =
          (_smsCodeRequestOperation?.cancel() ?? false) || cancelledAttempt;
      cancelledAttempt =
          (_smsLoginOperation?.cancel() ?? false) || cancelledAttempt;
      if (hadProviderSession && !cancelledAttempt) {
        (_gateway as SmsAuthenticationGateway).cancelSmsAuthentication();
      }
    }
    _smsCodeRequestOperation = null;
    _smsLoginOperation = null;
    _smsFailure = null;
    _smsCodeRequested = false;
    _smsStage = SmsLoginStage.hidden;
  }

  void _clearOfficialWebLogin() {
    _officialWebOperation?.cancel();
    _officialWebOperation = null;
    _officialWebFailure = null;
  }

  void _clearQrChallenge() {
    _qrImageBytes = null;
    _qrExternalConfirmationUri = null;
    _openingQrExternally = false;
    _externalQrLaunchFailed = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _verificationOperation?.cancel();
    _verificationOperation = null;
    _clearOfficialWebLogin();
    _clearSmsAuthentication();
    _clearDesktopQuickLogin();
    _startOperation?.cancel();
    _startOperation = null;
    _session?.cancel();
    _session = null;
    super.dispose();
  }
}
