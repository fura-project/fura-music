import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

const _probeCookieName = 'fura_webview_probe';
const _probeCookieValue = 'synthetic';
const _officialLoginUri = 'https://music.163.com/#/login';
const _runOfficialPageProbe = bool.fromEnvironment(
  'FURA_LIVE_NETEASE_WEBVIEW_PROBE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Uri probeUri;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    probeUri = Uri.parse('http://127.0.0.1:${server.port}/probe');
    server.listen((request) async {
      if (request.uri.path != '/probe') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.cookies.add(
        Cookie(_probeCookieName, _probeCookieValue)
          ..httpOnly = true
          ..sameSite = SameSite.lax
          ..path = '/',
      );
      request.response.headers.contentType = ContentType.html;
      request.response.write('''<!doctype html>
<html>
  <head><title>Fura WebView lifecycle probe</title></head>
  <body style="min-height: 1600px">
    <label for="probe-input">Probe</label>
    <input id="probe-input" value="ready">
    <script>
      window.furaProbe = () => JSON.stringify({
        value: document.getElementById('probe-input').value,
        scrollY: window.scrollY,
        ready: document.readyState,
      });
    </script>
  </body>
</html>''');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  testWidgets(
    'native cookie API observes HttpOnly data and website cleanup removes it',
    (tester) async {
      final dataManager = WebViewDataManager();
      final cookieManager = WebViewCookieManager();
      final initialClear = await dataManager.clearAllWebsiteData();
      expect(initialClear.isComplete, isTrue);

      final mounted = await _mountLoadedSession(tester, probeUri);
      addTearDown(() async {
        await _unmountAndClose(tester, mounted.session);
        await dataManager.clearAllWebsiteData();
      });

      final javaScriptCookie = await mounted.controller
          .runJavaScriptReturningResult('document.cookie');
      expect('$javaScriptCookie', isNot(contains(_probeCookieName)));

      final nativeCookies = await cookieManager.getCookies(domain: probeUri);
      expect(
        nativeCookies,
        contains(
          isA<WebViewCookie>()
              .having((cookie) => cookie.name, 'name', _probeCookieName)
              .having((cookie) => cookie.value, 'value', _probeCookieValue),
        ),
      );

      final clear = await dataManager.clearAllWebsiteData();
      expect(clear.isComplete, isTrue);
      final afterClear = await cookieManager.getCookies(domain: probeUri);
      expect(
        afterClear.where((cookie) => cookie.name == _probeCookieName),
        isEmpty,
      );
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'fifty visible create load resize interact close cycles complete',
    (tester) async {
      final dataManager = WebViewDataManager();
      expect((await dataManager.clearAllWebsiteData()).isComplete, isTrue);

      for (var cycle = 0; cycle < 50; cycle += 1) {
        final mounted = await _mountLoadedSession(
          tester,
          probeUri.replace(queryParameters: {'cycle': '$cycle'}),
          width: cycle.isEven ? 720 : 540,
          height: cycle.isEven ? 440 : 360,
        );
        await mounted.controller.runJavaScript('''
          document.getElementById('probe-input').value = 'cycle-$cycle';
          window.scrollTo(0, 240);
        ''');
        final state = await mounted.controller.runJavaScriptReturningResult(
          'window.furaProbe()',
        );
        expect('$state', contains('cycle-$cycle'));
        expect('$state', contains('240'));

        await _pumpWebView(
          tester,
          mounted.controller,
          width: cycle.isEven ? 540 : 720,
          height: cycle.isEven ? 360 : 440,
        );
        await _unmountAndClose(tester, mounted.session);
      }

      expect((await dataManager.clearAllWebsiteData()).isComplete, isTrue);
    },
    skip: !Platform.isLinux,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'official NetEase login page renders without performing account login',
    (tester) async {
      final dataManager = WebViewDataManager();
      expect((await dataManager.clearAllWebsiteData()).isComplete, isTrue);
      final mounted = await _mountLoadedSession(
        tester,
        Uri.parse(_officialLoginUri),
        width: 960,
        height: 640,
        loadTimeout: const Duration(seconds: 60),
        acceptInteractiveDocument: true,
      );
      addTearDown(() async {
        await _unmountAndClose(tester, mounted.session);
        await dataManager.clearAllWebsiteData();
      });

      final current = await mounted.controller.currentUrl();
      expect(current, isNotNull);
      expect(Uri.parse(current!).scheme, 'https');
      expect(Uri.parse(current).host, 'music.163.com');
      final readyState = await mounted.controller.runJavaScriptReturningResult(
        'document.readyState',
      );
      expect('$readyState', contains('complete'));
    },
    skip: !Platform.isLinux || !_runOfficialPageProbe,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<_MountedSession> _mountLoadedSession(
  WidgetTester tester,
  Uri uri, {
  double width = 720,
  double height = 440,
  Duration loadTimeout = const Duration(seconds: 20),
  bool acceptInteractiveDocument = false,
}) async {
  final session = await OffscreenWebViewSession.create();
  final controller = session.controller;
  final pageFinished = Completer<void>();
  try {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final target = Uri.tryParse(request.url);
          if (!request.isMainFrame ||
              target != null &&
                  ((target.scheme == 'http' &&
                          target.host ==
                              InternetAddress.loopbackIPv4.address) ||
                      (target.scheme == 'https' &&
                          target.host == 'music.163.com'))) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) pageFinished.complete();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && !pageFinished.isCompleted) {
            pageFinished.completeError(
              StateError('main-frame WebView load failed: ${error.errorType}'),
            );
          }
        },
      ),
    );
    await _pumpWebView(tester, controller, width: width, height: height);
    await controller.loadRequest(uri);
    if (acceptInteractiveDocument) {
      await _waitForInteractiveDocument(
        tester,
        controller,
        pageFinished,
        loadTimeout,
      );
    } else {
      await pageFinished.future.timeout(loadTimeout);
    }
    await tester.pump(const Duration(milliseconds: 100));
    return _MountedSession(session, controller);
  } catch (_) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await session.close();
    rethrow;
  }
}

Future<void> _waitForInteractiveDocument(
  WidgetTester tester,
  WebViewController controller,
  Completer<void> pageFinished,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    if (pageFinished.isCompleted) {
      await pageFinished.future;
      return;
    }
    try {
      final result = await controller.runJavaScriptReturningResult(
        'document.readyState',
      );
      final state = '$result'.replaceAll('"', '');
      if (state == 'interactive' || state == 'complete') return;
    } on Object catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    'WebView document did not become interactive; '
    'last error type: ${lastError?.runtimeType ?? 'none'}',
    timeout,
  );
}

Future<void> _pumpWebView(
  WidgetTester tester,
  WebViewController controller, {
  required double width,
  required double height,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: WebViewWidget(controller: controller),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmountAndClose(
  WidgetTester tester,
  OffscreenWebViewSession session,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await session.close().timeout(const Duration(seconds: 10));
}

class _MountedSession {
  const _MountedSession(this.session, this.controller);

  final OffscreenWebViewSession session;
  final WebViewController controller;
}
