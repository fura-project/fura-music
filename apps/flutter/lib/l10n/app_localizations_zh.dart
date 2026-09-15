// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'fura music';

  @override
  String get commonBack => '返回';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonRetry => '重试';

  @override
  String get commonClearSearch => '清除搜索';

  @override
  String get commonDismiss => '关闭';

  @override
  String get commonLoadMore => '加载更多';

  @override
  String get commonTryLoadingMoreAgain => '重新尝试加载更多';

  @override
  String get commonAddToQueue => '加入播放队列';

  @override
  String get commonMoreActions => '更多操作';

  @override
  String get commonPlayFromHere => '从这里播放';

  @override
  String get commonOpenAlbum => '查看专辑';

  @override
  String get commonOpenArtist => '查看歌手';

  @override
  String get commonChooseArtist => '选择歌手';

  @override
  String get commonPlay => '播放';

  @override
  String commonTrackSemantics(Object artists, Object title) {
    return '$title，$artists';
  }

  @override
  String commonAnnouncement(Object detail, Object title) {
    return '$title。$detail';
  }

  @override
  String commonSelectedValue(Object label, Object value) {
    return '$label：$value';
  }

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonScrollToLoadMore => '滚动以加载更多';

  @override
  String get tableTitle => '标题';

  @override
  String get tableArtist => '歌手';

  @override
  String get tableAlbum => '专辑';

  @override
  String get tableDuration => '时长';

  @override
  String get trackUnknownArtist => '未知歌手';

  @override
  String trackBrowseContextTooltip(String trackTitle) {
    return '浏览《$trackTitle》的相关信息';
  }

  @override
  String trackAddToQueueTooltip(String trackTitle) {
    return '将《$trackTitle》加入播放队列';
  }

  @override
  String trackArtworkSemantics(String trackTitle) {
    return '《$trackTitle》的封面';
  }

  @override
  String get trackChooseArtistTitle => '选择歌手';

  @override
  String get trackMultipleArtistsDetail => '这首歌曲由多位歌手演唱。';

  @override
  String metadataActionSemantics(String action, String value) {
    return '$action：$value';
  }

  @override
  String get librarySectionLabel => '音乐库';

  @override
  String get libraryLikedSongs => '喜欢';

  @override
  String get libraryPlaylists => '歌单';

  @override
  String get libraryAlbums => '专辑';

  @override
  String get libraryArtists => '歌手';

  @override
  String get libraryRefreshDismissTooltip => '关闭刷新消息';

  @override
  String get authCloseTooltip => '关闭登录';

  @override
  String authSignInTitle(String provider) {
    return '登录 $provider';
  }

  @override
  String get authIntroductionMultiple => '使用 QQ 或微信扫码授权。我们不会收集密码。';

  @override
  String authIntroductionSingle(String provider) {
    return '使用官方 $provider 应用扫描此二维码。我们不会收集密码。';
  }

  @override
  String get authScanWithQq => '使用 QQ 扫码';

  @override
  String get authScanWithWechat => '使用微信扫码';

  @override
  String authScanWithProvider(String provider) {
    return '使用 $provider 扫码';
  }

  @override
  String get authCreatingCodeTitle => '正在创建安全二维码…';

  @override
  String authConnectingProvider(String provider) {
    return '正在连接 $provider 授权服务。';
  }

  @override
  String get authConnectingQq => '正在连接 QQ 授权服务。';

  @override
  String get authConnectingWechat => '正在连接微信与 QQ 音乐。';

  @override
  String get authCheckingSavedSession => '正在检查已保存的会话…';

  @override
  String get authSavedSessionFound => '发现已保存的会话';

  @override
  String authConfirmingSavedSession(String provider) {
    return '正在向 $provider 验证会话，验证完成后才会恢复访问。';
  }

  @override
  String authSavedSessionNeedsVerification(String provider) {
    return '本地检查已通过，但仍需由 $provider 验证。';
  }

  @override
  String get authChooseMethod => '选择登录方式';

  @override
  String get authSignedOutStorageTitle => '已退出登录，但保存的会话仍在';

  @override
  String authSignedOutStorageDetail(String provider) {
    return '已清除当前 $provider 会话，但无法从安全存储中删除保存的副本。重启后它可能再次出现。';
  }

  @override
  String get authSavedSessionExpiredTitle => '保存的会话已过期';

  @override
  String authSavedSessionExpiredDetail(Object provider) {
    return '$provider 标示的有效期已结束，请重新登录。';
  }

  @override
  String get authSavedSessionOtherVersionTitle => '保存的会话来自其他版本';

  @override
  String get authSavedSessionOtherVersionDetail =>
      '当前版本没有猜测其格式，因此保持原样。你可以重新登录以替换它。';

  @override
  String get authStorageUnavailableTitle => '安全存储不可用';

  @override
  String get authStorageUnavailableDetail => '本次运行仍可登录，但重启后可能需要再次登录。';

  @override
  String get authCoreUnavailableTitle => '音乐核心不可用';

  @override
  String get authRestoreCoreUnavailableDetail => '无法安全检查已保存的会话，请在重启后重试。';

  @override
  String get authSavedSessionUnreadableTitle => '无法读取保存的会话';

  @override
  String get authSavedSessionUnreadableDetail => '它保持原样，没有被当作有效登录。你可以重新登录以替换它。';

  @override
  String get authRemovingSavedSession => '正在删除保存的会话…';

  @override
  String get authRemoveSavedSessionAgain => '再次尝试删除';

  @override
  String get authTryVerificationAgain => '重新验证';

  @override
  String get authSignInAgain => '重新登录';

  @override
  String get authSavedSessionRejectedTitle => '保存的会话已被拒绝';

  @override
  String authSavedSessionRejectedDetail(Object provider) {
    return '$provider 已不再接受此会话，保存的副本已删除。';
  }

  @override
  String authSavedSessionRejectedCleanupDetail(Object provider) {
    return '$provider 已不再接受此会话，但安全存储无法删除它。重启后它可能再次出现。';
  }

  @override
  String authCouldNotReachProviderTitle(Object provider) {
    return '无法连接 $provider';
  }

  @override
  String get authSavedSessionNetworkDetail => '保存的会话仍然可用。请检查网络后重试。';

  @override
  String authProviderUnavailableTitle(Object provider) {
    return '$provider 暂时不可用';
  }

  @override
  String get authSavedSessionServiceDetail => '保存的会话保持原样，请稍后重新验证。';

  @override
  String authProviderChangedResponseTitle(Object provider) {
    return '$provider 的响应发生了变化';
  }

  @override
  String get authSavedSessionInvalidResponseDetail => '保存的会话已保留，没有被误判为退出登录。';

  @override
  String get authSavedSessionVerifyCoreDetail => '无法安全验证保存的会话，请在重启后重试。';

  @override
  String get authSavedSessionNotCurrentTitle => '保存的会话已不是当前会话';

  @override
  String get authSignInAgainDetail => '请重新登录以继续。';

  @override
  String get authConfirmPhoneTitle => '请在手机上确认';

  @override
  String get authReconnectingTitle => '正在重新连接…';

  @override
  String get authCodeScannedProviderDetail => '二维码已扫描，请在官方应用中批准登录。';

  @override
  String get authCodeScannedQqDetail => '二维码已扫描，请在 QQ 中批准登录。';

  @override
  String get authCodeScannedWechatDetail => '二维码已扫描，请在微信中批准登录。';

  @override
  String get authReconnectingDetail => '二维码仍然有效，我们将重试连接。';

  @override
  String authOpenProviderScanDetail(Object provider) {
    return '打开 $provider，选择扫一扫，然后扫描此二维码。';
  }

  @override
  String get authOpenQqScanDetail => '打开 QQ，选择扫一扫，然后扫描此二维码。';

  @override
  String get authOpenWechatScanDetail => '打开微信，选择扫一扫，然后扫描此二维码。';

  @override
  String authProviderQrSemantics(Object provider) {
    return '$provider 登录二维码';
  }

  @override
  String get authQqQrSemantics => 'QQ 登录二维码';

  @override
  String get authWechatQrSemantics => '微信登录二维码';

  @override
  String get authQqLogin => 'QQ 登录';

  @override
  String get authWechatLogin => '微信登录';

  @override
  String get authQuickLoginTitle => '快速登录';

  @override
  String get authQuickLoginDetail => '使用已登录桌面 QQ 的账号。';

  @override
  String get authNewCode => '刷新二维码';

  @override
  String get authOpenQrExternally => '在系统浏览器或网易云 App 中打开';

  @override
  String get authOpeningQrExternally => '正在打开确认页…';

  @override
  String get authOpenQrExternallyFailed => '系统无法打开当前确认页，请使用另一台设备扫描二维码。';

  @override
  String get authSignedInTitle => '登录成功';

  @override
  String authSavingSessionDetail(Object provider) {
    return '$provider 已接受此会话，正在将它保存到平台安全存储…';
  }

  @override
  String get authSavedSessionReadyDetail => '此会话已安全保存，本次运行可以使用。';

  @override
  String get authSessionOnlyDetail => '本次运行已登录，但安全存储不可用，重启后需要重新登录。';

  @override
  String authStorageNotConfirmedDetail(Object provider) {
    return '$provider 已接受此会话，但尚未确认安全存储状态。';
  }

  @override
  String get authCodeExpiredTitle => '二维码已过期';

  @override
  String get authCodeExpiredDetail => '请刷新二维码后继续登录。';

  @override
  String get authNotApprovedTitle => '登录未获批准';

  @override
  String get authNotApprovedDetail => '账号没有发生任何变化，你可以重试。';

  @override
  String authSecurityVerificationTitle(Object provider) {
    return '$provider 要求额外安全验证';
  }

  @override
  String get authSecurityVerificationDetail =>
      '此次二维码登录触发了服务方安全验证。Fura 不会绕过验证；请稍后生成新二维码重试。';

  @override
  String authSecondaryVerificationTitle(Object provider) {
    return '$provider 要求完成二次验证';
  }

  @override
  String get authSecondaryVerificationDetail => '请在网易云音乐官方网页中继续，完成由服务方控制的验证。';

  @override
  String get authServiceRejectedDetail => '服务未接受此请求，请稍后重试。';

  @override
  String get authRejectedTitle => '登录被拒绝';

  @override
  String get authRejectedDetail => '授权未获接受，请选择登录方式后重试。';

  @override
  String get authNetworkFailuresTitle => '连接持续中断';

  @override
  String get authNetworkFailuresDetail => '请检查网络，然后刷新二维码。';

  @override
  String get authInvalidResponseDetail => '客户端已安全停止，没有猜测响应内容。请稍后刷新二维码。';

  @override
  String get authCouldNotContinueTitle => '无法继续登录';

  @override
  String get authCouldNotContinueDetail => '请重试本次会话或刷新二维码。';

  @override
  String authAnnouncementSemantics(Object detail, Object title) {
    return '$title。$detail';
  }

  @override
  String get authCheckingDesktopQq => '正在检查桌面 QQ…';

  @override
  String get authOpenDesktopQqDetail => '请打开并登录桌面 QQ，然后使用快速登录。';

  @override
  String get authNoDesktopAccount => '未找到已登录的桌面 QQ 账号。';

  @override
  String get authDesktopClientUnavailable => '桌面 QQ 不可用，请打开 QQ 后重试。';

  @override
  String get authDesktopNetworkFailure => '桌面 QQ 授权无法连接 QQ 音乐。';

  @override
  String get authDesktopServiceUnavailable => 'QQ 授权暂时不可用。';

  @override
  String get authDesktopRejected => '桌面 QQ 未批准本次授权。';

  @override
  String get authDesktopInvalidResponse => '桌面 QQ 返回了当前版本无法验证的响应。';

  @override
  String get authDesktopAttemptInactive => '本次快速登录已失效，请重新查找账号。';

  @override
  String get authDesktopAlreadyRunning => '桌面 QQ 授权已在进行中。';

  @override
  String get authDesktopCoreUnavailable => '音乐核心无法启动桌面 QQ 授权。';

  @override
  String get authDesktopUnavailable => '桌面 QQ 快速登录不可用。';

  @override
  String get authUsePhoneCode => '使用手机验证码';

  @override
  String get authUseQrCode => '使用二维码';

  @override
  String get authUseOfficialWebsite => '前往网易云音乐官网继续';

  @override
  String get authOfficialWebTitle => '在网易云音乐官网完成登录';

  @override
  String get authOfficialWebDetail => '请使用官方登录窗口。Fura 仅导入登录结果，验证账号后才会保存。';

  @override
  String get authOfficialWebErrorTitle => '网易云音乐官方登录未完成';

  @override
  String get authOfficialWebUnavailable => '此设备上无法打开官方登录窗口。';

  @override
  String get authOfficialWebRejected => '网易云音乐未接受官方网页产生的会话。';

  @override
  String get authOfficialWebNetwork => '网络连接失败，无法验证官方网页产生的会话。';

  @override
  String get authOfficialWebServiceUnavailable =>
      '官方登录交互已完成，但网易云音乐账号验证服务暂时不可用。';

  @override
  String get authOfficialWebInvalidCredential => '官方窗口未返回 Fura 可以验证的会话。';

  @override
  String get authOfficialWebAlreadyRunning => '已有一个网易云音乐官方登录窗口打开。';

  @override
  String get authOfficialWebFailed => '官方登录窗口无法安全完成，未保存任何会话。';

  @override
  String get authOfficialWebLoading => '正在加载网易云音乐官方登录页';

  @override
  String get authOfficialWebWaiting => '请在官方页面完成登录。Fura 会先验证登录结果，再保存会话。';

  @override
  String get authOfficialWebSystemBrowserWaiting =>
      '已打开独立的系统浏览器窗口。请在其中完成登录；Fura 安全读取并验证会话后会关闭该窗口。';

  @override
  String get authOfficialWebVerifying => '正在验证网易云音乐账号';

  @override
  String get authOfficialWebTimedOut => '官方登录会话已超时，请重新开始。';

  @override
  String get authOfficialWebCleanupFailed => 'Fura 无法清理临时网页会话，未保存任何凭据。';

  @override
  String get authSignedOutWebCleanupTitle => '已退出登录，但网页数据清理需要处理';

  @override
  String authSignedOutWebCleanupDetail(String providerName) {
    return '已移除$providerName账号和已保存会话，但 Fura 无法确认临时网页数据已清理。';
  }

  @override
  String get authPhoneCodeTitle => '使用手机验证码登录';

  @override
  String get authPhoneCodeDetail => '向网易云音乐账号绑定的手机号发送一次性验证码。';

  @override
  String get authCountryCode => '国家或地区代码';

  @override
  String get authPhoneNumber => '手机号';

  @override
  String get authSmsCode => '验证码';

  @override
  String get authSendCode => '发送验证码';

  @override
  String get authResendCode => '重新发送';

  @override
  String authResendCodeIn(int seconds) {
    return '$seconds 秒后重发';
  }

  @override
  String get authCodeSent => '验证码已发送，请查看短信。';

  @override
  String get authSmsSignIn => '登录';

  @override
  String get authSendingCode => '正在发送验证码…';

  @override
  String get authCheckingSmsCode => '正在验证…';

  @override
  String get authSmsRiskWarning => '网易云仍可能要求额外安全验证。Fura 不会绕过验证，而会停止并明确报告。';

  @override
  String get authSmsInvalidInput => '请使用纯数字填写有效的国家或地区代码、手机号和验证码。';

  @override
  String get authSmsCodeRejected => '验证码未获接受，请核对后重试。';

  @override
  String get authSmsRateLimited => '请求过于频繁，请稍后再发送验证码。';

  @override
  String get authSmsSecurityVerification => '网易云要求此次手机登录完成额外安全验证，Fura 无法绕过。';

  @override
  String get authSmsSecondaryVerification => '网易云要求完成互动式二次验证，请前往官方网页继续登录。';

  @override
  String get authSmsNetworkFailure => '无法连接网易云，请检查网络后重试。';

  @override
  String get authSmsServiceUnavailable => '网易云手机登录暂时不可用，请稍后重试或改用二维码。';

  @override
  String get authSmsInvalidResponse => '网易云返回了当前版本无法验证的响应，没有安装登录会话。';

  @override
  String get authSmsAlreadyRunning => '已有手机登录请求正在进行。';

  @override
  String get authSmsAttemptReplaced => '此次手机登录已不是当前会话，请重新发送验证码。';

  @override
  String get authSmsCoreUnavailable => '音乐核心无法继续手机登录。';

  @override
  String get searchSongHint => '歌曲、歌手或专辑名称';

  @override
  String get searchArtistHint => '歌手名称';

  @override
  String get searchAlbumHint => '专辑名称';

  @override
  String get searchPlaylistHint => '歌单名称';

  @override
  String get searchTypeLabel => '搜索类型';

  @override
  String searchSuggestionSubmit(String query) {
    return '搜索“$query”';
  }

  @override
  String get searchTracksType => '歌曲';

  @override
  String get searchArtistsType => '歌手';

  @override
  String get searchAlbumsType => '专辑';

  @override
  String get searchPlaylistsType => '歌单';

  @override
  String get searchBackTooltip => '返回音乐库';

  @override
  String searchProviderTitle(Object provider) {
    return '搜索 $provider';
  }

  @override
  String searchFindTracksTitle(Object provider) {
    return '在 $provider 中查找歌曲';
  }

  @override
  String get searchTrackPrompt => '按歌曲、歌手或专辑名称搜索。';

  @override
  String searchLoadingTracks(Object provider) {
    return '正在搜索 $provider 歌曲';
  }

  @override
  String get searchNoTracksTitle => '未找到歌曲';

  @override
  String get searchNoResultsDetail => '请尝试其他拼写或更宽泛的关键词。';

  @override
  String get searchEditAction => '修改搜索';

  @override
  String searchFindArtistsTitle(Object provider) {
    return '在 $provider 中查找歌手';
  }

  @override
  String get searchArtistPrompt => '按歌手或组合名称搜索。';

  @override
  String searchLoadingArtists(Object provider) {
    return '正在搜索 $provider 歌手';
  }

  @override
  String get searchNoArtistsTitle => '未找到歌手';

  @override
  String searchFindAlbumsTitle(Object provider) {
    return '在 $provider 中查找专辑';
  }

  @override
  String get searchAlbumPrompt => '按专辑名称搜索。';

  @override
  String searchLoadingAlbums(Object provider) {
    return '正在搜索 $provider 专辑';
  }

  @override
  String get searchNoAlbumsTitle => '未找到专辑';

  @override
  String searchFindPlaylistsTitle(Object provider) {
    return '在 $provider 中查找歌单';
  }

  @override
  String get searchPlaylistPrompt => '按公开歌单名称搜索。';

  @override
  String searchLoadingPlaylists(Object provider) {
    return '正在搜索 $provider 歌单';
  }

  @override
  String get searchNoPlaylistsTitle => '未找到歌单';

  @override
  String searchFailureTitle(Object provider) {
    return '无法搜索 $provider';
  }

  @override
  String get queueAddedMessage => '已加入播放队列';

  @override
  String get queueUpdateFailureMessage => '无法更新播放队列';

  @override
  String searchResultCount(int count, String query) {
    return '找到 $count 个与“$query”相关的结果';
  }

  @override
  String searchArtistResultCount(num count, Object query) {
    return '找到 $count 位与“$query”相关的歌手';
  }

  @override
  String searchAlbumResultCount(num count, Object query) {
    return '找到 $count 张与“$query”相关的专辑';
  }

  @override
  String searchPlaylistResultCount(num count, Object query) {
    return '找到 $count 个与“$query”相关的歌单';
  }

  @override
  String get searchArtistResultType => '歌手';

  @override
  String get searchAlbumResultType => '专辑';

  @override
  String get searchPlaylistResultType => '歌单';

  @override
  String trackCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String get searchBrowseCreditedArtists => '浏览参与演唱的歌手';

  @override
  String searchOpenNamedAlbum(Object albumTitle) {
    return '打开《$albumTitle》';
  }

  @override
  String get searchEndOfResults => '已显示全部结果';

  @override
  String get searchNetworkFailure => '请检查网络连接后重试。';

  @override
  String get searchServiceUnavailable => '音乐服务的搜索功能暂时不可用。';

  @override
  String get searchCancelled => '搜索已取消。';

  @override
  String get searchCoreUnavailable => '本地音乐核心不可用，请重启应用后重试。';

  @override
  String get searchUnexpectedResponse => '音乐服务返回了无法识别的搜索响应。';

  @override
  String get searchArtistServiceUnavailable => '歌手搜索暂时不可用。';

  @override
  String get searchArtistCancelled => '歌手搜索已取消。';

  @override
  String get searchArtistUnexpectedResponse => '音乐服务返回了无法识别的歌手搜索响应。';

  @override
  String get searchAlbumServiceUnavailable => '专辑搜索暂时不可用。';

  @override
  String get searchAlbumCancelled => '专辑搜索已取消。';

  @override
  String get searchAlbumUnexpectedResponse => '音乐服务返回了无法识别的专辑搜索响应。';

  @override
  String get searchPlaylistServiceUnavailable => '歌单搜索暂时不可用。';

  @override
  String get searchPlaylistCancelled => '歌单搜索已取消。';

  @override
  String get searchPlaylistUnexpectedResponse => '音乐服务返回了无法识别的歌单搜索响应。';

  @override
  String get discoverTitle => '探索';

  @override
  String get discoverBackTooltip => '返回我的音乐';

  @override
  String discoverSubtitleWithRadar(Object provider) {
    return '来自 $provider 的歌单、排行榜、雷达和新发布内容';
  }

  @override
  String discoverSubtitleWithoutRadar(Object provider) {
    return '来自 $provider 的歌单、排行榜和新发布内容';
  }

  @override
  String get discoverPlaylistsTab => '歌单';

  @override
  String get discoverRankingsTab => '排行榜';

  @override
  String get discoverRadarTab => '雷达';

  @override
  String get discoverNewAlbumsTab => '新专辑';

  @override
  String get discoverNewSongsTab => '新歌';

  @override
  String get discoverLoadingRecommendations => '正在加载推荐歌单';

  @override
  String get discoverNoRecommendationsTitle => '暂无推荐';

  @override
  String discoverNoRecommendationsDetail(Object provider) {
    return '$provider 返回了空的推荐歌单页。';
  }

  @override
  String get discoverRecommendationsFailureTitle => '无法加载推荐';

  @override
  String discoverLoadingRankings(Object provider) {
    return '正在加载 $provider 排行榜';
  }

  @override
  String get discoverNoRankingsTitle => '暂无排行榜';

  @override
  String discoverNoRankingsDetail(Object provider) {
    return '$provider 当前未返回排行榜。';
  }

  @override
  String get discoverRankingsFailureTitle => '无法加载排行榜';

  @override
  String get discoverLoadingRadar => '正在加载 QQ 音乐雷达';

  @override
  String get discoverNoRadarTitle => '暂无雷达歌曲';

  @override
  String get discoverNoRadarDetail => 'QQ 音乐返回了空的雷达歌曲页。';

  @override
  String get discoverRadarFailureTitle => '无法加载雷达';

  @override
  String get discoverReloadRadar => '重新加载雷达';

  @override
  String get discoverRefreshRadar => '刷新雷达';

  @override
  String get discoverLoadingNewAlbums => '正在加载新专辑';

  @override
  String get discoverNoNewAlbumsTitle => '暂无新专辑';

  @override
  String discoverNoNewAlbumsDetail(Object provider) {
    return '$provider 在此区域未返回专辑。';
  }

  @override
  String get discoverNewAlbumsFailureTitle => '无法加载新专辑';

  @override
  String get discoverLoadingNewSongs => '正在加载新歌';

  @override
  String get discoverNoNewSongsTitle => '暂无新歌';

  @override
  String discoverNoNewSongsDetail(Object provider) {
    return '$provider 在此分类未返回歌曲。';
  }

  @override
  String get discoverNewSongsFailureTitle => '无法加载新歌';

  @override
  String get discoverEndNewAlbums => '新专辑已全部显示';

  @override
  String get discoverEndRadar => '雷达推荐已全部显示';

  @override
  String get discoverEndRecommendations => '推荐已全部显示';

  @override
  String get discoverMusicServicePlaylist => '音乐服务歌单';

  @override
  String get discoverCurrentRanking => '当前排行榜';

  @override
  String get discoverAlbumType => '专辑';

  @override
  String get discoverRecommendationServiceFailure => '推荐服务暂时不可用。';

  @override
  String get discoverRecommendationCancelled => '推荐请求已取消。';

  @override
  String get discoverRecommendationUnexpected => '音乐服务返回了无法识别的推荐响应。';

  @override
  String get discoverRadarAuthenticationRequired => '请先登录以加载 QQ 音乐雷达歌曲。';

  @override
  String get discoverRadarCredentialRejected => 'QQ 音乐会话已过期，请重新登录。';

  @override
  String get discoverRadarCredentialCleanupFailure =>
      'QQ 音乐会话已过期，但无法删除已保存的副本。请检查安全存储后重新登录。';

  @override
  String get discoverRadarServiceFailure => 'QQ 音乐雷达暂时不可用。';

  @override
  String get discoverRadarAccountChanged => '加载雷达时登录账号已变更。';

  @override
  String get discoverRadarCancelled => '雷达请求已取消。';

  @override
  String get discoverRadarUnexpected => 'QQ 音乐返回了无法识别的雷达响应。';

  @override
  String get discoverNewAlbumServiceFailure => '新专辑服务暂时不可用。';

  @override
  String get discoverNewAlbumCancelled => '新专辑请求已取消。';

  @override
  String get discoverNewAlbumUnexpected => '音乐服务返回了无法识别的新专辑响应。';

  @override
  String get discoverNewSongServiceFailure => '新歌服务暂时不可用。';

  @override
  String get discoverNewSongCancelled => '新歌请求已取消。';

  @override
  String get discoverNewSongUnexpected => '音乐服务返回了无法识别的新歌响应。';

  @override
  String get discoverRegionMainlandChina => '中国大陆';

  @override
  String get discoverRegionHongKongTaiwan => '港台';

  @override
  String get discoverRegionWestern => '欧美';

  @override
  String get discoverRegionKorea => '韩国';

  @override
  String get discoverRegionJapan => '日本';

  @override
  String get discoverRegionOther => '其他';

  @override
  String get discoverCategoryLatest => '最新';

  @override
  String get rankingTitle => '排行榜';

  @override
  String get rankingBackTooltip => '返回排行榜';

  @override
  String get rankingLoadingTracks => '正在加载排行榜歌曲';

  @override
  String get rankingEmptyTitle => '此排行榜暂无可用歌曲';

  @override
  String rankingEmptyDetail(Object provider) {
    return '$provider 返回了空的当前排行榜歌曲列表。';
  }

  @override
  String get rankingFailureTitle => '无法加载此排行榜';

  @override
  String get rankingEyebrow => 'QQ 音乐排行榜';

  @override
  String rankingShowingTracks(Object shown, Object total) {
    return '已显示 $shown / $total 首歌曲';
  }

  @override
  String get rankingEnd => '当前排行榜已全部显示';

  @override
  String rankingServiceFailure(Object provider) {
    return '$provider 排行榜暂时不可用。';
  }

  @override
  String get rankingCancelled => '排行榜请求已取消。';

  @override
  String rankingUnexpected(Object provider) {
    return '$provider 返回了无法识别的排行榜响应。';
  }

  @override
  String get commonNetworkFailure => '请检查网络连接后重试。';

  @override
  String get commonCoreUnavailable => '本地音乐核心不可用，请重启应用后重试。';

  @override
  String get commonSeeAll => '查看全部';

  @override
  String commonUnavailableSemantics(Object label) {
    return '$label，不可用';
  }

  @override
  String get homeRecommendationsSemantics => '主页推荐';

  @override
  String get homeRefreshPartialFailure => '部分推荐无法刷新，可在各区域重试。';

  @override
  String homeRefreshSuccess(Object provider) {
    return '推荐已刷新。$provider 可能会返回相同内容。';
  }

  @override
  String get homeRefreshWarning => '部分推荐刷新失败。正在显示上次可用的推荐；可点击刷新重试。';

  @override
  String get homePlaylistTreasures => '你的歌单宝藏';

  @override
  String get homePopularPlaylists => '热门歌单';

  @override
  String get homeRefreshing => '正在刷新…';

  @override
  String get homePersonalFm => '私人 FM';

  @override
  String get homeSongsPickedForYou => '为你挑选的歌曲';

  @override
  String get homeNewSongs => '新歌';

  @override
  String get homeFreshReleases => '新鲜发布';

  @override
  String get homePublicPlaylists => '公开歌单';

  @override
  String get homeMoreFromListening => '更多听歌推荐';

  @override
  String get homeChangePicks => '换一批';

  @override
  String get homeRecommendTab => '推荐';

  @override
  String get homeMusicTab => '音乐';

  @override
  String get homeAudiobooksTab => '有声书';

  @override
  String get homeAudiobooksUnavailable => '有声书尚不可用';

  @override
  String get homePodcastsTab => '播客';

  @override
  String get homePodcastsUnavailable => '播客不在当前产品范围内';

  @override
  String get homeSignOut => '退出登录';

  @override
  String homeSignInToProvider(Object provider) {
    return '登录 $provider';
  }

  @override
  String get homeForYouEyebrow => '为你推荐';

  @override
  String get homePublicSpotlightEyebrow => '公开精选';

  @override
  String get homeSelectedForYou => '为你精选';

  @override
  String get homeTodaysPick => '今日精选';

  @override
  String get homeLoadingRecommendations => '正在加载推荐…';

  @override
  String get homeRecommendationsUnavailable => '推荐暂时不可用，请重试。';

  @override
  String get homeNoRecommendations => '暂无推荐，可前往探索页浏览。';

  @override
  String get homePopularPlaylist => '热门歌单';

  @override
  String get homeDailyTracks => '每日歌曲';

  @override
  String get homeDailyRecommendation => '每日推荐';

  @override
  String get homeRadar => '雷达';

  @override
  String get homeMusicService => '音乐服务';

  @override
  String homeTrackPlaySemantics(
    Object artists,
    Object label,
    Object trackTitle,
  ) {
    return '$label，$trackTitle，$artists。播放';
  }

  @override
  String get homePreviousSpotlight => '上一个精选';

  @override
  String get homePauseSpotlight => '暂停精选轮播';

  @override
  String get homeResumeSpotlight => '继续精选轮播';

  @override
  String get homeNextSpotlight => '下一个精选';

  @override
  String homeRetrySection(Object title) {
    return '重试$title';
  }

  @override
  String get homeLoadingPublicPlaylists => '正在加载公开歌单';

  @override
  String get homeNoPublicPlaylists => '暂无公开歌单';

  @override
  String homeNoPublicPlaylistsDetail(Object provider) {
    return '$provider 未返回公开歌单推荐。';
  }

  @override
  String get homePublicPlaylistsFailure => '无法加载公开歌单';

  @override
  String get homeNoAdditionalPublicPlaylists => '暂无更多公开歌单';

  @override
  String get homeAvailablePublicShown => '可用的公开推荐已在上方显示。';

  @override
  String get homeLoadingPublicNewSongs => '正在加载公开新歌';

  @override
  String get homeNoNewSongs => '暂无新歌';

  @override
  String homeNoNewSongsDetail(Object provider) {
    return '$provider 未返回公开新歌集合。';
  }

  @override
  String get homeNewSongsFailure => '无法加载新歌';

  @override
  String get homeLoadingYourPlaylists => '正在加载你的歌单';

  @override
  String get homeNoPersonalizedPlaylists => '暂无个性化歌单';

  @override
  String get homeNoPersonalizedPlaylistsDetail => '可稍后刷新，或在探索页浏览公开歌单。';

  @override
  String homePersonalizedPlaylistSemantics(Object title) {
    return '$title，个性化歌单';
  }

  @override
  String get homeDiscoverAction => '探索';

  @override
  String get homeDailyAction => '每日推荐';

  @override
  String get homeRankingsAction => '排行榜';

  @override
  String get homeLikedAction => '喜欢';

  @override
  String get homeLoadingPersonalFm => '正在加载私人 FM';

  @override
  String get homeLoadingPersonalizedSongs => '正在加载个性化歌曲';

  @override
  String get homePersonalFmEmpty => '私人 FM 暂无歌曲';

  @override
  String get homePersonalizedSongsEmpty => '暂无个性化歌曲';

  @override
  String get homePersonalizedSongsEmptyDetail => '仍可使用公开歌单和你的音乐库。';

  @override
  String get homePersonalFmFailure => '无法加载私人 FM';

  @override
  String get homePersonalizedSongsFailure => '无法加载个性化歌曲';

  @override
  String get homeOtherSectionsAvailable => '主页其他区域仍可用。';

  @override
  String homeLoadingRelatedSongs(Object seed) {
    return '正在加载与$seed相关的歌曲';
  }

  @override
  String get homeRecentListening => '你最近收听的内容';

  @override
  String get homeStartListeningTitle => '开始听歌，发现更多';

  @override
  String get homeStartListeningDetail =>
      '在 fura 收听后，这里会根据最近听过的一首歌提供推荐。听歌记录仅保留在本次会话中。';

  @override
  String get homeNoRelatedSongs => '暂无相关歌曲';

  @override
  String homeNoRelatedSongsDetail(Object seed) {
    return '音乐服务未返回与「$seed」相关的歌曲。';
  }

  @override
  String homeBecauseListened(Object seed) {
    return '因为你听过「$seed」';
  }

  @override
  String get homeRecentSong => '最近的一首歌';

  @override
  String homeAddTrackToQueue(Object trackTitle) {
    return '将《$trackTitle》加入播放队列';
  }

  @override
  String get homeMoreRecommendationsUnavailable => '更多推荐不可用';

  @override
  String get homePrimaryRecommendationShown => '主推荐状态已在上方显示。';

  @override
  String get homePreviousPlaylists => '上一组歌单';

  @override
  String get homeNextPlaylists => '下一组歌单';

  @override
  String get homePersonalizedInvalidTitle => '无法识别个性化歌单响应';

  @override
  String get homePersonalizedOfflineTitle => '个性化歌单已离线';

  @override
  String get homePersonalizedUnavailableTitle => '个性化歌单暂时不可用';

  @override
  String get homePersonalizedReplacedTitle => '个性化歌单请求已被替换';

  @override
  String get homePersonalizedCancelledTitle => '个性化歌单请求已取消';

  @override
  String get homePersonalizedRunningTitle => '个性化歌单正在加载';

  @override
  String get homePersonalizedFailureTitle => '无法加载个性化歌单';

  @override
  String homePersonalizedInvalidDetail(Object provider) {
    return '$provider 返回了当前客户端无法识别的个性化歌单结构，未记录任何账号内容。';
  }

  @override
  String get homeNetworkRetryDetail => '请检查网络连接后重试。';

  @override
  String homePersonalizedServiceDetail(Object provider) {
    return '$provider 拒绝或无法处理此请求，请稍后重试。';
  }

  @override
  String get homePersonalizedReplacedDetail => '更新的已登录推荐请求已替换本次请求。';

  @override
  String get homePersonalizedCancelledDetail => '在返回个性化歌单前请求已结束。';

  @override
  String get homePersonalizedRunningDetail => '请等待当前个性化歌单请求完成。';

  @override
  String get homePublicAndSearchAvailable => '公开推荐和搜索仍可用。';

  @override
  String get homeRelatedInvalidTitle => '这首歌无法用于生成推荐';

  @override
  String get homeRelatedOfflineTitle => '相关歌曲已离线';

  @override
  String get homeRelatedUnavailableTitle => '相关歌曲暂时不可用';

  @override
  String get homeRelatedInvalidResponseTitle => '无法识别相关歌曲响应';

  @override
  String get homeRelatedCancelledTitle => '相关歌曲请求已取消';

  @override
  String get homeRelatedRunningTitle => '相关歌曲正在加载';

  @override
  String get homeRelatedFailureTitle => '无法加载相关歌曲';

  @override
  String homeRelatedInvalidTrackDetail(Object seed) {
    return '「$seed」没有可用的音乐服务标识。';
  }

  @override
  String get homeThisSong => '这首歌';

  @override
  String get homeRelatedServiceDetail => '该歌曲所属音乐服务暂时无法为它提供相关歌曲。';

  @override
  String get homeRelatedInvalidResponseDetail => '音乐服务返回了当前客户端无法识别的相关歌曲结构。';

  @override
  String get homeRelatedCancelledDetail => '在返回相关歌曲前，种子歌曲已变更。';

  @override
  String get homeRelatedRunningDetail => '请等待当前相关歌曲请求完成。';

  @override
  String get homeRelatedCoreDetail => '无法连接相关歌曲核心能力。';

  @override
  String get homePublicLoading => '正在加载公开推荐…';

  @override
  String get homePublicNoAdditional => '暂无更多公开推荐。';

  @override
  String homePublicEmpty(Object provider) {
    return '$provider 当前没有可用的公开推荐。';
  }

  @override
  String get homePublicFailure => '无法加载公开推荐。';

  @override
  String get homeLoadingDailyTracks => '正在加载每日歌曲…';

  @override
  String get homeLoadingDaily30 => '正在加载每日 30 首…';

  @override
  String get homeDailyTracksUnavailable => '每日歌曲暂时不可用。';

  @override
  String get homeDaily30Unavailable => '每日 30 首暂时不可用。';

  @override
  String get homeDailyTracksFailure => '无法加载每日歌曲。';

  @override
  String get homeDaily30Failure => '无法加载每日 30 首。';

  @override
  String get homeRadarLoading => '正在加载雷达推荐…';

  @override
  String get homeRadarUnavailable => '雷达暂时不可用。';

  @override
  String get homeRadarEmpty => 'QQ 音乐当前没有雷达推荐。';

  @override
  String get homeRadarFailure => '无法加载雷达推荐。';

  @override
  String get homePublicNewSongsLoading => '正在加载公开新歌…';

  @override
  String get homePublicNewSongsUnavailable => '当前没有可用的公开新歌。';

  @override
  String homePublicNewSongsEmpty(Object provider) {
    return '$provider 当前没有公开新歌。';
  }

  @override
  String get homePublicNewSongsFailure => '无法加载公开新歌。';

  @override
  String homeNewSongsServiceFailure(Object provider) {
    return '$provider 新歌服务暂时不可用。';
  }

  @override
  String homeNewSongsInvalidResponse(Object provider) {
    return '$provider 返回了当前客户端无法识别的新歌响应。';
  }

  @override
  String get homeNewSongsRunning => '请等待当前新歌请求完成。';

  @override
  String get homeMusicPlaylist => '音乐歌单';

  @override
  String homeMusicPlaylistSemantics(Object title) {
    return '$title，音乐歌单';
  }

  @override
  String get libraryPlaylistType => '歌单';

  @override
  String get libraryTrackCountColumn => '歌曲数';

  @override
  String get libraryBackToPlaylists => '返回歌单';

  @override
  String get libraryRefreshingPlaylist => '正在刷新歌单';

  @override
  String get libraryRefreshPlaylist => '刷新歌单';

  @override
  String get libraryPlaylistEmptyTitle => '这个歌单还是空的';

  @override
  String libraryPlaylistEmptyDetail(Object provider) {
    return '在 $provider 中添加的歌曲会显示在这里。';
  }

  @override
  String libraryPlaylistCountSummary(num count, Object provider) {
    return '$count 首歌曲 · $provider';
  }

  @override
  String libraryPlaylistEnd(Object total) {
    return '已加载全部 $total 首歌曲';
  }

  @override
  String get libraryRefreshPlaylistFailure => '无法刷新此歌单，仍显示之前的歌曲。';

  @override
  String get likedTitle => '喜欢';

  @override
  String get likedProgramsUnavailableTitle => '有声节目收藏尚未接入';

  @override
  String get likedProgramsUnavailableDetail =>
      '当前账号音乐库支持歌曲、歌单、专辑和歌手，但不包含有声节目收藏。';

  @override
  String get likedVideosUnavailableTitle => '视频收藏尚未接入';

  @override
  String get likedVideosUnavailableDetail => '歌曲关联 MV 不等同于账号的视频收藏，不会在这里混用。';

  @override
  String get likedPlaylistUnavailableTitle => '暂时无法找到喜欢歌单';

  @override
  String likedPlaylistUnavailableDetail(Object provider) {
    return '$provider 未返回内建喜欢歌单；其他收藏仍可从上方标签进入。';
  }

  @override
  String get likedLoadingTitle => '正在加载喜欢的歌曲…';

  @override
  String likedLoadingDetail(Object provider) {
    return '正在从 $provider 读取收藏。';
  }

  @override
  String get likedEmptyTitle => '还没有喜欢的歌曲';

  @override
  String likedEmptyDetail(Object provider) {
    return '在 $provider 中喜欢的歌曲会显示在这里。';
  }

  @override
  String get likedSearchingAllTitle => '正在搜索整个歌单…';

  @override
  String get likedNoTrackMatchTitle => '未找到匹配的歌曲';

  @override
  String likedSearchProgress(Object processed, Object total) {
    return '已检查 $processed / $total 首，匹配结果会随加载实时更新。';
  }

  @override
  String likedSearchFinishedNoMatch(Object omitted, Object total) {
    return '已搜索全部 $total 首歌曲$omitted，请尝试其他关键词。';
  }

  @override
  String get likedContinueSearch => '继续搜索';

  @override
  String get likedQueueAdded => '已添加到播放队列';

  @override
  String likedSongsTab(Object count) {
    return '歌曲 $count';
  }

  @override
  String get likedSongsTabWithoutCount => '歌曲';

  @override
  String likedPlaylistsTab(Object count) {
    return '歌单 $count';
  }

  @override
  String get likedAlbumsTab => '专辑';

  @override
  String get likedProgramsTab => '有声节目';

  @override
  String get likedVideosTab => '视频';

  @override
  String get likedNoPlaylistMatch => '未找到匹配的歌单';

  @override
  String get likedNoOtherPlaylists => '还没有其他歌单';

  @override
  String get likedTryAnotherKeyword => '请尝试其他关键词。';

  @override
  String get likedCreatedPlaylists => '自创歌单';

  @override
  String get likedSavedPlaylists => '收藏歌单';

  @override
  String get likedOtherPlaylists => '其他歌单';

  @override
  String likedPlaylistCollectionDetail(Object provider) {
    return '你在 $provider 中创建或收藏的歌单会显示在这里。';
  }

  @override
  String likedPlaylistSectionCount(Object count, Object title) {
    return '$title $count';
  }

  @override
  String likedPlaylistSemantics(Object title) {
    return '$title，歌单';
  }

  @override
  String likedTrackCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String get likedPlayAll => '播放全部';

  @override
  String get likedRefreshing => '正在刷新';

  @override
  String get likedRefreshSongs => '刷新喜欢的歌曲';

  @override
  String get likedSearchEntirePlaylist => '搜索整个歌单';

  @override
  String get likedSearchPlaylists => '搜索歌单';

  @override
  String get likedSearchLoadedAlbums => '搜索已加载专辑';

  @override
  String get likedProgramsSearchUnavailable => '有声节目收藏尚未接入';

  @override
  String get likedVideosSearchUnavailable => '视频收藏尚未接入';

  @override
  String get likedMultipleArtistsDetail => '这首歌曲包含多个歌手，请选择要打开的歌手。';

  @override
  String get likedRetryLoad => '重试加载';

  @override
  String likedReadStatus(Object available, Object processed, Object total) {
    return '已读取 $processed / $total 首，可显示 $available 首';
  }

  @override
  String likedSearchInterruptedStatus(Object processed, Object total) {
    return '搜索暂时中断 · 已检查 $processed / $total 首';
  }

  @override
  String get likedSearchInterruptedTitle => '搜索暂时中断';

  @override
  String likedSearchInterruptedDetail(Object processed, Object total) {
    return '已检查 $processed / $total 首，可重试继续搜索剩余歌曲。';
  }

  @override
  String likedOmittedSearchSuffix(Object count) {
    return '，其中 $count 首缺少可检索标识';
  }

  @override
  String likedOmittedTracksDetail(Object count) {
    return '$count 首歌曲缺少可用标识，已跳过且不影响后续加载。';
  }

  @override
  String likedExactResults(Object count) {
    return '$count 首';
  }

  @override
  String likedApproximateResults(Object count) {
    return '$count 首可能结果';
  }

  @override
  String likedSearchingStatus(Object processed, Object results, Object total) {
    return '已找到 $results · 正在检查 $processed / $total 首';
  }

  @override
  String likedApproximateOnlyStatus(Object results) {
    return '未找到完全匹配 · 显示 $results';
  }

  @override
  String likedMixedResults(Object approximate, Object count) {
    return '$count 首（含 $approximate 首可能结果）';
  }

  @override
  String likedSearchCompleteStatus(Object results, Object total) {
    return '已搜索全部 $total 首 · 找到 $results';
  }

  @override
  String get likedFailureNetworkTitle => '网络不可用';

  @override
  String get likedFailureNetworkDetail => '请检查网络后重试。';

  @override
  String likedFailureServiceTitle(Object provider) {
    return '$provider 暂时无法加载';
  }

  @override
  String get likedFailureServiceDetail => '你的会话状态保持不变，稍后重试即可。';

  @override
  String get likedFailureSignedOutTitle => '登录已失效';

  @override
  String get likedFailureSignedOutDetail => '请重新登录后加载喜欢的歌曲。';

  @override
  String get likedFailureAuthenticationTitle => '需要登录';

  @override
  String likedFailureAuthenticationDetail(Object provider) {
    return '请登录 $provider 后继续。';
  }

  @override
  String get likedFailureInvalidTitle => '无法安全读取喜欢的歌曲';

  @override
  String get likedFailureInvalidDetail => '请重试；当前结果未被部分显示。';

  @override
  String get likedFailureCoreTitle => '无法加载喜欢的歌曲';

  @override
  String get likedFailureCoreDetail => '请重试，或重启应用后再试。';

  @override
  String get likedFailureGenericDetail => '请重试。';

  @override
  String get likedRefreshNetworkFailure => '刷新失败：请检查网络。';

  @override
  String likedRefreshServiceFailure(Object provider) {
    return '$provider 暂时无法刷新。';
  }

  @override
  String get likedRefreshInvalidResponse => '无法安全读取刷新结果。';

  @override
  String get likedRefreshFailure => '刷新失败，仍保留上一次结果。';

  @override
  String get recentTitle => '最近播放';

  @override
  String get recentCloudSubtitle => 'QQ 音乐账号的播放记录 · 最近播放优先';

  @override
  String get recentCloudNotConnectedShort => 'QQ 音乐云端记录尚未接通';

  @override
  String recentProcessedStatus(
    Object action,
    Object approximate,
    Object omitted,
    Object processed,
    Object total,
  ) {
    return '$action $processed$total 首$approximate$omitted';
  }

  @override
  String get recentLoadedAction => '已加载';

  @override
  String get recentSearchedAction => '已搜索';

  @override
  String recentTotalPart(Object total) {
    return ' / $total';
  }

  @override
  String recentApproximatePart(Object count) {
    return ' · $count 个近似匹配';
  }

  @override
  String recentOmittedPart(Object count) {
    return ' · $count 首暂不可显示';
  }

  @override
  String recentSongsTab(Object count) {
    return '歌曲 $count';
  }

  @override
  String recentSongsTabApproximate(Object count) {
    return '歌曲 $count+';
  }

  @override
  String get recentSongsTabWithoutCount => '歌曲';

  @override
  String get recentSearchHint => '搜索最近播放';

  @override
  String get recentRefreshSnapshotFailure => '刷新失败，仍显示上次读取的记录。';

  @override
  String get recentPlayTooltip => '播放最近播放';

  @override
  String get recentRefreshTooltip => '刷新最近播放';

  @override
  String get recentUnavailableTitle => '暂时无法读取跨设备播放记录';

  @override
  String get recentUnavailableDetail =>
      '当前版本尚未接通 QQ 音乐的云端最近播放。\n接通后，你可以在这里查看同一账号的播放记录。';

  @override
  String get recentLoadingTitle => '正在读取最近播放…';

  @override
  String get recentSignInTitle => '请重新登录 QQ 音乐';

  @override
  String get recentSignInDetail => '登录同一账号后再读取云端播放记录。';

  @override
  String get recentUnavailableTemporaryTitle => '暂时无法读取最近播放';

  @override
  String get recentTryLater => '请稍后重试。';

  @override
  String get recentEmptyTitle => '还没有云端播放记录';

  @override
  String get recentEmptyDetail => '刷新可以重新读取 QQ 音乐返回的记录。';

  @override
  String get recentSearchingAll => '正在搜索整个播放记录…';

  @override
  String get recentNoMatch => '未找到匹配的歌曲';

  @override
  String get recentAppendFailure => '后续记录加载失败，已加载的歌曲仍可播放。';

  @override
  String get recentContinueLoading => '继续加载';

  @override
  String get recentAddToQueue => '加入播放队列';

  @override
  String get recentChooseArtistDetail => '这首歌曲包含多个歌手，请选择要打开的歌手。';

  @override
  String libraryShowingTracks(Object shown, Object total) {
    return '已显示 $shown / $total 首歌曲';
  }

  @override
  String get libraryEndPlaylist => '歌单已全部显示';

  @override
  String libraryFailureReachTitle(Object provider) {
    return '无法连接 $provider';
  }

  @override
  String get libraryFailureReachDetail => '会话仍然有效，请检查网络连接后重试。';

  @override
  String libraryFailureUnavailableTitle(Object provider) {
    return '$provider 不可用';
  }

  @override
  String get libraryFailureUnavailableDetail => '当前无法加载歌单，会话已保留。';

  @override
  String get libraryFailureReadTitle => '无法读取此歌单';

  @override
  String libraryFailureReadDetail(Object provider) {
    return '$provider 返回了当前版本无法安全显示的数据。';
  }

  @override
  String get libraryFailureRejectedTitle => '已保存的会话被拒绝';

  @override
  String libraryFailureRejectedDetail(Object provider) {
    return '$provider 已不再接受此会话，已删除保存的会话。';
  }

  @override
  String libraryFailureRejectedCleanupDetail(Object provider) {
    return '$provider 拒绝了此会话，但安全存储无法将其删除。';
  }

  @override
  String get libraryFailureSignInTitle => '登录后打开此歌单';

  @override
  String get libraryFailureAccountChangedDetail => '请求完成前账号状态已变更。';

  @override
  String get libraryFailureCoreTitle => '音乐核心不可用';

  @override
  String get libraryFailureCoreDetail => '无法安全加载此歌单。';

  @override
  String get libraryFailureRunningTitle => '已有歌单请求正在进行';

  @override
  String get libraryFailureRunningDetail => '请等待完成后再重试。';

  @override
  String get libraryFailureGenericTitle => '无法加载此歌单';

  @override
  String get libraryFailureGenericDetail => '请重试或重新登录。';

  @override
  String get navHome => '主页';

  @override
  String get navDiscover => '探索';

  @override
  String get navSearch => '搜索';

  @override
  String get navLiked => '喜欢';

  @override
  String get navRecentPlays => '最近播放';

  @override
  String get navOnlineMusicSection => '在线音乐';

  @override
  String get navMyMusicSection => '我的音乐';

  @override
  String get navYourPlaylistsSection => '你的歌单';

  @override
  String get navSettingsSection => '设置';

  @override
  String shellSearchProvider(Object provider) {
    return '搜索 $provider';
  }

  @override
  String get shellSignOut => '退出登录';

  @override
  String get shellSignIn => '登录';

  @override
  String shellSignInToProvider(Object provider) {
    return '登录 $provider';
  }

  @override
  String shellLoadingProviderAccount(Object provider) {
    return '正在加载 $provider 账号…';
  }

  @override
  String shellProviderClient(Object provider) {
    return '$provider 客户端';
  }

  @override
  String get shellBackToMusic => '返回音乐';

  @override
  String get shellBackToFavoriteArtists => '返回收藏歌手';

  @override
  String get shellBackToPlaylist => '返回歌单';

  @override
  String get shellBackToAlbum => '返回专辑';

  @override
  String get shellBackToPreviousPage => '返回上一页';

  @override
  String get shellBackToSearchResults => '返回搜索结果';

  @override
  String get shellBackToArtist => '返回歌手';

  @override
  String get shellBackToNewAlbums => '返回新专辑';

  @override
  String get shellBackToFavoriteAlbums => '返回收藏专辑';

  @override
  String get libraryYourPlaylists => '你的歌单';

  @override
  String libraryPlaylistsSavedCount(num count, Object provider) {
    return '在 $provider 保存了 $count 个歌单';
  }

  @override
  String libraryPlaylistsSavedProvider(Object provider) {
    return '保存在 $provider';
  }

  @override
  String get libraryRefreshingPlaylists => '正在刷新歌单';

  @override
  String get libraryRefreshPlaylists => '刷新歌单';

  @override
  String libraryPlaylistCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String get libraryLoadingPlaylists => '正在加载你的歌单…';

  @override
  String get libraryNoPlaylistsTitle => '还没有歌单';

  @override
  String libraryNoPlaylistsDetail(Object provider) {
    return '你在 $provider 创建或收藏的歌单会显示在这里。';
  }

  @override
  String get librarySignInTitle => '登录后查看你的音乐';

  @override
  String librarySignInDetail(Object provider) {
    return '你在 $provider 的歌单、喜欢的歌曲、专辑和歌手会显示在这里。';
  }

  @override
  String get librarySignOutConfirmTitle => '在此设备上退出登录？';

  @override
  String librarySignOutConfirmDetail(Object provider) {
    return '这会停止播放，并从此设备移除已保存的 $provider 会话。';
  }

  @override
  String get librarySignOutFailure => '无法退出登录，本地会话保持不变。';

  @override
  String get libraryQualitySaveFailure => '无法保存播放音质，设置未更改。';

  @override
  String get libraryRefreshFailure => '无法刷新歌单，仍显示之前的结果。';

  @override
  String get libraryFailureReachCollectionDetail => '会话仍然有效，请检查网络后重试。';

  @override
  String get libraryFailureServiceCollectionDetail => '会话保持不变，请稍后重新加载歌单。';

  @override
  String get libraryFailureCompleteTitle => '无法读取完整音乐库';

  @override
  String libraryFailureCompleteDetail(Object provider) {
    return '$provider 返回的收藏列表无法由当前版本安全读取，因此未显示不完整列表。';
  }

  @override
  String get libraryFailureSignInPlaylistsTitle => '登录后加载你的歌单';

  @override
  String get libraryFailureRequestChangedDetail => '音乐库请求完成前账号状态已变更。';

  @override
  String get libraryFailureCoreCollectionDetail => '无法安全加载音乐库，请重启后重试。';

  @override
  String get libraryFailureRunningCollectionTitle => '已有音乐库请求正在进行';

  @override
  String get libraryFailureGenericCollectionTitle => '无法加载你的歌单';

  @override
  String libraryFailureGenericCollectionDetail(Object provider) {
    return '请重试或使用新的 $provider 会话登录。';
  }

  @override
  String get favoriteAlbumsTitle => '收藏专辑';

  @override
  String get favoriteArtistsTitle => '收藏歌手';

  @override
  String favoriteSavedCount(Object count, Object provider) {
    return '在 $provider 收藏了 $count 项';
  }

  @override
  String favoriteSavedProvider(Object provider) {
    return '收藏于 $provider';
  }

  @override
  String get favoriteAlbumsRefreshing => '正在刷新收藏专辑';

  @override
  String get favoriteAlbumsRefresh => '刷新收藏专辑';

  @override
  String get favoriteArtistsRefreshing => '正在刷新收藏歌手';

  @override
  String get favoriteArtistsRefresh => '刷新收藏歌手';

  @override
  String get favoriteAlbumsLoading => '正在加载收藏专辑';

  @override
  String get favoriteArtistsLoading => '正在加载收藏歌手';

  @override
  String get favoriteAlbumsEmptyTitle => '还没有收藏专辑';

  @override
  String favoriteAlbumsEmptyDetail(Object provider) {
    return '你在 $provider 收藏的专辑会显示在这里。';
  }

  @override
  String get favoriteArtistsEmptyTitle => '还没有收藏歌手';

  @override
  String favoriteArtistsEmptyDetail(Object provider) {
    return '你在 $provider 关注的歌手会显示在这里。';
  }

  @override
  String get favoriteAlbumsSearchEmptyTitle => '未找到匹配的专辑';

  @override
  String get favoriteAlbumsSearchEmptyDetail => '请尝试其他关键词，搜索范围为已加载的收藏专辑。';

  @override
  String get favoriteAlbumsFailureTitle => '无法加载收藏专辑';

  @override
  String get favoriteArtistsFailureTitle => '无法加载收藏歌手';

  @override
  String get favoriteAlbumsSignInTitle => '登录后查看收藏专辑';

  @override
  String get favoriteAlbumsSignInDetail => '请重新登录后加载收藏专辑。';

  @override
  String get favoriteArtistsSignInTitle => '登录后查看收藏歌手';

  @override
  String get favoriteArtistsSignInDetail => '请重新登录后加载收藏歌手。';

  @override
  String favoriteSessionRejectedTitle(Object provider) {
    return '$provider 会话被拒绝';
  }

  @override
  String favoriteSessionRejectedCleanupDetail(Object provider) {
    return '$provider 拒绝了此会话，且无法移除已保存的副本。';
  }

  @override
  String favoriteSessionRejectedDetail(Object provider) {
    return '$provider 已不再接受此已保存会话。';
  }

  @override
  String favoriteAlbumSemantics(Object title) {
    return '$title，专辑';
  }

  @override
  String favoriteArtistSemantics(Object name) {
    return '$name，歌手';
  }

  @override
  String favoriteFailureNetwork(Object provider) {
    return '无法连接 $provider，请检查网络后重试。';
  }

  @override
  String favoriteAlbumsFailureService(Object provider) {
    return '$provider 当前无法加载收藏专辑。';
  }

  @override
  String favoriteArtistsFailureService(Object provider) {
    return '$provider 当前无法加载收藏歌手。';
  }

  @override
  String favoriteAlbumsFailureInvalid(Object provider) {
    return '$provider 返回了无法读取的收藏专辑分页。';
  }

  @override
  String favoriteArtistsFailureInvalid(Object provider) {
    return '$provider 返回了无法读取的收藏歌手分页。';
  }

  @override
  String get favoriteFailureCore => '音乐核心不可用，请重试。';

  @override
  String get favoriteAlbumsFailureRunning => '已有收藏专辑请求正在进行。';

  @override
  String get favoriteArtistsFailureRunning => '已有收藏歌手请求正在进行。';

  @override
  String get favoriteFailureSignIn => '请重新登录后继续。';

  @override
  String get albumType => '专辑';

  @override
  String get albumLoadingTracks => '正在加载专辑歌曲';

  @override
  String get albumEmptyTitle => '此专辑没有可用歌曲';

  @override
  String albumEmptyDetail(Object provider) {
    return '$provider 返回了空的专辑歌曲列表。';
  }

  @override
  String get albumFailureTitle => '无法加载此专辑';

  @override
  String albumAboutTitle(Object title) {
    return '关于《$title》';
  }

  @override
  String get albumChooseArtistTitle => '选择歌手';

  @override
  String albumTrackCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String albumProviderSummary(Object provider) {
    return '$provider 专辑';
  }

  @override
  String get albumAboutAction => '关于此专辑';

  @override
  String get albumRetryDetails => '重试专辑详情';

  @override
  String get albumMultipleArtistsDetail => '此专辑包含多位歌手。';

  @override
  String get albumEnd => '专辑已全部显示';

  @override
  String get albumFailureNetwork => '请检查网络后重试。';

  @override
  String albumFailureService(Object provider) {
    return '$provider 的专辑浏览暂时不可用。';
  }

  @override
  String get albumFailureCancelled => '专辑请求已取消。';

  @override
  String get catalogFailureCore => '本地音乐核心不可用，请重启应用后重试。';

  @override
  String albumFailureUnexpected(Object provider) {
    return '$provider 返回了异常的专辑响应。';
  }

  @override
  String get albumDetailsFailureNetwork => '专辑详情当前离线。';

  @override
  String get albumDetailsFailureService => '专辑详情暂时不可用。';

  @override
  String get albumDetailsFailureCancelled => '专辑详情加载已取消。';

  @override
  String get albumDetailsFailureCore => '无法启动专辑详情加载。';

  @override
  String get albumDetailsFailureGeneric => '无法读取专辑详情。';

  @override
  String get artistType => '歌手';

  @override
  String get artistTracksSection => '歌曲';

  @override
  String get artistAlbumsSection => '专辑';

  @override
  String get artistLoadingTracks => '正在加载歌手歌曲';

  @override
  String get artistEmptyTracksTitle => '此歌手没有可用歌曲';

  @override
  String artistEmptyTracksDetail(Object provider) {
    return '$provider 返回了空的歌手歌曲列表。';
  }

  @override
  String get artistFailureTitle => '无法加载此歌手';

  @override
  String get artistLoadingAlbums => '正在加载歌手专辑';

  @override
  String get artistEmptyAlbumsTitle => '此歌手没有可用专辑';

  @override
  String artistEmptyAlbumsDetail(Object provider) {
    return '$provider 返回了空的歌手专辑列表。';
  }

  @override
  String get artistAlbumsFailureTitle => '无法加载此歌手的专辑';

  @override
  String artistCountSummary(Object count, Object type) {
    return '$count 个$type';
  }

  @override
  String artistTrackCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String artistAlbumCount(num count) {
    return '$count 张专辑';
  }

  @override
  String artistAlbumSemantics(Object title) {
    return '$title，专辑';
  }

  @override
  String get artistEndAlbums => '歌手专辑已全部显示';

  @override
  String get artistEndTracks => '歌手歌曲已全部显示';

  @override
  String artistFailureService(Object provider) {
    return '$provider 的歌手浏览暂时不可用。';
  }

  @override
  String get artistFailureCancelled => '歌手请求已取消。';

  @override
  String artistFailureUnexpected(Object provider) {
    return '$provider 返回了异常的歌手响应。';
  }

  @override
  String artistAlbumsFailureService(Object provider) {
    return '$provider 的歌手专辑浏览暂时不可用。';
  }

  @override
  String get artistAlbumsFailureCancelled => '歌手专辑请求已取消。';

  @override
  String artistAlbumsFailureUnexpected(Object provider) {
    return '$provider 返回了异常的歌手专辑响应。';
  }

  @override
  String get queueTitle => '播放队列';

  @override
  String queueTrackCount(num count) {
    return '$count 首歌曲';
  }

  @override
  String get queueClear => '清空';

  @override
  String get queueClose => '关闭播放队列';

  @override
  String get queueEmpty => '播放队列为空，请从歌单中选择歌曲。';

  @override
  String get queueRemove => '从队列移除';

  @override
  String get queueClearTitle => '清空播放队列？';

  @override
  String get queueClearOneDetail => '这会移除队列中的歌曲并停止播放。';

  @override
  String queueClearManyDetail(Object count) {
    return '这会移除全部 $count 首歌曲并停止播放。';
  }

  @override
  String get queueFailureInvalidTrack => '无法安全表示队列中的某首歌曲。';

  @override
  String get queueFailureInvalidPosition => '该队列位置已不可用。';

  @override
  String get queueFailureCore => '音乐核心无法更新播放队列。';

  @override
  String get queueFailureInvalidResponse => '音乐核心返回了无效的队列状态。';

  @override
  String get playbackQualityMenuStandard => '标准 · MP3 128 kbps';

  @override
  String get playbackQualityMenuHigh => 'HQ · MP3 320 kbps';

  @override
  String get playbackQualityMenuLossless => 'SQ · FLAC 无损';

  @override
  String playbackQualitySelectedNext(Object quality) {
    return '已选择 $quality，将在下一首歌曲开始时应用。';
  }

  @override
  String playbackQualityPlaying(Object quality) {
    return '正在播放 $quality 音质。';
  }

  @override
  String playbackQualityFallback(Object actual, Object preferred) {
    return '此歌曲不支持 $preferred，已改用 $actual。';
  }

  @override
  String playbackQualityTooltipPreferred(Object quality) {
    return '播放音质：$quality';
  }

  @override
  String playbackQualityTooltipCurrent(
    Object actual,
    Object fallback,
    Object preferred,
  ) {
    return '播放音质：$preferred。当前音源：$actual$fallback';
  }

  @override
  String get playbackQualityFallbackSuffix => '（已回退）';

  @override
  String get playbackActualLow => '低音质';

  @override
  String get playbackSignIn => '登录';

  @override
  String get playbackOpenNowPlaying => '打开正在播放';

  @override
  String playbackOpenNowPlayingFor(Object title) {
    return '打开《$title》的正在播放页面';
  }

  @override
  String get playbackPrevious => '上一首';

  @override
  String get playbackNext => '下一首';

  @override
  String get playbackStop => '停止';

  @override
  String get playbackPause => '暂停';

  @override
  String get playbackResume => '继续播放';

  @override
  String get playbackRetry => '重试';

  @override
  String get playbackShuffleOn => '随机播放已开启。关闭随机播放';

  @override
  String get playbackShuffleOff => '随机播放已关闭。开启随机播放';

  @override
  String get playbackRepeatOff => '循环播放已关闭。切换为列表循环';

  @override
  String get playbackRepeatAll => '列表循环已开启。切换为单曲循环';

  @override
  String get playbackRepeatOne => '单曲循环已开启。关闭循环播放';

  @override
  String get playbackBrowseCurrentTrack => '浏览当前歌曲信息';

  @override
  String playbackOpenCreditedArtist(Object title) {
    return '打开《$title》的歌手';
  }

  @override
  String playbackOpenAlbum(Object title) {
    return '打开《$title》的专辑';
  }

  @override
  String playbackBrowseAlbumArtists(Object title) {
    return '浏览《$title》的专辑和歌手';
  }

  @override
  String playbackChooseCreditedArtist(Object title) {
    return '选择《$title》的歌手';
  }

  @override
  String playbackProgressSemantics(Object duration, Object position) {
    return '$position，共 $duration';
  }

  @override
  String playbackTrackStatusSemantics(Object artist, Object status) {
    return '$artist · $status';
  }

  @override
  String get playbackShowQueue => '显示播放队列';

  @override
  String get playbackVolume => '音量';

  @override
  String playbackVolumePercent(Object percent) {
    return '百分之 $percent';
  }

  @override
  String get playbackShowLyrics => '显示歌词';

  @override
  String playbackArtworkSemantics(Object title) {
    return '《$title》的封面';
  }

  @override
  String get playbackReady => '准备播放';

  @override
  String get playbackFindingSource => '正在查找可播放音源…';

  @override
  String get playbackLoadingAudio => '正在加载音频…';

  @override
  String get playbackPlaying => '正在播放';

  @override
  String get playbackPaused => '已暂停';

  @override
  String get playbackStopped => '已停止';

  @override
  String get playbackFinished => '播放完毕';

  @override
  String get playbackEngineFailure => '播放失败，请重试此歌曲。';

  @override
  String get playbackQueueInvalidTrack => '播放队列中存在无效歌曲。';

  @override
  String get playbackAuthRequired => '请登录后尝试账号授权播放。';

  @override
  String playbackCredentialRejected(Object provider) {
    return '$provider 会话已失效并被移除。';
  }

  @override
  String get playbackCredentialCleanupFailure => '会话已失效，但无法从安全存储中移除。';

  @override
  String playbackSourceUnavailable(Object provider) {
    return '$provider 未提供可播放的音源。';
  }

  @override
  String playbackNetworkFailure(Object provider) {
    return '无法连接到 $provider，请重试。';
  }

  @override
  String playbackServiceUnavailable(Object provider) {
    return '$provider 播放服务暂时不可用。';
  }

  @override
  String playbackInvalidResponse(Object provider) {
    return '$provider 返回了当前版本无法安全播放的音源。';
  }

  @override
  String get playbackCoreUnavailable => '音乐核心无法解析此歌曲。';

  @override
  String get playbackRequestRunning => '另一个音源请求仍在进行中。';

  @override
  String get playbackResolutionFailure => '无法解析此歌曲。';

  @override
  String get nowPlayingTitle => '正在播放';

  @override
  String get nowPlayingBack => '返回上一页';

  @override
  String get nowPlayingOpenMusicVideo => '打开音乐视频';

  @override
  String get nowPlayingOpenComments => '打开评论';

  @override
  String get nowPlayingComments => '评论';

  @override
  String get nowPlayingEmptyTitle => '当前没有播放内容';

  @override
  String get nowPlayingEmptyDetail => '请从音乐库、搜索或探索中选择歌曲。';

  @override
  String get nowPlayingBackToMusic => '返回音乐页面';

  @override
  String get nowPlayingLyricsUnavailable => '当前播放会话无法获取歌词。';

  @override
  String get lyricsTitle => '歌词';

  @override
  String get lyricsClose => '关闭歌词';

  @override
  String get lyricsIdleTitle => '播放歌曲后查看歌词';

  @override
  String get lyricsIdleDetail => '同步歌词会跟随播放队列中的当前歌曲。';

  @override
  String get lyricsUnavailableTitle => '没有同步歌词';

  @override
  String lyricsUnavailableDetail(Object provider) {
    return '$provider 未提供此歌曲的歌词。';
  }

  @override
  String get lyricsSignInTitle => '登录后加载歌词';

  @override
  String lyricsSignInDetail(Object provider) {
    return '当前会话无法请求 $provider 歌词。';
  }

  @override
  String lyricsSessionRejectedTitle(Object provider) {
    return '$provider 会话已失效';
  }

  @override
  String get lyricsSessionRejectedDetail => '请重新登录后再请求歌词。';

  @override
  String get lyricsFollowCurrent => '跟随当前歌词';

  @override
  String lyricsSegmentProgress(Object percent) {
    return '已完成百分之 $percent';
  }

  @override
  String get lyricsLoading => '正在加载同步歌词…';

  @override
  String lyricsAnnouncement(Object detail, Object title) {
    return '$title。$detail';
  }

  @override
  String lyricsFailureNetworkTitle(Object provider) {
    return '无法连接到 $provider';
  }

  @override
  String get lyricsFailureServiceTitle => '歌词暂时不可用';

  @override
  String get lyricsFailureRunningTitle => '另一个歌词请求仍在进行中';

  @override
  String get lyricsFailureGenericTitle => '无法加载同步歌词';

  @override
  String get lyricsFailureNetworkDetail => '会话未改变，请检查网络连接后重试。';

  @override
  String get lyricsFailureServiceDetail => '会话未改变，请稍后重新请求此歌曲。';

  @override
  String get lyricsFailureRunningDetail => '请等待当前请求结束后再重试。';

  @override
  String get lyricsFailureReplacedDetail => '歌词请求在完成前已被替换。';

  @override
  String lyricsFailureInvalidDetail(Object provider) {
    return '$provider 返回了当前版本无法安全显示的歌词。';
  }

  @override
  String get commentsTitle => '评论';

  @override
  String get commentsClose => '关闭评论';

  @override
  String get commentsLoading => '正在加载评论';

  @override
  String get commentsEmptyTitle => '暂无评论';

  @override
  String commentsEmptyDetail(Object provider) {
    return '$provider 未返回此歌曲的评论。';
  }

  @override
  String get commentsFailureTitle => '无法加载评论';

  @override
  String get commentsHot => '热门评论';

  @override
  String get commentsNewest => '最新评论';

  @override
  String commentsLoadMoreFailure(Object detail) {
    return '无法加载更多评论。$detail';
  }

  @override
  String get commentsLoadMore => '加载更多';

  @override
  String get commentsFailureNetwork => '请检查网络连接后重试。';

  @override
  String commentsFailureService(Object provider) {
    return '$provider 评论暂时不可用。';
  }

  @override
  String commentsFailureInvalid(Object provider) {
    return '$provider 返回了当前版本无法读取的评论数据。';
  }

  @override
  String get commentsFailureCore => '此版本无法使用本机评论服务。';

  @override
  String get commentsFailureRunning => '另一个评论请求仍在结束，请稍后重试。';

  @override
  String get commentsFailureCancelled => '评论请求已取消。';

  @override
  String get musicVideoTitle => '音乐视频';

  @override
  String get musicVideoClose => '关闭音乐视频';

  @override
  String get musicVideoLoading => '正在加载音乐视频';

  @override
  String get musicVideoEmptyTitle => '此歌曲没有音乐视频';

  @override
  String musicVideoEmptyDetail(Object provider) {
    return '$provider 未将 MV 与此歌曲关联。';
  }

  @override
  String get musicVideoUnavailableTitle => '音乐视频不可用';

  @override
  String get musicVideoFailureTitle => '无法播放音乐视频';

  @override
  String get musicVideoStoppedTitle => '音乐视频已停止';

  @override
  String get musicVideoStoppedDetail => '音乐播放或播放队列中的当前歌曲已改变。';

  @override
  String get musicVideoControlsSemantics => '音乐视频播放控件';

  @override
  String get musicVideoPause => '暂停音乐视频';

  @override
  String get musicVideoPlay => '播放音乐视频';

  @override
  String musicVideoFailureSource(Object provider) {
    return '$provider 未提供受支持且可播放的 MV 音源。';
  }

  @override
  String musicVideoFailureNetwork(Object provider) {
    return 'MV 请求无法连接到 $provider，请检查网络连接。';
  }

  @override
  String musicVideoFailureService(Object provider) {
    return '$provider 暂时无法提供此 MV。';
  }

  @override
  String musicVideoFailureInvalid(Object provider) {
    return '$provider 返回了应用无法安全使用的 MV 数据。';
  }

  @override
  String get musicVideoFailureCancelled => 'MV 请求已取消。';

  @override
  String get musicVideoFailureRunning => '另一个 MV 请求已在进行，请稍后重试。';

  @override
  String get musicVideoFailureCore => 'MV 播放器无法启动此视频。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSearchLabel => '搜索设置';

  @override
  String get settingsBackTooltip => '返回';

  @override
  String get settingsBackToSettingsTooltip => '返回设置';

  @override
  String get settingsSearchResultsTitle => '搜索结果';

  @override
  String settingsSearchNoMatch(String query) {
    return '没有与“$query”匹配的设置。';
  }

  @override
  String settingsSearchMatchSummary(int count, String query) {
    return '找到 $count 个与“$query”匹配的设置分类。';
  }

  @override
  String get settingsSaveFailure => '无法在此设备上保存设置。';

  @override
  String get settingsChooseCategory => '选择设置分类';

  @override
  String settingsCategorySemantics(
    String label,
    String description,
    String summary,
  ) {
    return '$label。$description。$summary';
  }

  @override
  String get settingsAppearanceLabel => '外观';

  @override
  String get settingsAppearanceCompactLabel => '主题模式';

  @override
  String get settingsAppearanceDescription => '主题模式与配色来源';

  @override
  String get settingsAppearanceBody => '选择 fura music 使用的明暗模式和配色方案。';

  @override
  String get settingsAppearanceSummarySystem => '跟随系统主题';

  @override
  String get settingsAppearanceSummaryLight => '浅色主题';

  @override
  String get settingsAppearanceSummaryDark => '深色主题';

  @override
  String get settingsAppearanceSearchKeywords =>
      '外观|主题|系统|浅色|深色|颜色|配色|色板|莫奈|Monet|壁纸|强调色|品牌|印象色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsColorSourceLabel => '配色来源';

  @override
  String get settingsColorSourceBody => '选择 Material 3 色板的取色来源。';

  @override
  String get settingsColorSourceSystem => '系统动态取色（Monet）';

  @override
  String get settingsColorSourceSystemDescription =>
      '在受支持的设备上使用壁纸或系统强调色；不可用时回退到当前音乐服务的印象色。';

  @override
  String get settingsColorSourceSystemSummary => '系统动态色';

  @override
  String get settingsColorSourceBrand => '品牌印象色';

  @override
  String settingsColorSourceBrandDescription(String provider) {
    return '使用受 $provider 启发、在不同设备上保持一致的配色。';
  }

  @override
  String get settingsColorSourceBrandSummary => '品牌印象色';

  @override
  String get settingsMusicServiceLabel => '音乐服务';

  @override
  String get settingsMusicServiceDescription => '曲库与账号来源';

  @override
  String get settingsMusicServiceBody => '选择用于浏览、搜索、推荐和账号音乐库的服务。';

  @override
  String get settingsMusicServiceSearchKeywords => '提供方|音乐服务|音源|来源|QQ音乐|网易云音乐';

  @override
  String get providerQqMusic => 'QQ 音乐';

  @override
  String get providerNeteaseCloudMusic => '网易云音乐';

  @override
  String get providerGenericMusicService => '音乐服务';

  @override
  String get providerQqMusicSettingsDescription => '首要支持的默认服务';

  @override
  String get providerNeteaseSettingsDescription => '根据能力显示功能的内置服务';

  @override
  String get settingsLanguageLabel => '语言';

  @override
  String get settingsLanguageDescription => '显示语言与系统偏好';

  @override
  String get settingsLanguageBody => '选择 fura music 的界面语言。歌曲名、歌单名等服务方内容不会被翻译。';

  @override
  String get settingsLanguageSearchKeywords => '语言|区域|系统|英文|英语|简体中文|中文';

  @override
  String get settingsLanguageFollowSystem => '跟随系统';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsLanguageSummarySystem => '跟随系统语言';

  @override
  String get settingsLanguageSummaryEnglish => 'English';

  @override
  String get settingsLanguageSummarySimplifiedChinese => '简体中文';

  @override
  String get settingsPlaybackLabel => '播放';

  @override
  String get settingsPlaybackCompactLabel => '音频质量';

  @override
  String get settingsPlaybackSectionLabel => '播放音质';

  @override
  String get settingsPlaybackDescription => '首选流媒体音质';

  @override
  String get settingsPlaybackBody => '在当前音乐服务支持时优先使用所选音质。播放器始终显示实际使用的音质。';

  @override
  String get settingsPlaybackSearchKeywords => '播放|音质|音频|标准|高品质|音乐源|HQ|SQ';

  @override
  String get playbackQualityStandard => '标准';

  @override
  String get playbackQualityHigh => 'HQ';

  @override
  String get playbackQualityLossless => 'SQ';

  @override
  String get playbackQualitySummaryStandard => '标准音质';

  @override
  String get playbackQualitySummaryHigh => '高品质';

  @override
  String get playbackQualitySummaryLossless => 'SQ 无损音质';

  @override
  String get commonLocateCurrentTrack => '定位当前歌曲';

  @override
  String partialResultsNotice(int count) {
    return '部分内容无法安全显示，已跳过 $count 项，其余结果不受影响。';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');
}
