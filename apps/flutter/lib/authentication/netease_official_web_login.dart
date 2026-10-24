import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_all/webview_all.dart';

import 'netease_web_refresh_diagnostics.dart';

const neteaseOfficialLoginUri = 'https://music.163.com/#/login';

enum OfficialWebLoginFailure {
  unavailable,
  alreadyRunning,
  invalidCredential,
  timedOut,
  cleanupFailed,
  failed,
}

enum OfficialWebLoginPresentationStage {
  idle,
  preparing,
  waitingForSignIn,
  finishing,
}

class OfficialWebLoginException implements Exception {
  const OfficialWebLoginException(this.failure);

  final OfficialWebLoginFailure failure;

  @override
  String toString() => 'OfficialWebLoginException(${failure.name})';
}

/// Native cookie value observed by the browser runtime.
///
/// Values are deliberately kept local to one broker attempt. Callers must not
/// retain or log them.
class OfficialWebCookie {
  const OfficialWebCookie({
    required this.name,
    required this.value,
    this.domain = 'music.163.com',
  });

  final String name;
  final String value;
  final String domain;

  @override
  String toString() => 'OfficialWebCookie([REDACTED])';
}

/// A visible WebView session owned by one official-login attempt.
abstract interface class OfficialWebViewSession {
  Widget get view;
  Future<void> load(Uri uri);
  Future<void> close();
}

/// Small runtime seam used by deterministic unit tests.
abstract interface class OfficialWebRuntime {
  bool get isSupported;

  Future<bool> clearAllWebsiteData();

  Future<OfficialWebViewSession> createSession({
    required VoidCallback onPageEvent,
    required VoidCallback onMainFrameFailure,
  });

  Future<List<OfficialWebCookie>> readCookies(Uri uri);
}

/// Produces a short-lived, minimal NetEase browser credential candidate.
///
/// Observing MUSIC_U is not authentication. The gateway immediately stages
/// the returned bytes in Rust, verifies the account through the existing
/// account-summary path, and only then writes the existing provider vault.
abstract interface class OfficialWebLoginBroker {
  bool get isSupported;
  Listenable get presentationListenable;
  OfficialWebLoginPresentationStage get presentationStage;
  Widget? get activeView;

  Future<Uint8List?> authenticate();
  bool cancel();
  Future<bool> clearWebsiteData();
}

class PlatformNeteaseOfficialWebLoginBroker extends ChangeNotifier
    implements OfficialWebLoginBroker {
  static const _runtimeOperationTimeout = Duration(seconds: 15);
  static const _sessionCreationTimeout = Duration(seconds: 30);
  static const _sessionCloseTimeout = Duration(seconds: 10);

  PlatformNeteaseOfficialWebLoginBroker({
    OfficialWebRuntime? runtime,
    this._pollInterval = const Duration(seconds: 1),
    this._attemptTimeout = const Duration(minutes: 5),
    this.diagnostics = const NeteaseWebRefreshDiagnostics(),
  }) : _runtime = runtime ?? WebViewAllOfficialWebRuntime();

  final OfficialWebRuntime _runtime;
  final Duration _pollInterval;
  final Duration _attemptTimeout;
  final NeteaseWebRefreshDiagnostics diagnostics;

  OfficialWebLoginPresentationStage _presentationStage =
      OfficialWebLoginPresentationStage.idle;
  Widget? _activeView;
  bool _active = false;
  int _generation = 0;
  Completer<void>? _wake;
  Future<void>? _attemptDone;

  @override
  bool get isSupported => _runtime.isSupported;

  @override
  Listenable get presentationListenable => this;

  @override
  OfficialWebLoginPresentationStage get presentationStage => _presentationStage;

  @override
  Widget? get activeView => _activeView;

  @override
  Future<Uint8List?> authenticate() async {
    final previousAttempt = _attemptDone;
    if (_active) cancel();
    if (previousAttempt != null) await previousAttempt;
    if (!isSupported) {
      throw const OfficialWebLoginException(
        OfficialWebLoginFailure.unavailable,
      );
    }

    final generation = ++_generation;
    final done = Completer<void>();
    final attemptDone = done.future;
    _attemptDone = attemptDone;
    _active = true;
    _setPresentation(
      stage: OfficialWebLoginPresentationStage.preparing,
      view: null,
    );

    OfficialWebViewSession? session;
    Uint8List? candidate;
    OfficialWebLoginFailure? terminalFailure;
    var cleanupSucceeded = true;
    final deadline = DateTime.now().add(_attemptTimeout);
    _wake = Completer<void>();

    try {
      if (!await _runtime.clearAllWebsiteData().timeout(
        _runtimeOperationTimeout,
      )) {
        terminalFailure = OfficialWebLoginFailure.cleanupFailed;
      } else if (_isCurrent(generation)) {
        session = await _runtime
            .createSession(
              onPageEvent: () => _wakeAttempt(generation),
              onMainFrameFailure: () {
                if (_isCurrent(generation)) {
                  terminalFailure = OfficialWebLoginFailure.failed;
                  _wakeAttempt(generation);
                }
              },
            )
            .timeout(_sessionCreationTimeout);
        if (_isCurrent(generation)) {
          _setPresentation(
            stage: OfficialWebLoginPresentationStage.waitingForSignIn,
            view: session.view,
          );
          await session
              .load(Uri.parse(neteaseOfficialLoginUri))
              .timeout(_runtimeOperationTimeout);
          _wakeAttempt(generation);
        }
      }

      while (_isCurrent(generation) && terminalFailure == null) {
        if (!DateTime.now().isBefore(deadline)) {
          terminalFailure = OfficialWebLoginFailure.timedOut;
          break;
        }
        final wake = _wake ??= Completer<void>();
        final remaining = deadline.difference(DateTime.now());
        final delay = remaining < _pollInterval ? remaining : _pollInterval;
        await Future.any<void>([wake.future, Future<void>.delayed(delay)]);
        if (identical(_wake, wake)) _wake = null;
        if (!_isCurrent(generation) || terminalFailure != null) break;

        final cookies = await _runtime
            .readCookies(Uri.parse(neteaseOfficialLoginUri))
            .timeout(_runtimeOperationTimeout);
        if (!_isCurrent(generation)) break;
        try {
          candidate = _minimalCredentialCandidate(cookies);
          _reportCapture(cookies, candidate != null);
        } on OfficialWebLoginException {
          _reportCapture(cookies, false);
          rethrow;
        }
        if (candidate != null) {
          _setPresentation(
            stage: OfficialWebLoginPresentationStage.finishing,
            view: null,
          );
          break;
        }
      }
    } on OfficialWebLoginException catch (error) {
      terminalFailure = error.failure;
    } on Object {
      terminalFailure = OfficialWebLoginFailure.failed;
    } finally {
      _activeView = null;
      notifyListeners();
      if (session != null) {
        try {
          await session.close().timeout(_sessionCloseTimeout);
        } on Object {
          cleanupSucceeded = false;
        }
      }
      try {
        cleanupSucceeded =
            await _runtime.clearAllWebsiteData().timeout(
              _runtimeOperationTimeout,
            ) &&
            cleanupSucceeded;
      } on Object {
        cleanupSucceeded = false;
      }
      if (_isCurrent(generation)) {
        _active = false;
        _wake = null;
        _setPresentation(
          stage: OfficialWebLoginPresentationStage.idle,
          view: null,
        );
      }
      if (!done.isCompleted) done.complete();
      if (identical(_attemptDone, attemptDone)) _attemptDone = null;
    }

    if (!cleanupSucceeded) {
      candidate?.fillRange(0, candidate.length, 0);
      throw const OfficialWebLoginException(
        OfficialWebLoginFailure.cleanupFailed,
      );
    }
    if (generation != _generation) {
      candidate?.fillRange(0, candidate.length, 0);
      return null;
    }
    final failure = terminalFailure;
    if (failure != null) {
      candidate?.fillRange(0, candidate.length, 0);
      throw OfficialWebLoginException(failure);
    }
    return candidate;
  }

  @override
  bool cancel() {
    if (!_active) return false;
    ++_generation;
    _active = false;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _setPresentation(stage: OfficialWebLoginPresentationStage.idle, view: null);
    return true;
  }

  @override
  Future<bool> clearWebsiteData() async {
    final previousAttempt = _attemptDone;
    cancel();
    if (previousAttempt != null) await previousAttempt;
    try {
      return await _runtime.clearAllWebsiteData().timeout(
        _runtimeOperationTimeout,
      );
    } on Object {
      return false;
    }
  }

  bool _isCurrent(int generation) => _active && generation == _generation;

  void _reportCapture(List<OfficialWebCookie> cookies, bool valid) {
    bool observed(String name) => cookies.any(
      (cookie) =>
          _allowedCookieDomain(cookie.domain) &&
          cookie.name == name &&
          cookie.value.isNotEmpty,
    );
    diagnostics.capture(
      musicU: observed('MUSIC_U'),
      musicRU: observed('MUSIC_R_U'),
      csrf: observed('__csrf'),
      structurallyValid: valid,
    );
  }

  void _wakeAttempt(int generation) {
    if (!_isCurrent(generation)) return;
    final wake = _wake ??= Completer<void>();
    if (!wake.isCompleted) wake.complete();
  }

  void _setPresentation({
    required OfficialWebLoginPresentationStage stage,
    required Widget? view,
  }) {
    _presentationStage = stage;
    _activeView = view;
    notifyListeners();
  }
}

class WebViewAllOfficialWebRuntime implements OfficialWebRuntime {
  WebViewAllOfficialWebRuntime({
    WebViewDataManager? dataManager,
    WebViewCookieManager? cookieManager,
  }) : _providedDataManager = dataManager,
       _providedCookieManager = cookieManager;

  final WebViewDataManager? _providedDataManager;
  final WebViewCookieManager? _providedCookieManager;

  WebViewDataManager get _dataManager =>
      _providedDataManager ?? WebViewDataManager();
  WebViewCookieManager get _cookieManager =>
      _providedCookieManager ?? WebViewCookieManager();

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    final supportedPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia => false,
    };
    return supportedPlatform &&
        WebViewPlatform.instance?.supportsOffscreenWebViews == true;
  }

  @override
  Future<bool> clearAllWebsiteData() async => isOfficialLoginWebsiteDataCleared(
    await _dataManager.clearAllWebsiteData(),
    platform: defaultTargetPlatform,
  );

  @override
  Future<OfficialWebViewSession> createSession({
    required VoidCallback onPageEvent,
    required VoidCallback onMainFrameFailure,
  }) async {
    final owned = await OffscreenWebViewSession.create(
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    final controller = owned.controller;
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame ||
                isAllowedNeteaseOfficialNavigation(request.url)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) => onPageEvent(),
          onPageFinished: (_) => onPageEvent(),
          onUrlChange: (_) => onPageEvent(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) onMainFrameFailure();
          },
          onSslAuthError: (error) {
            unawaited(error.cancel());
            onMainFrameFailure();
          },
        ),
      );
      return _WebViewAllOfficialWebSession(owned, controller);
    } on Object {
      await owned.close();
      rethrow;
    }
  }

  @override
  Future<List<OfficialWebCookie>> readCookies(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.host != 'music.163.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      throw const OfficialWebLoginException(
        OfficialWebLoginFailure.invalidCredential,
      );
    }
    final cookies = await _cookieManager.getCookies(domain: uri);
    return cookies
        .where(
          (cookie) =>
              _allowedCookieDomain(cookie.domain) &&
              const {'MUSIC_U', 'MUSIC_R_U', '__csrf'}.contains(cookie.name),
        )
        .map(
          (cookie) => OfficialWebCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
          ),
        )
        .toList(growable: false);
  }
}

class _WebViewAllOfficialWebSession implements OfficialWebViewSession {
  _WebViewAllOfficialWebSession(this._owned, this._controller)
    : _view = WebViewWidget(controller: _controller);

  final OffscreenWebViewSession _owned;
  final WebViewController _controller;
  final Widget _view;

  @override
  Widget get view => _view;

  @override
  Future<void> load(Uri uri) => _controller.loadRequest(uri);

  @override
  Future<void> close() async {
    final detached = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!detached.isCompleted) detached.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    await detached.future.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () {},
    );
    await _owned.close();
  }
}

bool isAllowedNeteaseOfficialNavigation(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return false;
  if (uri.scheme == 'about' && uri.path == 'blank') return true;
  const allowedHosts = <String>{'music.163.com', 'y.music.163.com'};
  return uri.scheme == 'https' &&
      allowedHosts.contains(uri.host) &&
      !uri.hasPort &&
      uri.userInfo.isEmpty;
}

/// Whether clearing the WebView store is sufficient for a short-lived login.
///
/// WebView2 reports session storage and service-worker registration as
/// unsupported even after it successfully clears every cookie and persistent
/// web storage/cache category. Session storage is destroyed with the owned
/// WebView session. No other unsupported category or native clearing failure
/// is accepted.
bool isOfficialLoginWebsiteDataCleared(
  WebViewDataClearingResult result, {
  required TargetPlatform platform,
}) {
  if (result.isComplete) return true;
  if (platform != TargetPlatform.windows || result.failures.isNotEmpty) {
    return false;
  }
  const webView2Unsupported = <WebViewDataType>{
    WebViewDataType.sessionStorage,
    WebViewDataType.serviceWorkers,
  };
  const requiredCleared = <WebViewDataType>{
    WebViewDataType.cookies,
    WebViewDataType.cache,
    WebViewDataType.localStorage,
    WebViewDataType.indexedDb,
    WebViewDataType.webSql,
    WebViewDataType.cacheStorage,
  };
  return webView2Unsupported.containsAll(result.unsupportedDataTypes) &&
      result.clearedDataTypes.containsAll(requiredCleared);
}

Uint8List? _minimalCredentialCandidate(List<OfficialWebCookie> cookies) {
  String? musicU;
  String? musicRU;
  String? csrf;
  for (final cookie in cookies) {
    if (!_allowedCookieDomain(cookie.domain)) continue;
    if (cookie.name == 'MUSIC_U') {
      if (musicU != null && musicU != cookie.value) {
        throw const OfficialWebLoginException(
          OfficialWebLoginFailure.invalidCredential,
        );
      }
      musicU = cookie.value;
    } else if (cookie.name == 'MUSIC_R_U') {
      if (musicRU != null && musicRU != cookie.value) {
        throw const OfficialWebLoginException(
          OfficialWebLoginFailure.invalidCredential,
        );
      }
      musicRU = cookie.value;
    } else if (cookie.name == '__csrf') {
      if (csrf != null && csrf != cookie.value) {
        throw const OfficialWebLoginException(
          OfficialWebLoginFailure.invalidCredential,
        );
      }
      csrf = cookie.value;
    }
  }
  if (musicU == null) return null;
  if (!_validCookieValue(musicU, maxLength: 4096) ||
      musicRU != null && !_validCookieValue(musicRU, maxLength: 4096) ||
      csrf != null && !_validCookieValue(csrf, maxLength: 256)) {
    throw const OfficialWebLoginException(
      OfficialWebLoginFailure.invalidCredential,
    );
  }
  final candidate = [
    'MUSIC_U=$musicU',
    if (musicRU != null) 'MUSIC_R_U=$musicRU',
    if (csrf != null) '__csrf=$csrf',
  ].join('; ');
  if (candidate.length > 8192) {
    throw const OfficialWebLoginException(
      OfficialWebLoginFailure.invalidCredential,
    );
  }
  return Uint8List.fromList(ascii.encode(candidate));
}

bool _allowedCookieDomain(String domain) =>
    domain == 'music.163.com' || domain == '.music.163.com';

bool _validCookieValue(String value, {required int maxLength}) {
  if (value.isEmpty || value.length > maxLength) return false;
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x21 ||
        codeUnit > 0x7e ||
        codeUnit == 0x22 ||
        codeUnit == 0x2c ||
        codeUnit == 0x3b ||
        codeUnit == 0x5c) {
      return false;
    }
  }
  return true;
}
