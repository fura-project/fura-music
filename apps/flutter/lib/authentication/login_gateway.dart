import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutterustmusic/authentication/credential_vault.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;
import 'package:flutterustmusic/src/rust/api/netease_authentication.dart'
    as netease_bridge;

enum LoginImageFormat { png, jpeg }

enum LoginQrChannel { qq, wechat }

enum LoginProgress {
  waitingForScan,
  scannedAwaitingConfirmation,
  authenticated,
  expired,
  refused,
  timedOut,
}

enum LoginFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  rejected,
  cancelled,
  replaced,
  sessionClosed,
  sessionFinished,
  timedOut,
  tooManyNetworkFailures,
  advanceAlreadyInProgress,
  securityVerificationRequired,
  secondaryVerificationRequired,
}

enum DesktopQuickLoginFailure {
  coreUnavailable,
  clientUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  invalidSelection,
  rejected,
  cancelled,
  replaced,
  sessionFinished,
  alreadyRunning,
}

enum SmsAuthenticationFailure {
  coreUnavailable,
  network,
  serviceUnavailable,
  invalidResponse,
  invalidInput,
  codeRejected,
  rateLimited,
  securityVerificationRequired,
  secondaryVerificationRequired,
  replaced,
  alreadyRunning,
}

class SmsAuthenticationOutcome {
  const SmsAuthenticationOutcome({required this.success, this.failure});

  final bool success;
  final SmsAuthenticationFailure? failure;
}

enum OfficialWebAuthenticationFailure {
  unavailable,
  cancelled,
  alreadyRunning,
  invalidCredential,
  timedOut,
  cleanupFailed,
  rejected,
  network,
  serviceUnavailable,
  invalidResponse,
  replaced,
  coreUnavailable,
}

class OfficialWebAuthenticationOutcome {
  const OfficialWebAuthenticationOutcome({
    required this.authenticated,
    this.failure,
  });

  final bool authenticated;
  final OfficialWebAuthenticationFailure? failure;
}

enum CredentialPersistenceResult {
  stored,
  noAuthenticatedCredential,
  storageUnavailable,
}

enum CredentialRestoreResult {
  signedOut,
  verificationRequired,
  locallyExpired,
  invalidStoredCredential,
  unsupportedStoredCredential,
  storageUnavailable,
  coreUnavailable,
}

enum CredentialVerificationResult {
  authenticated,
  rejected,
  rejectedStorageCleanupFailed,
  network,
  serviceUnavailable,
  invalidResponse,
  noRestoredCredential,
  replaced,
  coreUnavailable,
}

enum CredentialSignOutResult {
  signedOut,
  storageCleanupFailed,
  browserCleanupFailed,
  coreUnavailable,
}

typedef CredentialRestoreImporter = CredentialRestoreResult Function(
  Uint8List? secretBytes,
);

typedef CredentialVerificationOperationFactory =
    CredentialVerificationOperation Function();

typedef CredentialSignOutCore = bool Function();

class LoginChallenge {
  const LoginChallenge({
    required this.imageFormat,
    required this.imageBytes,
    this.externalConfirmationUri,
  });

  final LoginImageFormat imageFormat;
  final Uint8List imageBytes;
  final Uri? externalConfirmationUri;
}

class LoginUpdate {
  const LoginUpdate({this.progress, this.failure, required this.sessionActive});

  final LoginProgress? progress;
  final LoginFailure? failure;
  final bool sessionActive;
}

abstract interface class LoginSession {
  Future<LoginUpdate> advance();
  bool cancel();
  bool get isActive;
}

class LoginStart {
  const LoginStart({this.session, this.challenge, this.failure});

  final LoginSession? session;
  final LoginChallenge? challenge;
  final LoginFailure? failure;
}

class DesktopQuickLoginAccount {
  const DesktopQuickLoginAccount({
    required this.selectionId,
    required this.displayName,
    required this.accountHint,
  });

  final int selectionId;
  final String displayName;
  final String accountHint;
}

class DesktopQuickLoginUpdate {
  const DesktopQuickLoginUpdate({
    required this.authenticated,
    this.failure,
    required this.sessionActive,
  });

  final bool authenticated;
  final DesktopQuickLoginFailure? failure;
  final bool sessionActive;
}

abstract interface class DesktopQuickLoginSession {
  Future<DesktopQuickLoginUpdate> authorize(int selectionId);
  bool cancel();
  bool get isActive;
}

class DesktopQuickLoginStart {
  const DesktopQuickLoginStart({
    this.session,
    this.accounts = const [],
    this.failure,
  });

  final DesktopQuickLoginSession? session;
  final List<DesktopQuickLoginAccount> accounts;
  final DesktopQuickLoginFailure? failure;
}

abstract interface class DesktopQuickLoginStartOperation {
  Future<DesktopQuickLoginStart> run();
  bool cancel();
}

abstract interface class QqMusicAuthenticationGateway {
  LoginStartOperation beginStart();
  bool get hasAuthenticatedCredential;
  Future<CredentialPersistenceResult> persistAuthenticatedCredential();
  Future<CredentialRestoreResult> restoreCredential();
  CredentialVerificationOperation beginCredentialVerification();
  Future<CredentialSignOutResult> signOut();
}

abstract interface class ProviderAuthenticationPresentation {
  String get providerId;
}

/// Optional pacing for providers whose QR status endpoint returns immediately.
///
/// Providers that use a long-polling endpoint do not need to implement this.
abstract interface class QrLoginPollingPolicy {
  Duration get minimumQrPollInterval;
}

abstract interface class MultiMethodQqMusicAuthenticationGateway {
  LoginStartOperation beginQrStart(LoginQrChannel channel);
}

abstract interface class DesktopQuickQqMusicAuthenticationGateway {
  DesktopQuickLoginStartOperation beginDesktopQuickLoginStart();
}

/// Optional phone-code authentication exposed only by providers that own a
/// complete request/login session.
abstract interface class SmsAuthenticationGateway {
  SmsCodeRequestOperation beginSmsCodeRequest({
    required String countryCode,
    required String phone,
  });
  SmsLoginOperation beginSmsLogin({required String code});
  bool cancelSmsAuthentication();
}

/// Optional handoff to the provider's own interactive website. The provider
/// credential is still verified by the same Rust account endpoint before this
/// operation reports authentication.
abstract interface class OfficialWebAuthenticationGateway {
  bool get supportsOfficialWebLogin;
  OfficialWebAuthenticationOperation beginOfficialWebLogin();
}

/// Marks a provider whose only product login route is its official website.
///
/// The legacy QR start required by [QqMusicAuthenticationGateway] remains an
/// internal compatibility boundary, but the controller and UI never expose or
/// invoke it for a gateway carrying this capability.
abstract interface class OfficialWebOnlyAuthenticationGateway {}

/// Optional visible presentation owned by an official-Web login broker.
///
/// The controller and UI observe this boundary without passing a BuildContext
/// into authentication or credential layers.
abstract interface class OfficialWebAuthenticationPresentation {
  Listenable get officialWebPresentationListenable;
  OfficialWebLoginPresentationStage get officialWebPresentationStage;
  Widget? get officialWebLoginView;
}

abstract interface class OfficialWebAuthenticationOperation {
  Future<OfficialWebAuthenticationOutcome> run();
  bool cancel();
}

abstract interface class SmsCodeRequestOperation {
  Future<SmsAuthenticationOutcome> run();
  bool cancel();
}

abstract interface class SmsLoginOperation {
  Future<SmsAuthenticationOutcome> run();
  bool cancel();
}

abstract interface class LoginStartOperation {
  Future<LoginStart> run();
  bool cancel();
}

abstract interface class CredentialVerificationOperation {
  Future<CredentialVerificationResult> run();
  bool cancel();
}

class RustQqMusicAuthenticationGateway
    implements
        QqMusicAuthenticationGateway,
        ProviderAuthenticationPresentation,
        MultiMethodQqMusicAuthenticationGateway,
        DesktopQuickQqMusicAuthenticationGateway {
  RustQqMusicAuthenticationGateway({
    CredentialVault? credentialVault,
    CredentialRestoreImporter? credentialImporter,
    CredentialVerificationOperationFactory? verificationOperationFactory,
    CredentialSignOutCore? credentialSignOutCore,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ?? PlatformCredentialVault(),
       ),
       _credentialImporter =
           credentialImporter ?? _restoreQqMusicCredentialInRust,
       _verificationOperationFactory =
           verificationOperationFactory ?? _reserveRustCredentialVerification,
       _credentialSignOutCore = credentialSignOutCore ?? bridge.signOutQqMusic;

  final CredentialVault _credentialVault;
  final CredentialRestoreImporter _credentialImporter;
  final CredentialVerificationOperationFactory _verificationOperationFactory;
  final CredentialSignOutCore _credentialSignOutCore;

  @override
  String get providerId => 'qq-music';

  @override
  bool get hasAuthenticatedCredential =>
      bridge.qqMusicHasAuthenticatedCredential();

  @override
  LoginStartOperation beginStart() => beginQrStart(LoginQrChannel.wechat);

  @override
  LoginStartOperation beginQrStart(LoginQrChannel channel) =>
      _RustLoginStartOperation(bridge.reserveQqMusicQrLoginStart(), channel);

  @override
  DesktopQuickLoginStartOperation beginDesktopQuickLoginStart() =>
      _RustDesktopQuickLoginStartOperation(
        bridge.reserveQqMusicDesktopQuickLoginStart(),
      );

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      _VaultCleaningCredentialVerificationOperation(
        _verificationOperationFactory(),
        _credentialVault,
      );

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async {
    final export = bridge.exportQqMusicCredentialForSecureStorage();
    final secretBytes = export.secretBytes;
    if (secretBytes == null) {
      return CredentialPersistenceResult.noAuthenticatedCredential;
    }

    try {
      await _credentialVault.write(secretBytes);
      return CredentialPersistenceResult.stored;
    } catch (_) {
      return CredentialPersistenceResult.storageUnavailable;
    } finally {
      secretBytes.fillRange(0, secretBytes.length, 0);
    }
  }

  @override
  Future<CredentialRestoreResult> restoreCredential() async {
    Uint8List? secretBytes;
    try {
      secretBytes = await _credentialVault.read();
    } on FormatException {
      return CredentialRestoreResult.invalidStoredCredential;
    } catch (_) {
      return CredentialRestoreResult.storageUnavailable;
    }

    try {
      return _credentialImporter(secretBytes);
    } catch (_) {
      return CredentialRestoreResult.coreUnavailable;
    } finally {
      secretBytes?.fillRange(0, secretBytes.length, 0);
    }
  }

  @override
  Future<CredentialSignOutResult> signOut() async {
    try {
      if (!_credentialSignOutCore()) {
        return CredentialSignOutResult.coreUnavailable;
      }
    } catch (_) {
      return CredentialSignOutResult.coreUnavailable;
    }

    try {
      await _credentialVault.delete();
      return CredentialSignOutResult.signedOut;
    } catch (_) {
      return CredentialSignOutResult.storageCleanupFailed;
    }
  }
}

class RustNeteaseAuthenticationGateway
    implements
        QqMusicAuthenticationGateway,
        ProviderAuthenticationPresentation,
        OfficialWebAuthenticationGateway,
        OfficialWebOnlyAuthenticationGateway,
        OfficialWebAuthenticationPresentation {
  RustNeteaseAuthenticationGateway({
    CredentialVault? credentialVault,
    OfficialWebLoginBroker? officialWebLoginBroker,
    CredentialSignOutCore? credentialSignOutCore,
  }) : _credentialVault = SerializedCredentialVault(
         credentialVault ??
             PlatformCredentialVault(
               credentialKey: PlatformCredentialVault.netEaseCredentialKey,
             ),
       ),
       _officialWebLoginBroker =
           officialWebLoginBroker ?? PlatformNeteaseOfficialWebLoginBroker(),
       _usesLinuxSystemBrowser =
           officialWebLoginBroker == null &&
           !kIsWeb &&
           defaultTargetPlatform == TargetPlatform.linux,
       _credentialSignOutCore =
           credentialSignOutCore ?? netease_bridge.signOutNetease;

  final CredentialVault _credentialVault;
  final OfficialWebLoginBroker _officialWebLoginBroker;
  final bool _usesLinuxSystemBrowser;
  final _SystemBrowserOfficialWebPresentation _systemBrowserPresentation =
      _SystemBrowserOfficialWebPresentation();
  final CredentialSignOutCore _credentialSignOutCore;

  @override
  String get providerId => 'netease-cloud-music';

  @override
  bool get hasAuthenticatedCredential =>
      netease_bridge.neteaseHasAuthenticatedCredential();

  @override
  LoginStartOperation beginStart() =>
      const _OfficialWebOnlyLegacyStartOperation();

  @override
  bool get supportsOfficialWebLogin => _usesLinuxSystemBrowser
      ? netease_bridge.neteaseSystemBrowserLoginSupported()
      : _officialWebLoginBroker.isSupported;

  @override
  Listenable get officialWebPresentationListenable => _usesLinuxSystemBrowser
      ? _systemBrowserPresentation
      : _officialWebLoginBroker.presentationListenable;

  @override
  OfficialWebLoginPresentationStage get officialWebPresentationStage =>
      _usesLinuxSystemBrowser
      ? _systemBrowserPresentation.stage
      : _officialWebLoginBroker.presentationStage;

  @override
  Widget? get officialWebLoginView =>
      _usesLinuxSystemBrowser ? null : _officialWebLoginBroker.activeView;

  @override
  OfficialWebAuthenticationOperation beginOfficialWebLogin() =>
      _usesLinuxSystemBrowser
      ? _RustNeteaseSystemBrowserAuthenticationOperation(
          netease_bridge.reserveNeteaseSystemBrowserLogin(),
          _systemBrowserPresentation,
        )
      : _RustNeteaseOfficialWebAuthenticationOperation(_officialWebLoginBroker);

  @override
  CredentialVerificationOperation beginCredentialVerification() =>
      _VaultCleaningCredentialVerificationOperation(
        _reserveRustNeteaseCredentialVerification(),
        _credentialVault,
      );

  @override
  Future<CredentialPersistenceResult> persistAuthenticatedCredential() async {
    final export = netease_bridge.exportNeteaseCredentialForSecureStorage();
    final secretBytes = export.secretBytes;
    if (secretBytes == null) {
      return CredentialPersistenceResult.noAuthenticatedCredential;
    }
    try {
      await _credentialVault.write(secretBytes);
      return CredentialPersistenceResult.stored;
    } on Object {
      return CredentialPersistenceResult.storageUnavailable;
    } finally {
      secretBytes.fillRange(0, secretBytes.length, 0);
    }
  }

  @override
  Future<CredentialRestoreResult> restoreCredential() async {
    Uint8List? secretBytes;
    try {
      secretBytes = await _credentialVault.read();
    } on FormatException {
      return CredentialRestoreResult.invalidStoredCredential;
    } on Object {
      return CredentialRestoreResult.storageUnavailable;
    }
    try {
      return _restoreNeteaseCredentialInRust(secretBytes);
    } on Object {
      return CredentialRestoreResult.coreUnavailable;
    } finally {
      secretBytes?.fillRange(0, secretBytes.length, 0);
    }
  }

  @override
  Future<CredentialSignOutResult> signOut() async {
    final browserCleanupSucceeded = _usesLinuxSystemBrowser
        ? await _cancelLinuxSystemBrowserForSignOut()
        : await _clearEmbeddedOfficialWebSession();
    try {
      if (!_credentialSignOutCore()) {
        return CredentialSignOutResult.coreUnavailable;
      }
    } on Object {
      return CredentialSignOutResult.coreUnavailable;
    }
    try {
      await _credentialVault.delete();
      return browserCleanupSucceeded
          ? CredentialSignOutResult.signedOut
          : CredentialSignOutResult.browserCleanupFailed;
    } on Object {
      return CredentialSignOutResult.storageCleanupFailed;
    }
  }

  Future<bool> _cancelLinuxSystemBrowserForSignOut() async {
    _systemBrowserPresentation.reset();
    try {
      await netease_bridge.cancelActiveNeteaseSystemBrowserLoginAndWait();
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _clearEmbeddedOfficialWebSession() async {
    _officialWebLoginBroker.cancel();
    return _officialWebLoginBroker.clearWebsiteData();
  }
}

class _SystemBrowserOfficialWebPresentation extends ChangeNotifier {
  OfficialWebLoginPresentationStage _stage =
      OfficialWebLoginPresentationStage.idle;

  OfficialWebLoginPresentationStage get stage => _stage;

  void show(OfficialWebLoginPresentationStage stage) {
    if (_stage == stage) return;
    _stage = stage;
    notifyListeners();
  }

  void reset() => show(OfficialWebLoginPresentationStage.idle);
}

class _RustNeteaseSystemBrowserAuthenticationOperation
    implements OfficialWebAuthenticationOperation {
  _RustNeteaseSystemBrowserAuthenticationOperation(
    this._attemptId,
    this._presentation,
  );

  final int _attemptId;
  final _SystemBrowserOfficialWebPresentation _presentation;
  bool _cancelled = false;

  @override
  bool cancel() {
    if (_cancelled) return false;
    _cancelled = true;
    _presentation.reset();
    return netease_bridge.cancelNeteaseSystemBrowserLogin(
      attemptId: _attemptId,
    );
  }

  @override
  Future<OfficialWebAuthenticationOutcome> run() async {
    _presentation.show(OfficialWebLoginPresentationStage.preparing);
    await Future<void>.delayed(Duration.zero);
    if (_cancelled) {
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.cancelled,
      );
    }
    _presentation.show(OfficialWebLoginPresentationStage.waitingForSignIn);
    try {
      final outcome = await netease_bridge.authenticateNeteaseWithSystemBrowser(
        attemptId: _attemptId,
      );
      debugPrint(
        'FURA_DIAGNOSTIC netease_system_browser phase=complete '
        'outcome=${outcome.authenticated ? 'authenticated' : 'failure'} '
        'failure=${outcome.failure?.name ?? 'none'}',
      );
      if (_cancelled) {
        return const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.cancelled,
        );
      }
      if (outcome.authenticated) {
        _presentation.show(OfficialWebLoginPresentationStage.finishing);
        return const OfficialWebAuthenticationOutcome(authenticated: true);
      }
      return OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: _mapSystemBrowserFailure(outcome.failure),
      );
    } on Object catch (error) {
      debugPrint(
        'FURA_DIAGNOSTIC netease_system_browser phase=complete '
        'outcome=exception error=${error.runtimeType}',
      );
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.coreUnavailable,
      );
    } finally {
      _presentation.reset();
    }
  }
}

OfficialWebAuthenticationFailure _mapSystemBrowserFailure(
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure? failure,
) => switch (failure) {
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.cancelled =>
    OfficialWebAuthenticationFailure.cancelled,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.replaced =>
    OfficialWebAuthenticationFailure.replaced,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.timedOut =>
    OfficialWebAuthenticationFailure.timedOut,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.invalidCredential =>
    OfficialWebAuthenticationFailure.invalidCredential,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.cleanupFailed =>
    OfficialWebAuthenticationFailure.cleanupFailed,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.rejected =>
    OfficialWebAuthenticationFailure.rejected,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.network =>
    OfficialWebAuthenticationFailure.network,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.serviceUnavailable =>
    OfficialWebAuthenticationFailure.serviceUnavailable,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.invalidResponse =>
    OfficialWebAuthenticationFailure.invalidResponse,
  netease_bridge
      .NeteaseSystemBrowserAuthenticationFailure
      .unsupportedPlatform ||
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.browserUnavailable =>
    OfficialWebAuthenticationFailure.unavailable,
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.browserClosed =>
    OfficialWebAuthenticationFailure.cancelled,
  netease_bridge
      .NeteaseSystemBrowserAuthenticationFailure
      .browserLaunchFailed ||
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.profileSetupFailed ||
  netease_bridge
      .NeteaseSystemBrowserAuthenticationFailure
      .devtoolsUnavailable ||
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.devtoolsInvalid ||
  netease_bridge
      .NeteaseSystemBrowserAuthenticationFailure
      .officialTargetUnavailable ||
  netease_bridge.NeteaseSystemBrowserAuthenticationFailure.coreUnavailable ||
  null => OfficialWebAuthenticationFailure.coreUnavailable,
};

class _RustNeteaseOfficialWebAuthenticationOperation
    implements OfficialWebAuthenticationOperation {
  _RustNeteaseOfficialWebAuthenticationOperation(this._broker);

  final OfficialWebLoginBroker _broker;
  CredentialVerificationOperation? _verification;
  bool _cancelled = false;

  @override
  bool cancel() {
    if (_cancelled) return false;
    _cancelled = true;
    final browserCancelled = _broker.cancel();
    final verificationCancelled = _verification?.cancel() ?? false;
    return browserCancelled || verificationCancelled;
  }

  @override
  Future<OfficialWebAuthenticationOutcome> run() async {
    Uint8List? secretBytes;
    try {
      secretBytes = await _broker.authenticate();
    } on OfficialWebLoginException catch (error) {
      return OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: switch (error.failure) {
          OfficialWebLoginFailure.unavailable =>
            OfficialWebAuthenticationFailure.unavailable,
          OfficialWebLoginFailure.alreadyRunning =>
            OfficialWebAuthenticationFailure.alreadyRunning,
          OfficialWebLoginFailure.invalidCredential =>
            OfficialWebAuthenticationFailure.invalidCredential,
          OfficialWebLoginFailure.timedOut =>
            OfficialWebAuthenticationFailure.timedOut,
          OfficialWebLoginFailure.cleanupFailed =>
            OfficialWebAuthenticationFailure.cleanupFailed,
          OfficialWebLoginFailure.failed =>
            OfficialWebAuthenticationFailure.coreUnavailable,
        },
      );
    } on Object {
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.coreUnavailable,
      );
    }
    if (_cancelled || secretBytes == null) {
      secretBytes?.fillRange(0, secretBytes.length, 0);
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.cancelled,
      );
    }

    CredentialRestoreResult staged;
    try {
      staged = _stageNeteaseOfficialWebCredentialInRust(secretBytes);
    } on Object {
      staged = CredentialRestoreResult.coreUnavailable;
    } finally {
      secretBytes.fillRange(0, secretBytes.length, 0);
    }
    debugPrint(
      'FURA_DIAGNOSTIC netease_web phase=stage outcome=${staged.name}',
    );
    if (_cancelled) {
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.cancelled,
      );
    }
    if (staged != CredentialRestoreResult.verificationRequired) {
      return OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: staged == CredentialRestoreResult.coreUnavailable
            ? OfficialWebAuthenticationFailure.coreUnavailable
            : OfficialWebAuthenticationFailure.invalidCredential,
      );
    }

    final verification = _reserveRustNeteaseCredentialVerification();
    _verification = verification;
    final result = await verification.run();
    debugPrint(
      'FURA_DIAGNOSTIC netease_web phase=verify outcome=${result.name}',
    );
    if (identical(_verification, verification)) _verification = null;
    if (_cancelled) {
      return const OfficialWebAuthenticationOutcome(
        authenticated: false,
        failure: OfficialWebAuthenticationFailure.cancelled,
      );
    }
    return switch (result) {
      CredentialVerificationResult.authenticated =>
        const OfficialWebAuthenticationOutcome(authenticated: true),
      CredentialVerificationResult.rejected ||
      CredentialVerificationResult.rejectedStorageCleanupFailed =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.rejected,
        ),
      CredentialVerificationResult.network =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.network,
        ),
      CredentialVerificationResult.serviceUnavailable =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.serviceUnavailable,
        ),
      CredentialVerificationResult.invalidResponse =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.invalidResponse,
        ),
      CredentialVerificationResult.replaced =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.replaced,
        ),
      CredentialVerificationResult.noRestoredCredential ||
      CredentialVerificationResult.coreUnavailable =>
        const OfficialWebAuthenticationOutcome(
          authenticated: false,
          failure: OfficialWebAuthenticationFailure.coreUnavailable,
        ),
    };
  }
}

CredentialVerificationOperation _reserveRustCredentialVerification() {
  final attemptId = bridge.reserveQqMusicCredentialVerification();
  return attemptId == null
      ? const _ImmediateCredentialVerificationOperation(
          CredentialVerificationResult.noRestoredCredential,
        )
      : _RustCredentialVerificationOperation(attemptId);
}

class _RustCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _RustCredentialVerificationOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      bridge.cancelQqMusicCredentialVerification(attemptId: _attemptId);

  @override
  Future<CredentialVerificationResult> run() async {
    try {
      final outcome = await bridge.verifyRestoredQqMusicCredential(
        attemptId: _attemptId,
      );
      final state = outcome.state;
      if (state != null) {
        return switch (state) {
          bridge.QqMusicCredentialVerificationState.authenticated =>
            CredentialVerificationResult.authenticated,
          bridge.QqMusicCredentialVerificationState.rejected =>
            CredentialVerificationResult.rejected,
        };
      }
      return switch (outcome.failure) {
        bridge.QqMusicCredentialVerificationFailure.network =>
          CredentialVerificationResult.network,
        bridge.QqMusicCredentialVerificationFailure.serviceUnavailable =>
          CredentialVerificationResult.serviceUnavailable,
        bridge.QqMusicCredentialVerificationFailure.invalidResponse =>
          CredentialVerificationResult.invalidResponse,
        bridge.QqMusicCredentialVerificationFailure.noRestoredCredential =>
          CredentialVerificationResult.noRestoredCredential,
        bridge.QqMusicCredentialVerificationFailure.replaced =>
          CredentialVerificationResult.replaced,
        bridge.QqMusicCredentialVerificationFailure.coreUnavailable ||
        null => CredentialVerificationResult.coreUnavailable,
      };
    } catch (_) {
      return CredentialVerificationResult.coreUnavailable;
    }
  }
}

class _ImmediateCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _ImmediateCredentialVerificationOperation(this._result);

  final CredentialVerificationResult _result;

  @override
  bool cancel() => false;

  @override
  Future<CredentialVerificationResult> run() async => _result;
}

class _VaultCleaningCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _VaultCleaningCredentialVerificationOperation(
    this._inner,
    this._credentialVault,
  );

  final CredentialVerificationOperation _inner;
  final CredentialVault _credentialVault;

  @override
  bool cancel() => _inner.cancel();

  @override
  Future<CredentialVerificationResult> run() async {
    final result = await _inner.run();
    if (result != CredentialVerificationResult.rejected) return result;
    try {
      await _credentialVault.delete();
      return result;
    } catch (_) {
      return CredentialVerificationResult.rejectedStorageCleanupFailed;
    }
  }
}

CredentialRestoreResult _restoreQqMusicCredentialInRust(
  Uint8List? secretBytes,
) {
  final outcome = bridge.restoreQqMusicCredentialFromSecureStorage(
    secretBytes: secretBytes,
  );
  final state = outcome.state;
  if (state != null) {
    return switch (state) {
      bridge.QqMusicCredentialRestoreState.signedOut =>
        CredentialRestoreResult.signedOut,
      bridge.QqMusicCredentialRestoreState.verificationRequired =>
        CredentialRestoreResult.verificationRequired,
      bridge.QqMusicCredentialRestoreState.locallyExpired =>
        CredentialRestoreResult.locallyExpired,
    };
  }

  return switch (outcome.failure) {
    bridge.QqMusicCredentialRestoreFailure.invalidDocument ||
    bridge.QqMusicCredentialRestoreFailure.invalidCredential =>
      CredentialRestoreResult.invalidStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.unsupportedVersion =>
      CredentialRestoreResult.unsupportedStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.coreUnavailable ||
    null => CredentialRestoreResult.coreUnavailable,
  };
}

CredentialRestoreResult _restoreNeteaseCredentialInRust(
  Uint8List? secretBytes,
) {
  final outcome = netease_bridge.restoreNeteaseCredentialFromSecureStorage(
    secretBytes: secretBytes,
  );
  final state = outcome.state;
  if (state != null) {
    return switch (state) {
      bridge.QqMusicCredentialRestoreState.signedOut =>
        CredentialRestoreResult.signedOut,
      bridge.QqMusicCredentialRestoreState.verificationRequired =>
        CredentialRestoreResult.verificationRequired,
      bridge.QqMusicCredentialRestoreState.locallyExpired =>
        CredentialRestoreResult.locallyExpired,
    };
  }
  return switch (outcome.failure) {
    bridge.QqMusicCredentialRestoreFailure.invalidDocument ||
    bridge.QqMusicCredentialRestoreFailure.invalidCredential =>
      CredentialRestoreResult.invalidStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.unsupportedVersion =>
      CredentialRestoreResult.unsupportedStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.coreUnavailable ||
    null => CredentialRestoreResult.coreUnavailable,
  };
}

CredentialRestoreResult _stageNeteaseOfficialWebCredentialInRust(
  Uint8List secretBytes,
) {
  final outcome = netease_bridge.stageNeteaseOfficialWebCredential(
    secretBytes: secretBytes,
  );
  final state = outcome.state;
  if (state != null) {
    return switch (state) {
      bridge.QqMusicCredentialRestoreState.signedOut =>
        CredentialRestoreResult.signedOut,
      bridge.QqMusicCredentialRestoreState.verificationRequired =>
        CredentialRestoreResult.verificationRequired,
      bridge.QqMusicCredentialRestoreState.locallyExpired =>
        CredentialRestoreResult.locallyExpired,
    };
  }
  return switch (outcome.failure) {
    bridge.QqMusicCredentialRestoreFailure.invalidDocument ||
    bridge.QqMusicCredentialRestoreFailure.invalidCredential =>
      CredentialRestoreResult.invalidStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.unsupportedVersion =>
      CredentialRestoreResult.unsupportedStoredCredential,
    bridge.QqMusicCredentialRestoreFailure.coreUnavailable ||
    null => CredentialRestoreResult.coreUnavailable,
  };
}

CredentialVerificationOperation _reserveRustNeteaseCredentialVerification() {
  final attemptId = netease_bridge.reserveNeteaseCredentialVerification();
  return attemptId == null
      ? const _ImmediateCredentialVerificationOperation(
          CredentialVerificationResult.noRestoredCredential,
        )
      : _RustNeteaseCredentialVerificationOperation(attemptId);
}

class _RustNeteaseCredentialVerificationOperation
    implements CredentialVerificationOperation {
  const _RustNeteaseCredentialVerificationOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      netease_bridge.cancelNeteaseCredentialVerification(attemptId: _attemptId);

  @override
  Future<CredentialVerificationResult> run() async {
    try {
      final outcome = await netease_bridge.verifyRestoredNeteaseCredential(
        attemptId: _attemptId,
      );
      final state = outcome.state;
      if (state != null) {
        return switch (state) {
          bridge.QqMusicCredentialVerificationState.authenticated =>
            CredentialVerificationResult.authenticated,
          bridge.QqMusicCredentialVerificationState.rejected =>
            CredentialVerificationResult.rejected,
        };
      }
      return switch (outcome.failure) {
        bridge.QqMusicCredentialVerificationFailure.network =>
          CredentialVerificationResult.network,
        bridge.QqMusicCredentialVerificationFailure.serviceUnavailable =>
          CredentialVerificationResult.serviceUnavailable,
        bridge.QqMusicCredentialVerificationFailure.invalidResponse =>
          CredentialVerificationResult.invalidResponse,
        bridge.QqMusicCredentialVerificationFailure.noRestoredCredential =>
          CredentialVerificationResult.noRestoredCredential,
        bridge.QqMusicCredentialVerificationFailure.replaced =>
          CredentialVerificationResult.replaced,
        bridge.QqMusicCredentialVerificationFailure.coreUnavailable ||
        null => CredentialVerificationResult.coreUnavailable,
      };
    } on Object {
      return CredentialVerificationResult.coreUnavailable;
    }
  }
}

class _RustDesktopQuickLoginStartOperation
    implements DesktopQuickLoginStartOperation {
  const _RustDesktopQuickLoginStartOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      bridge.cancelQqMusicDesktopQuickLoginStart(attemptId: _attemptId);

  @override
  Future<DesktopQuickLoginStart> run() async {
    try {
      final outcome = await bridge.startQqMusicDesktopQuickLogin(
        attemptId: _attemptId,
      );
      final failure = outcome.failure;
      final session = outcome.session;
      return DesktopQuickLoginStart(
        session: session == null
            ? null
            : _RustDesktopQuickLoginSession(session),
        accounts: outcome.accounts
            .map(
              (account) => DesktopQuickLoginAccount(
                selectionId: account.selectionId,
                displayName: account.displayName,
                accountHint: account.accountHint,
              ),
            )
            .toList(growable: false),
        failure: failure == null ? null : _mapDesktopQuickFailure(failure),
      );
    } on Object {
      return const DesktopQuickLoginStart(
        failure: DesktopQuickLoginFailure.coreUnavailable,
      );
    }
  }
}

class _RustDesktopQuickLoginSession implements DesktopQuickLoginSession {
  const _RustDesktopQuickLoginSession(this._inner);

  final bridge.QqMusicDesktopQuickLoginSessionHandle _inner;

  @override
  bool cancel() => _inner.cancel();

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<DesktopQuickLoginUpdate> authorize(int selectionId) async {
    try {
      final update = await _inner.authorize(selectionId: selectionId);
      return DesktopQuickLoginUpdate(
        authenticated: update.authenticated,
        failure: update.failure == null
            ? null
            : _mapDesktopQuickFailure(update.failure!),
        sessionActive: update.sessionActive,
      );
    } on Object {
      return DesktopQuickLoginUpdate(
        authenticated: false,
        failure: DesktopQuickLoginFailure.coreUnavailable,
        sessionActive: _inner.isActive,
      );
    }
  }
}

DesktopQuickLoginFailure _mapDesktopQuickFailure(
  bridge.QqMusicDesktopQuickLoginFailure failure,
) => switch (failure) {
  bridge.QqMusicDesktopQuickLoginFailure.coreUnavailable =>
    DesktopQuickLoginFailure.coreUnavailable,
  bridge.QqMusicDesktopQuickLoginFailure.clientUnavailable =>
    DesktopQuickLoginFailure.clientUnavailable,
  bridge.QqMusicDesktopQuickLoginFailure.network =>
    DesktopQuickLoginFailure.network,
  bridge.QqMusicDesktopQuickLoginFailure.serviceUnavailable =>
    DesktopQuickLoginFailure.serviceUnavailable,
  bridge.QqMusicDesktopQuickLoginFailure.invalidResponse =>
    DesktopQuickLoginFailure.invalidResponse,
  bridge.QqMusicDesktopQuickLoginFailure.invalidSelection =>
    DesktopQuickLoginFailure.invalidSelection,
  bridge.QqMusicDesktopQuickLoginFailure.rejected =>
    DesktopQuickLoginFailure.rejected,
  bridge.QqMusicDesktopQuickLoginFailure.cancelled =>
    DesktopQuickLoginFailure.cancelled,
  bridge.QqMusicDesktopQuickLoginFailure.replaced =>
    DesktopQuickLoginFailure.replaced,
  bridge.QqMusicDesktopQuickLoginFailure.sessionFinished =>
    DesktopQuickLoginFailure.sessionFinished,
  bridge.QqMusicDesktopQuickLoginFailure.alreadyRunning =>
    DesktopQuickLoginFailure.alreadyRunning,
};

class _OfficialWebOnlyLegacyStartOperation implements LoginStartOperation {
  const _OfficialWebOnlyLegacyStartOperation();

  @override
  bool cancel() => false;

  @override
  Future<LoginStart> run() async =>
      const LoginStart(failure: LoginFailure.rejected);
}

class _RustLoginStartOperation implements LoginStartOperation {
  const _RustLoginStartOperation(this._attemptId, this._channel);

  final int _attemptId;
  final LoginQrChannel _channel;

  @override
  bool cancel() => bridge.cancelQqMusicQrLoginStart(attemptId: _attemptId);

  @override
  Future<LoginStart> run() async {
    final outcome = await bridge.startQqMusicQrLogin(
      attemptId: _attemptId,
      channel: switch (_channel) {
        LoginQrChannel.qq => bridge.QqMusicQrLoginChannel.qq,
        LoginQrChannel.wechat => bridge.QqMusicQrLoginChannel.wechat,
      },
    );
    final session = outcome.session;
    final challenge = outcome.challenge;
    final failure = outcome.failure;

    if (session == null || challenge == null) {
      return LoginStart(
        failure: failure == null
            ? LoginFailure.invalidResponse
            : _mapFailure(failure),
      );
    }

    return LoginStart(
      session: _RustLoginSession(session),
      challenge: LoginChallenge(
        imageFormat: switch (challenge.imageFormat) {
          bridge.QqMusicQrImageFormat.png => LoginImageFormat.png,
          bridge.QqMusicQrImageFormat.jpeg => LoginImageFormat.jpeg,
        },
        imageBytes: challenge.imageBytes,
      ),
    );
  }
}

class _RustLoginSession implements LoginSession {
  const _RustLoginSession(this._inner);

  final bridge.QqMusicQrLoginSessionHandle _inner;

  @override
  bool cancel() => _inner.cancel();

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<LoginUpdate> advance() async {
    final update = await _inner.advance();
    return LoginUpdate(
      progress: update.state == null ? null : _mapProgress(update.state!),
      failure: update.failure == null ? null : _mapFailure(update.failure!),
      sessionActive: update.sessionActive,
    );
  }
}

LoginProgress _mapProgress(bridge.QqMusicQrLoginState state) => switch (state) {
  bridge.QqMusicQrLoginState.waitingForScan => LoginProgress.waitingForScan,
  bridge.QqMusicQrLoginState.scannedAwaitingConfirmation =>
    LoginProgress.scannedAwaitingConfirmation,
  bridge.QqMusicQrLoginState.authenticated => LoginProgress.authenticated,
  bridge.QqMusicQrLoginState.expired => LoginProgress.expired,
  bridge.QqMusicQrLoginState.refused => LoginProgress.refused,
  bridge.QqMusicQrLoginState.timedOut => LoginProgress.timedOut,
};

LoginFailure _mapFailure(
  bridge.QqMusicQrLoginFailure failure,
) => switch (failure) {
  bridge.QqMusicQrLoginFailure.coreUnavailable => LoginFailure.coreUnavailable,
  bridge.QqMusicQrLoginFailure.network => LoginFailure.network,
  bridge.QqMusicQrLoginFailure.serviceUnavailable =>
    LoginFailure.serviceUnavailable,
  bridge.QqMusicQrLoginFailure.invalidResponse => LoginFailure.invalidResponse,
  bridge.QqMusicQrLoginFailure.rejected => LoginFailure.rejected,
  bridge.QqMusicQrLoginFailure.cancelled => LoginFailure.cancelled,
  bridge.QqMusicQrLoginFailure.replaced => LoginFailure.replaced,
  bridge.QqMusicQrLoginFailure.sessionClosed => LoginFailure.sessionClosed,
  bridge.QqMusicQrLoginFailure.sessionFinished => LoginFailure.sessionFinished,
  bridge.QqMusicQrLoginFailure.timedOut => LoginFailure.timedOut,
  bridge.QqMusicQrLoginFailure.tooManyNetworkFailures =>
    LoginFailure.tooManyNetworkFailures,
  bridge.QqMusicQrLoginFailure.advanceAlreadyInProgress =>
    LoginFailure.advanceAlreadyInProgress,
  bridge.QqMusicQrLoginFailure.securityVerificationRequired =>
    LoginFailure.securityVerificationRequired,
  bridge.QqMusicQrLoginFailure.secondaryVerificationRequired =>
    LoginFailure.secondaryVerificationRequired,
};
