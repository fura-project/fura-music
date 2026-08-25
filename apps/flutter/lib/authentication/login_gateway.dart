import 'dart:typed_data';

import 'package:flutterustmusic/src/rust/api/authentication.dart' as bridge;

enum LoginImageFormat { png, jpeg }

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
}

class LoginChallenge {
  const LoginChallenge({required this.imageFormat, required this.imageBytes});

  final LoginImageFormat imageFormat;
  final Uint8List imageBytes;
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

abstract interface class QqMusicAuthenticationGateway {
  LoginStartOperation beginStart();
  bool get hasAuthenticatedCredential;
}

abstract interface class LoginStartOperation {
  Future<LoginStart> run();
  bool cancel();
}

class RustQqMusicAuthenticationGateway implements QqMusicAuthenticationGateway {
  const RustQqMusicAuthenticationGateway();

  @override
  bool get hasAuthenticatedCredential =>
      bridge.qqMusicHasAuthenticatedCredential();

  @override
  LoginStartOperation beginStart() =>
      _RustLoginStartOperation(bridge.reserveQqMusicWechatQrLoginStart());
}

class _RustLoginStartOperation implements LoginStartOperation {
  const _RustLoginStartOperation(this._attemptId);

  final int _attemptId;

  @override
  bool cancel() =>
      bridge.cancelQqMusicWechatQrLoginStart(attemptId: _attemptId);

  @override
  Future<LoginStart> run() async {
    final outcome = await bridge.startQqMusicWechatQrLogin(
      attemptId: _attemptId,
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
};
