import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  test('reports unavailable without creating or clearing a session', () async {
    final runtime = _FakeOfficialWebRuntime(isSupported: false);
    final broker = PlatformNeteaseOfficialWebLoginBroker(runtime: runtime);

    await expectLater(
      broker.authenticate(),
      throwsA(
        isA<OfficialWebLoginException>().having(
          (error) => error.failure,
          'failure',
          OfficialWebLoginFailure.unavailable,
        ),
      ),
    );
    expect(runtime.clearCalls, 0);
    expect(runtime.sessions, isEmpty);
  });

  test('allows only the bounded NetEase HTTPS top-level origins', () {
    expect(
      isAllowedNeteaseOfficialNavigation('https://music.163.com/#/login'),
      isTrue,
    );
    expect(isAllowedNeteaseOfficialNavigation('about:blank'), isTrue);
    expect(
      isAllowedNeteaseOfficialNavigation('https://y.music.163.com/m/login'),
      isTrue,
    );
    expect(
      isAllowedNeteaseOfficialNavigation('http://music.163.com/#/login'),
      isFalse,
    );
    expect(
      isAllowedNeteaseOfficialNavigation('https://evil.y.music.163.com/login'),
      isFalse,
    );
    expect(
      isAllowedNeteaseOfficialNavigation('https://evil.example/login'),
      isFalse,
    );
    expect(
      isAllowedNeteaseOfficialNavigation(
        'https://music.163.com.evil.example/login',
      ),
      isFalse,
    );
    expect(
      isAllowedNeteaseOfficialNavigation('https://user@music.163.com/login'),
      isFalse,
    );
    expect(
      isAllowedNeteaseOfficialNavigation('https://music.163.com:8443/login'),
      isFalse,
    );
  });

  test('accepts WebView2 known cleanup limits only on Windows', () {
    final result = WebViewDataClearingResult(
      clearedDataTypes: const {
        WebViewDataType.cookies,
        WebViewDataType.cache,
        WebViewDataType.localStorage,
        WebViewDataType.indexedDb,
        WebViewDataType.webSql,
        WebViewDataType.cacheStorage,
      },
      unsupportedDataTypes: const {
        WebViewDataType.sessionStorage,
        WebViewDataType.serviceWorkers,
      },
    );

    expect(
      isOfficialLoginWebsiteDataCleared(
        result,
        platform: TargetPlatform.windows,
      ),
      isTrue,
    );
    expect(
      isOfficialLoginWebsiteDataCleared(
        result,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
  });

  test('does not hide WebView2 clearing failures or missing categories', () {
    final failed = WebViewDataClearingResult(
      clearedDataTypes: const {
        WebViewDataType.cache,
        WebViewDataType.localStorage,
        WebViewDataType.indexedDb,
        WebViewDataType.webSql,
        WebViewDataType.cacheStorage,
      },
      unsupportedDataTypes: const {
        WebViewDataType.sessionStorage,
        WebViewDataType.serviceWorkers,
      },
      failures: const {WebViewDataType.cookies: 'native failure'},
    );

    expect(
      isOfficialLoginWebsiteDataCleared(
        failed,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });

  test(
    'returns only bounded MUSIC_U and csrf candidate after cleanup',
    () async {
      final runtime = _FakeOfficialWebRuntime(
        cookieResults: [
          const [
            OfficialWebCookie(name: 'unrelated', value: 'not-exported'),
            OfficialWebCookie(name: '__csrf', value: 'csrf-value'),
            OfficialWebCookie(name: 'MUSIC_U', value: 'music-value'),
          ],
        ],
      );
      final broker = PlatformNeteaseOfficialWebLoginBroker(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 1),
      );

      final result = await broker.authenticate();

      expect(utf8.decode(result!), 'MUSIC_U=music-value; __csrf=csrf-value');
      expect(runtime.clearCalls, 2);
      expect(runtime.sessions, hasLength(1));
      expect(runtime.sessions.single.closed, isTrue);
      expect(
        runtime.readUris,
        everyElement(Uri.parse(neteaseOfficialLoginUri)),
      );
      expect(broker.presentationStage, OfficialWebLoginPresentationStage.idle);
      expect(broker.activeView, isNull);
      result.fillRange(0, result.length, 0);
    },
  );

  test('visible presentation exists only while the attempt owns it', () async {
    final pendingCookies = Completer<List<OfficialWebCookie>>();
    final runtime = _FakeOfficialWebRuntime(
      cookieResults: [pendingCookies.future],
    );
    final broker = PlatformNeteaseOfficialWebLoginBroker(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 1),
    );

    final attempt = broker.authenticate();
    await runtime.firstRead;
    expect(
      broker.presentationStage,
      OfficialWebLoginPresentationStage.waitingForSignIn,
    );
    expect(broker.activeView, same(runtime.sessions.single.view));

    pendingCookies.complete(const [
      OfficialWebCookie(name: 'MUSIC_U', value: 'candidate'),
    ]);
    final result = await attempt;
    expect(utf8.decode(result!), 'MUSIC_U=candidate');
    expect(broker.activeView, isNull);
    result.fillRange(0, result.length, 0);
  });

  test(
    'cancel closes, clears, and suppresses a late cookie callback',
    () async {
      final pendingCookies = Completer<List<OfficialWebCookie>>();
      final runtime = _FakeOfficialWebRuntime(
        cookieResults: [pendingCookies.future],
      );
      final broker = PlatformNeteaseOfficialWebLoginBroker(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 1),
      );

      final attempt = broker.authenticate();
      await runtime.firstRead;
      expect(broker.cancel(), isTrue);
      expect(broker.activeView, isNull);
      pendingCookies.complete(const [
        OfficialWebCookie(name: 'MUSIC_U', value: 'late-secret'),
      ]);

      expect(await attempt, isNull);
      expect(runtime.sessions.single.closed, isTrue);
      expect(runtime.clearCalls, 2);
      expect(broker.cancel(), isFalse);
    },
  );

  test('a replacement waits for cancelled cleanup before opening', () async {
    final firstCookies = Completer<List<OfficialWebCookie>>();
    final runtime = _FakeOfficialWebRuntime(
      cookieResults: [
        firstCookies.future,
        const [OfficialWebCookie(name: 'MUSIC_U', value: 'replacement')],
      ],
    );
    final broker = PlatformNeteaseOfficialWebLoginBroker(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 1),
    );

    final first = broker.authenticate();
    await runtime.firstRead;
    final second = broker.authenticate();
    await Future<void>.delayed(Duration.zero);
    expect(runtime.sessions, hasLength(1));

    firstCookies.complete(const []);
    expect(await first, isNull);
    final candidate = await second;
    expect(utf8.decode(candidate!), 'MUSIC_U=replacement');
    expect(runtime.sessions, hasLength(2));
    expect(runtime.sessions, everyElement(isA<_FakeOfficialWebSession>()));
    expect(runtime.sessions.every((session) => session.closed), isTrue);
    candidate.fillRange(0, candidate.length, 0);
  });

  test('conflicting or malformed candidates are rejected', () async {
    for (final cookies in <List<OfficialWebCookie>>[
      const [
        OfficialWebCookie(name: 'MUSIC_U', value: 'one'),
        OfficialWebCookie(name: 'MUSIC_U', value: 'two'),
      ],
      const [OfficialWebCookie(name: 'MUSIC_U', value: 'bad;value')],
      [
        OfficialWebCookie(
          name: 'MUSIC_U',
          value: List.filled(4097, 'x').join(),
        ),
      ],
    ]) {
      final runtime = _FakeOfficialWebRuntime(cookieResults: [cookies]);
      final broker = PlatformNeteaseOfficialWebLoginBroker(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 1),
      );

      await expectLater(
        broker.authenticate(),
        throwsA(
          isA<OfficialWebLoginException>().having(
            (error) => error.failure,
            'failure',
            OfficialWebLoginFailure.invalidCredential,
          ),
        ),
      );
      expect(runtime.sessions.single.closed, isTrue);
      expect(runtime.clearCalls, 2);
    }
  });

  test('cleanup failure is terminal and does not return a candidate', () async {
    final runtime = _FakeOfficialWebRuntime(
      clearResults: [true, false],
      cookieResults: [
        const [OfficialWebCookie(name: 'MUSIC_U', value: 'candidate')],
      ],
    );
    final broker = PlatformNeteaseOfficialWebLoginBroker(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 1),
    );

    await expectLater(
      broker.authenticate(),
      throwsA(
        isA<OfficialWebLoginException>().having(
          (error) => error.failure,
          'failure',
          OfficialWebLoginFailure.cleanupFailed,
        ),
      ),
    );
    expect(runtime.sessions.single.closed, isTrue);
  });

  test('attempt timeout is typed and closes browser state', () async {
    final runtime = _FakeOfficialWebRuntime();
    final broker = PlatformNeteaseOfficialWebLoginBroker(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 1),
      attemptTimeout: const Duration(milliseconds: 8),
    );

    await expectLater(
      broker.authenticate(),
      throwsA(
        isA<OfficialWebLoginException>().having(
          (error) => error.failure,
          'failure',
          OfficialWebLoginFailure.timedOut,
        ),
      ),
    );
    expect(runtime.sessions.single.closed, isTrue);
    expect(runtime.clearCalls, 2);
  });

  test(
    'explicit website cleanup cancels an attempt and clears again',
    () async {
      final pendingCookies = Completer<List<OfficialWebCookie>>();
      final runtime = _FakeOfficialWebRuntime(
        cookieResults: [pendingCookies.future],
      );
      final broker = PlatformNeteaseOfficialWebLoginBroker(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 1),
      );

      final attempt = broker.authenticate();
      await runtime.firstRead;
      final cleanup = broker.clearWebsiteData();
      pendingCookies.complete(const []);

      expect(await attempt, isNull);
      expect(await cleanup, isTrue);
      expect(runtime.clearCalls, 3);
    },
  );
}

class _FakeOfficialWebRuntime implements OfficialWebRuntime {
  _FakeOfficialWebRuntime({
    this.isSupported = true,
    List<bool> clearResults = const [],
    List<FutureOr<List<OfficialWebCookie>>> cookieResults = const [],
  }) : _clearResults = List.of(clearResults),
       _cookieResults = List.of(cookieResults);

  @override
  final bool isSupported;
  final List<bool> _clearResults;
  final List<FutureOr<List<OfficialWebCookie>>> _cookieResults;
  final List<_FakeOfficialWebSession> sessions = [];
  final List<Uri> readUris = [];
  final Completer<void> _firstRead = Completer<void>();
  int clearCalls = 0;

  Future<void> get firstRead => _firstRead.future;

  @override
  Future<bool> clearAllWebsiteData() async {
    clearCalls += 1;
    return _clearResults.isEmpty ? true : _clearResults.removeAt(0);
  }

  @override
  Future<OfficialWebViewSession> createSession({
    required VoidCallback onPageEvent,
    required VoidCallback onMainFrameFailure,
  }) async {
    final session = _FakeOfficialWebSession(
      onPageEvent: onPageEvent,
      onMainFrameFailure: onMainFrameFailure,
    );
    sessions.add(session);
    return session;
  }

  @override
  Future<List<OfficialWebCookie>> readCookies(Uri uri) async {
    readUris.add(uri);
    if (!_firstRead.isCompleted) _firstRead.complete();
    if (_cookieResults.isEmpty) return const [];
    return _cookieResults.removeAt(0);
  }
}

class _FakeOfficialWebSession implements OfficialWebViewSession {
  _FakeOfficialWebSession({
    required this.onPageEvent,
    required this.onMainFrameFailure,
  });

  final VoidCallback onPageEvent;
  final VoidCallback onMainFrameFailure;
  @override
  final Widget view = const SizedBox(key: ValueKey('fake-webview'));
  Uri? loadedUri;
  bool closed = false;

  @override
  Future<void> load(Uri uri) async {
    loadedUri = uri;
    onPageEvent();
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
