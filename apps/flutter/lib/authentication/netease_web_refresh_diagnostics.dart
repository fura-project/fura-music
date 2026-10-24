import 'dart:io';

import 'package:flutter/foundation.dart';

enum NeteaseWebLoginPath { webView, linuxIsolatedChromium }

enum NeteaseWebLoginCheckpoint { accountVerification, securePersistence }

/// Opt-in, fixed-schema observations from the current official-login adapter.
/// No API accepts credential values, URLs, account data or browser identifiers.
class NeteaseWebRefreshDiagnostics {
  const NeteaseWebRefreshDiagnostics({this.enabledOverride, this.sink});

  final bool? enabledOverride;
  final ValueChanged<String>? sink;

  bool get enabled =>
      enabledOverride ??
      (const String.fromEnvironment('FURA_NETEASE_WEB_REFRESH_DEBUG') == '1' ||
          !kIsWeb &&
              Platform.environment['FURA_NETEASE_WEB_REFRESH_DEBUG'] == '1');

  void capture({
    required bool musicU,
    required bool musicRU,
    required bool csrf,
    required bool structurallyValid,
  }) {
    _emit(
      'path=web_view phase=capture observed_music_u=$musicU '
      'observed_music_r_u=$musicRU observed_csrf=$csrf '
      'candidate_valid=$structurallyValid',
    );
  }

  void checkpoint(
    NeteaseWebLoginPath path,
    NeteaseWebLoginCheckpoint checkpoint, {
    required bool success,
  }) {
    _emit(
      'path=${path == NeteaseWebLoginPath.webView ? 'web_view' : 'linux_isolated_chromium'} '
      'phase=${checkpoint == NeteaseWebLoginCheckpoint.accountVerification ? 'account_verification_entered' : 'secure_persistence'} '
      'success=$success',
    );
  }

  void _emit(String fields) {
    if (enabled) {
      (sink ?? debugPrint)('FURA_NETEASE_WEB_REFRESH_DEBUG $fields');
    }
  }
}
