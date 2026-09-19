# 首页推荐：来源、刷新与最近听歌策略

日期：2026-09-08。状态：实现候选，等待 Human 真实账号及视觉核对。

## 结论与已定位问题

本轮处理维护者提供的四张首页截图，不重新设计已经接受的 Shell。

1. 原大卡无论是否登录，都读匿名 `RecommendedPlaylistController`。每天按同一日期从同一列表选首图，所以不同账号看见相同起点是本地接线造成的，不足以推断 QQ 个性化推荐失效。
2. 原 12 秒轮播只切换内存中的列表；首页留存期间没有过期刷新。换图不等于服务端更新。
3. 原个人歌单区使用正确的账号 feed，但右侧按钮错误地跳到喜欢页；桌面使用 `Wrap`，放不下的第六张被排到下一行。
4. 原相关歌曲优先跟随当前队列歌曲，没有当前歌曲时取个性化歌曲的第一首。二者都不是“最近真正听过的歌曲”。

## 来源交叉核对

查阅日期均为本文件日期。开源实现能证明调用形状和各模块独立，不能证明 QQ 官方推荐排序、实验分组或固定更新周期。

| 首页区域 | 未登录 | 已登录 | 本地已有调用 / 证据 |
| --- | --- | --- | --- |
| 顶部大卡 | 公共歌单，标记 `PUBLIC SPOTLIGHT` | 账号推荐歌单，标记 `FOR YOU` | 公共：`music.playlist.PlaylistSquare/GetRecommendFeed`；账号：`music.recommend.RecommendFeed/get_recommend_feed` |
| Daily 30 | 不冒充账号每日推荐，显示公共歌单入口 | 保留独立每日歌单 | 精确匹配 `recforyou`、歌单跳转类型与 `#daily30` 标记 |
| Radar | 不冒充私人雷达，显示新歌 | 独立雷达歌曲 | `music.recommend.TrackRelationServer/GetRadarSong` |
| 个人歌单 | `Popular playlists` 公共列表 | `Your playlist treasures` 账号列表 | 只接受 `playlist` 模块和已证实的歌单卡类型；最多 64 张，非法或歧义结构报错 |
| 个性化歌曲 | 显示公共新歌 | 独立猜你喜欢歌曲 | `music.radioProxy.MbTrackRadioSvr/get_radio_track` |
| 新歌 / 更多公共歌单 | 明确公共来源 | 仍明确公共来源，不变成“你的”推荐 | 新歌与公共歌单继续保持独立 |
| 因为听过某首歌 | 可以使用本次 Fura 会话内实际播放记录 | 同样使用本次会话记录，与账号 feed 区分 | `rcmusic.similarSongRadioServer/get_simsongs`，按选中歌曲的已验证 ID 请求 |

[L-1124/QQMusicApi 的推荐模块](https://github.com/L-1124/QQMusicApi/blob/main/qqmusic_api/modules/recommend.py)分别实现首页 feed、猜你喜欢、雷达、公共歌单及新歌。首页后续页处理 `direction/page/s_num/v_cache`，这不等于“随便改参数即可换一批”。本轮保留本仓库已验证的首屏账号请求，不猜测曝光上报或后续异构 feed。

[FeelUOwn 的 QQMusic Provider](https://github.com/feeluown/feeluown-qqmusic/blob/master/fuo_qqmusic/provider.py)也区分 Daily 和 playlist 模块；[其 API 实现](https://github.com/feeluown/feeluown-qqmusic/blob/master/fuo_qqmusic/api.py)使用较旧的 feed 模块别名。采用本仓库已有证据支持的新模块名，不因为单个参考项目不同就轮询多个接口。

[Spotify 对推荐机制的官方说明](https://www.spotify.com/uk/safetyandprivacy/understanding-recommendations)区分编辑推荐、个性化、听歌/跳过/收藏信号、内容特征和趋势。它支持“多信号且不只看当前歌曲”的设计方向；不能拿它证明 QQ 使用相同权重或算法。

仓库的既有协议证据见 [Daily 与账号歌单](qqmusic-daily-recommendation-evidence.md)、[能力矩阵](qqmusic-capability-protocol-matrix.md)以及 `crates/qqmusic-client/src/personalized_tracks.rs` 的请求形状和只读实测回归。本轮没有读取保存的登录凭据、抓取真实账号内容、执行账号写入或实测多个 QQ 账号的推荐差异。

## 方案比较与取舍

| 方案 | 结论 | 原因 |
| --- | --- | --- |
| 按账号随机打乱公共列表 | 不采用 | 只能改变外观，仍不是账号推荐 |
| 登录后使用现有账号推荐 feed | 本轮采用 | 已有边界清楚的协议、解析和取消机制，直接修复数据源错接 |
| 高频重新请求 / 猜测 `v_cache` 防重复 | 不采用 | 无法保证新内容，增加风控和错误解释成本 |
| 可见时 TTL + 手动刷新 | 本轮采用 | 刷新与轮播职责清楚，后台不主动刷新 |
| 每次切歌重建相关歌曲 | 删除 | 页面跳动、频繁请求，也不符合最近听歌语义 |
| 本地实际听歌候选池 + 加权随机种子 | 本轮采用 | 可解释、可测试、不需要导入云端数据 |
| 自动导入 QQ 云端最近播放 / 上报 Fura 播放 | 不在本轮实现 | 尚无本仓库当前协议和生命周期证据；需要独立评估，不宣称不存在接口 |

## 已实现的规则

### 数据源和刷新

- 登录后大卡与个人歌单来自账号 feed；没有个人内容就显示相应空/错态，不偷偷用公共结果冒充个性化。
- 首次展示优先保留服务端账号排序；公共大卡保留按日期选择起点。轮播、上一个/下一个、暂停及减少动态效果仍是纯展示功能。
- 首页可见并处于前台时，每分钟检查一次；距上次加载/刷新尝试至少 15 分钟才自动重取。返回首页、应用恢复前台也检查。15 分钟是 Fura 的初始刷新策略，不是 QQ 官方承诺。
- `Refresh` 对账号推荐、Daily、猜你喜欢、雷达、新歌和公共歌单发起一个有限请求组；组内重复点击合并。不会刷新账号身份资料，也不会清掉 Discover 的分页或分类状态。
- 在途自动组不重复创建；失败也更新尝试时间，避免反复进出页面形成自动重试风暴。单区错误仍可重试，手动刷新不受 15 分钟限制。
- 账号内容的瞬时网络/服务错误保留上一批并显示提示；成功空结果更新为空；认证拒绝清空对应私人资源并沿用既有重新登录流程。公共、新歌和 Radar 继续使用其原有独立加载/错误状态。
- 成功刷新明确提示 QQ 可能返回相同内容。日期或随机重排不作为“服务端已更新”的证据。

### 最近听歌与相关歌曲

- Rust `music-domain::RecentListening` 是唯一候选与选择规则所有者；Flutter 只转发实际播放器曲目、进度和播放状态，Bridge 提供单调时钟和抽样熵。
- 本次 Shell 会话最多保留 30 首去重歌曲。累积有效播放达到 30 秒或短歌时长的一半即入池；未知时长用 30 秒，下限一秒。
- 仅点选、解析音源、暂停、缓冲和跳跃式 seek 不计作有效播放。相邻观测相隔超过五秒的区间不推断为持续播放，避免挂起恢复造成虚假记录。
- 对候选按最近顺序赋权，并在有替代项时避开当前歌曲和上一种子。随机性是 Fura 的实现策略，不宣称还原 QQ 算法。
- 首次形成有效候选时可加载相关曲目；此后进度变化、切歌、清队列都不会自动改掉已展示的一组。`Change picks` 或首页刷新才重新选种子；单一候选不会为了看起来不同而反复请求同一组。
- 标题显示 `Because you listened to …`；没有实际记录时明确提示开始听歌，不拿猜你喜欢或队列意图伪造历史。
- 会话记录不写磁盘、不上传。退出/切换账号或关闭应用后重建上下文；重新启动时此区可能为空。这是本轮的明确功能边界，不等价于官方跨设备听歌历史。
- 相关歌曲仍由现有 QQ 相似歌曲接口返回；没有混入外部音源、改动播放授权或改变用户收藏。

### 布局与返回行为

- 歌单棚所有尺寸均使用惰性横向列表。桌面正常宽度保持一行；空间不足不再换行，提供滚动条和左右按钮，支持鼠标拖动、触控和触控板。
- 个人歌单不再只截取前六张：展示已有有界账号结果中的所有卡片，不新增无限 feed。
- 个人歌单标题右侧改为 `Refresh`，不再跳喜欢；原来的导航栏和移动快捷入口仍可打开喜欢页。
- 相同歌单在大卡和列表同时出现时，分别记录返回焦点所属区域；保留横向及纵向滚动位置。
- Home 只订阅当前曲目身份变化来更新选中行，不因每次进度/音量/歌词事件重建整页。

## 验证与人工验收

自动回归覆盖真实播放资格、去重/容量、候选回避、会话隔离、刷新合并、瞬时失败保留/认证拒绝清空、相关请求取消及迟到结果、登录/访客数据源、可见/前后台生命周期、横向末项可达和详情返回。最终命令结果见 `PROGRESS.md`，不得用离线 fixture 推断真实账号推荐质量。

执行记录：Rust `cargo test --workspace` 428 个离线测试通过，12 个显式 live 测试保持默认忽略；Rust format 与严格 Clippy 通过。Flutter 全量 492 个测试通过，`dart analyze --fatal-infos` 用于最终静态检查，Linux Release 已构建。该机器的 `flutter analyze` 在含中文路径的 LSP 初始化帧解析处退出，改用同一 SDK 的 `dart analyze` 完成检查；未修改 SDK，也不将该工具异常算作通过。

视觉回归使用 `HOME_VISUAL_REVIEW=true` 的 canonical fixture，显式加载本机 Roboto 和 MaterialIcons 后生成并检查桌面、手机、以及新增中型横向末项截图。字体文件路径只通过测试参数传入，不加入产品资源；CJK 回退、真实封面和设备视觉验收仍有限制。截图是测试数据，不是真实账号推荐或推荐质量实测。

人工核对：

1. 同一版本分别未登录、登录，确认大卡来源标签及个人列表变化；登录后依然可能有与其他账号重叠的推荐。
2. 点击 Refresh，确认独立错误提示与成功提示；服务端返回同一批不判作前端未发送请求。
3. 在不同窗口宽度、手机触控和桌面鼠标下浏览歌单末项，打开再返回，核对位置及焦点。
4. 本次运行实际听几首歌曲超过门槛，再换歌；既有相关列表不应跟着立即跳动，点击 Change picks 应在可用候选中改变种子。
5. 退出再登录或重启应用，确认不会遗留上一个上下文的本地记录；新的空状态应符合上述会话边界。

仍未证明：QQ 官方真实随机规则、服务端刷新间隔、不同账号推荐重叠率、真实网络延迟，以及手机实体设备与所有字体缩放条件的最终观感。

## 2026-09-19 官方歌单来源复核

状态：`WIRE_EVIDENCE_CONFIRMED`；匿名生产接线已实现，等待 Human 真实网络与视觉核对。

本轮先复核仓库内现有 `PlaylistSquare/GetRecommendFeed`，确认它仍只代表歌单广场公开
推荐。随后找到并交叉验证了另一条独立协议族：

- [`jsososo/QQMusicApi` commit `13b08afd3180cc74d76fff208956b77a560abd22`](https://github.com/jsososo/QQMusicApi/blob/13b08afd3180cc74d76fff208956b77a560abd22/routes/recommend.js)
  明确把分类 `3317` 标注为“官方歌单”，并构造
  `playlist.PlayListPlazaServer/get_playlist_by_category`；参数为 `id`、`curPage`、
  `size`、`order=5`、`titleid`，匿名 GET 将序列化的 musicu 请求放在 `data` query 中。
  同仓库文档把响应解释为 `playlist.data.total` 与 `v_playlist`。该来源较旧，只作为
  request-shape 和分类语义候选，不单独用于生产晋级。
- [`yakult-green-tea/qq-music-api` commit `b369be4ab8e0a7b6bdfba971e107faeccae3541f`](https://github.com/yakult-green-tea/qq-music-api/blob/b369be4ab8e0a7b6bdfba971e107faeccae3541f/src/controllers/getRecommend.ts)
  独立使用相同 module/method、`curPage/size/order/titleid` 结构，并同时使用
  `music.web_category_svr/get_hot_category` 获取分类。它不单独证明 `3317` 的语义，
  但交叉证明该服务族和参数结构持续存在。
- 2026-09-19 对 `https://u.y.qq.com/cgi-bin/musicu.fcg` 做了两组串行、匿名、只读、
  有界探测，不携带 Cookie 或账号凭据。`music.web_category_svr/get_hot_category`
  返回全局/方法 code 0，并在当前
  `category.data.category[0].items[3]` 结构化分类项中直接返回
  `item_id=3317`、`item_name=官方歌单`。随后
  `playlist.PlayListPlazaServer/get_playlist_by_category`
  使用 `id=titleid=3317`、`curPage=1`、`size=3`、`order=5` 返回 code 0、
  `total=736` 和 3 条 `v_playlist`。相邻页也返回成功且 identity fingerprint 不同，
  两个 3-row 页面有 2 个相同 identity；因此 `curPage` 是唯一 continuation，调用方
  必须按真实 Playlist identity 去重，不能用可见行数推算分页。
- 同一个当前分类响应只返回一个 `热门推荐` group；其中还能直接验证
  `全部分类(-100)`、`国语(1)`、`英语(3)`、`轻音乐(49)` 等少量公开分类，但没有返回
  Human 截图中的完整“华语 / 欧美 / 韩语 / 日语 / 粤语 / 场景 / 心情 / Urban / ACG /
  艺人歌单”矩阵。因此本轮只晋级已直接验证的固定“官方歌单”source，不发布一个伪完整
  category-list capability，也不把当前热门分类集合当作官方页面完整 taxonomy。
- 当前响应 row 的字段集合直接包含 `tid`、`title`、大/中/小 cover URL、
  `creator_info`、`access_num`、`tag_names`。Fura 只映射这些真实字段；没有从标题或
  creator 名字猜测“官方”身份，也没有伪造 Track count。

另外，腾讯公开 CDN 的 QQ Music Windows 22.22 安装包经 Microsoft WinGet manifest
SHA-256 校验后做了只读静态扫描；没有找到可用于提升上述结论的明文 route。这个负面
结果不用于否定协议，也没有启动 Windows 程序、访问本地账号或读取 Cookie。

实现因此新增独立 `OfficialPlaylistsProvider`、QQ Client decoder、typed Flutter Bridge、
`OfficialPlaylistGateway/Controller`，与 `RecommendedPlaylistsProvider` 保持不同 trait、
请求 DTO、响应 DTO 和 presentation owner。Home 的 `HomeSpotlightController` 优先使用
官方 source 的 8 条有界候选；previous/next 与 12 秒 rotation 只在内存窗口中移动，
不会在 timer tick 请求网络。官方 source 失败或为空时才使用 public recommendation
的 3 条有界窗口作为 fallback，并显示“公开精选 / PUBLIC SPOTLIGHT”；只有 official
source 有内容时显示“官方歌单 / OFFICIAL PLAYLIST”。Discover 仍只使用
`PlaylistSquare/GetRecommendFeed`，
账号“你的歌单宝藏”仍只使用 personalized playlists。官方条目的 `tid` 继续映射为现有
`catalog:<tid>` Playlist identity，详情与 logical Play All 复用现有页面和 continuation。
