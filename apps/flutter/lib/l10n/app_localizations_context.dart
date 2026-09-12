import 'package:flutter/widgets.dart';
import 'package:flutterustmusic/l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  /// Uses the configured app localization in production and a deterministic
  /// English fallback for independently hosted widgets (for example, focused
  /// component tests and embedders that have not installed the app delegate).
  /// The fallback stores no locale state and cannot override MaterialApp.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('en'));
}
