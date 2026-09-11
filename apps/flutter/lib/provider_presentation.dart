String builtInProviderDisplayName(String providerId) => switch (providerId) {
  'qq-music' => 'QQ Music',
  'netease-cloud-music' => 'NetEase Cloud Music',
  _ => 'Music service',
};
