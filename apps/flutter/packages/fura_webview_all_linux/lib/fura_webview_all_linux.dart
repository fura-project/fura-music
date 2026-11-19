import 'package:webview_platform_interface/webview_platform_interface.dart';

/// Linux official login uses the system browser. Keep embedded WebViews
/// unsupported, using the platform interface's throwing factory defaults.
class FuraLinuxWebViewPlatform extends WebViewPlatform {
  static void registerWith() {
    WebViewPlatform.instance = FuraLinuxWebViewPlatform();
  }
}
