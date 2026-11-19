import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterustmusic/authentication/login_gateway.dart';
import 'package:flutterustmusic/authentication/netease_official_web_login.dart';
import 'package:flutterustmusic/src/rust/api/netease_authentication.dart';
import 'package:flutterustmusic/src/rust/frb_generated.dart';
import 'package:fura_webview_all_linux/fura_webview_all_linux.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux official login does not require embedded WebViews', (
    _,
  ) async {
    await RustLib.init();
    expect(WebViewPlatform.instance, isA<FuraLinuxWebViewPlatform>());
    expect(WebViewPlatform.instance!.supportsOffscreenWebViews, isFalse);
    expect(PlatformNeteaseOfficialWebLoginBroker().isSupported, isFalse);
    expect(WebViewController.new, throwsUnimplementedError);
    expect(WebViewCookieManager.new, throwsUnimplementedError);
    expect(WebViewDataManager.new, throwsUnimplementedError);
    await expectLater(OffscreenWebViewSession.create(), throwsUnsupportedError);

    // Use the production constructor with no injected broker. A native
    // reservation is local and is cancelled before any browser is launched.
    final gateway = RustNeteaseAuthenticationGateway();
    expect(
      gateway.supportsOfficialWebLogin,
      neteaseSystemBrowserLoginSupported(),
    );
    expect(gateway.officialWebLoginView, isNull);
    final attempt = gateway.beginOfficialWebLogin();
    expect(attempt.cancel(), isTrue);
    final outcome = await attempt.run();
    expect(outcome.authenticated, isFalse);
    expect(outcome.failure, OfficialWebAuthenticationFailure.cancelled);
    expect(gateway.officialWebLoginView, isNull);
  }, skip: !Platform.isLinux);
}
