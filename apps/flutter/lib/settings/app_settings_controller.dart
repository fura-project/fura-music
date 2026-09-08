import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutterustmusic/settings/app_settings.dart';
import 'package:flutterustmusic/settings/app_settings_store.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController(
    this._store,
    this._onPlaybackQualityChanged, {
    required AppSettings initialSettings,
  }) : _settings = initialSettings,
       _persistedSettings = initialSettings;

  AppSettingsStore? _store;
  final ValueChanged<AppPlaybackQualityPreference>? _onPlaybackQualityChanged;

  AppSettings _settings;
  AppSettings _persistedSettings;
  AppSettings? _latestRequestedSettings;
  Future<AppSettingsWriteResult>? _latestWrite;
  bool _disposed = false;

  AppSettings get settings => _settings;

  Future<AppSettingsWriteResult> update(AppSettings settings) {
    if (_disposed) {
      return Future.value(AppSettingsWriteResult.storageUnavailable);
    }
    if (settings == _settings) {
      if (_latestRequestedSettings == settings && _latestWrite != null) {
        return _latestWrite!;
      }
      return Future.value(AppSettingsWriteResult.saved);
    }

    _applyCurrent(settings);
    final operation = _persistAndReconcile(settings);
    _latestRequestedSettings = settings;
    _latestWrite = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_latestWrite, operation)) {
          _latestRequestedSettings = null;
          _latestWrite = null;
        }
      }),
    );
    return operation;
  }

  Future<AppSettingsWriteResult> _persistAndReconcile(
    AppSettings requested,
  ) async {
    AppSettingsWriteResult result;
    try {
      final store = _store ??= AppSettingsStore();
      result = await store.save(requested);
    } on Object {
      result = AppSettingsWriteResult.storageUnavailable;
    }
    if (result == AppSettingsWriteResult.saved) {
      _persistedSettings = requested;
    } else if (!_disposed && _settings == requested) {
      _applyCurrent(_persistedSettings);
    }
    return result;
  }

  void _applyCurrent(AppSettings settings) {
    if (_settings == settings) return;
    final previousQuality = _settings.playbackQuality;
    _settings = settings;
    if (previousQuality != settings.playbackQuality) {
      _onPlaybackQualityChanged?.call(settings.playbackQuality);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
