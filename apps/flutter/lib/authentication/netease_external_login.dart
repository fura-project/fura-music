import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hands one active NetEase QR confirmation page to an external application.
///
/// The URI is the same short-lived secret encoded in the visible QR image. It
/// is deliberately never printed. The Rust-owned QR session keeps polling and
/// remains the only component allowed to accept the resulting credential.
Future<bool> openNeteaseQrConfirmationExternally(Uri uri) async {
  if (kIsWeb || !isAllowedNeteaseQrConfirmationUri(uri)) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

@visibleForTesting
bool isAllowedNeteaseQrConfirmationUri(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != 'music.163.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/st/platform/scanlogin' ||
      uri.fragment.isNotEmpty) {
    return false;
  }
  const allowedKeys = <String>{
    'codekey',
    'chainId',
    'hdw_device',
    'hdw_appid',
    'hitExp',
  };
  final queryKeys = uri.queryParametersAll.keys.toSet();
  if (queryKeys.difference(allowedKeys).isNotEmpty ||
      allowedKeys.difference(queryKeys).isNotEmpty ||
      uri.queryParametersAll.values.any((values) => values.length != 1)) {
    return false;
  }
  final query = uri.queryParameters;
  return _isSafeToken(query['codekey']) &&
      _isSafeToken(query['chainId']) &&
      query['hdw_device'] == 'web' &&
      query['hdw_appid'] == 'web' &&
      query['hitExp'] == '1';
}

bool _isSafeToken(String? value) =>
    value != null &&
    value.isNotEmpty &&
    value.length <= 256 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
