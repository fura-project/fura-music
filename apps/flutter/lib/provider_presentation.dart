import 'package:flutterustmusic/l10n/app_localizations.dart';

String builtInProviderDisplayName(
  String providerId, [
  AppLocalizations? l10n,
]) => switch (providerId) {
  'qq-music' => l10n?.providerQqMusic ?? 'QQ Music',
  'netease-cloud-music' =>
    l10n?.providerNeteaseCloudMusic ?? 'NetEase Cloud Music',
  _ => l10n?.providerGenericMusicService ?? 'Music service',
};
