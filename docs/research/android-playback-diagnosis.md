# Android 歌曲可检索但无法播放：根因诊断与修复方案

## 结论

当前 Android “能够搜索并展示歌曲信息，但点击后不能播放”的首要根因，具有高可信度：**QQ Music 媒体解析链路把 CDN 下发的明文 `http://` 音频地址原样交给了 Android `MediaPlayer`，而应用面向 Android API 36、没有允许明文流量；Android 9 / API 28 起此类应用默认禁止明文网络流量，`MediaPlayer` 会直接拒绝该请求。**[^android-cleartext-app][^android-network-security]

这不是同一条 HTTPS 元数据链路的失败。搜索、歌曲详情和 VKey 请求都由 Rust Core 通过 HTTPS 请求 QQ Music API，所以它们可以成功；最终音频则走 Flutter `audioplayers` → Android 平台 `MediaPlayer`，使用的是另一条 URL 和另一套平台网络策略。

2026-09-10 的匿名、限量在线核对进一步闭合了证据链：

- `music.audioCdnDispatch.cdnDispatch / GetCdnDispatch` 成功返回，5 个 CDN base 全部是 HTTP；
- 生产选择逻辑最终生成的音频源也是 HTTP；
- 对同一条已解析媒体路径进行 Range 请求时，HTTP 与把 scheme 改为 HTTPS 均返回 `206`、有效 MP3 起始字节；
- 是否携带 `Referer` 不影响该样本；
- 涉及的 4 个唯一 CDN host 均能完成 HTTPS TLS 验证。

因此推荐修复不是放开 Android 明文流量，而是：**在 Rust QQ Provider 内对可信 QQ Music 音频 CDN 做严格 host 校验，然后把可验证的 HTTP base 规范化为 HTTPS，再通过 typed bridge 向 Flutter 暴露 HTTPS 媒体源。**

本轮已在 Rust QQ Music client 内落地该修复：可信 CDN base 会先通过严格 host/URL 结构校验，再统一规范化为 HTTPS；Flutter 与 Android manifest 均未放开明文流量。仓库当前没有连接 Android 设备，因此最终真机确认仍属于 Human Review；在真机观察到 QQ 远程媒体播放进度大于 0 之前，不应把问题标记为完全解决。

## 2026-09-15 补充诊断：系统播放焦点与网易云 Android 媒体

HD-030 将两个现象作为独立故障分支处理，没有用网易云修复代替系统
播放修复，也没有用系统通知出现代替真实音频进度。

### A. Android 系统播放生命周期

再次核对锁定依赖源码后，root-owned `AppPlaybackHost`、唯一 Queue、
`ProjectSystemAudioHandler`、manifest Service/Receiver 和原生 MediaSession
生命周期仍然成立。`audio_service` 0.18.19 会在 handler 发布 playing
状态时激活 MediaSession、进入 media foreground service 并持有 wake lock；
通知、锁屏和媒体键再通过同一 handler 回到 `QueuePlaybackController`。

新发现的实际冲突位于音频焦点：`audioplayers_android` 5.3.0 默认用
`AUDIOFOCUS_GAIN` 自己请求焦点，而 Fura 又把焦点/中断策略交给
`audio_session` 0.2.4；同时旧代码只执行
`AudioSession.configure(music)`，没有在播放前显式 `setActive(true)`。
这会使解码播放器与系统会话拥有不一致的焦点生命周期。

修复保持原 owner 不变：加载源之前把 `audioplayers` Android context 的
focus 设置为 `none`，播放前由 `audio_session` 显式激活，暂停、停止、完成、
失败和 dispose 时释放。没有增加 `just_audio_background`、第二个播放器、
第二个 Queue、第二个 handler 或自制 Android Service。初始化、配置、状态
发布、系统命令和引擎阶段增加了去敏诊断；`AudioService.init` 也增加了
可注入的成功/失败测试缝，失败仍只降级为包住同一 controller 的前台播放。

### B. 网易云 Android 媒体传输

一次显式开启、匿名、严格限量的在线探测得到以下粗粒度结果：

- 当前媒体 API 返回 `http`、精确 host `m701.music.126.net`、格式 `M4a`、
  TTL 1200 秒；
- 对同一个 path/query 分别用 HTTP 和 HTTPS 发
  `Range: bytes=0-4095`，两者均为 206、4096 bytes、MP4 `ftyp` 签名；
- 两个变体都不需要额外 Referer/User-Agent/Cookie header；API 的
  `Content-Type` 为 `audio/mpeg`，但签名与既有 M4A 映射一致。

因此 Android 的确定性阻塞是网易云把短期音频地址以明文 HTTP 返回，
不是当前样本缺少 header，也不是应该全局放开 cleartext。修复位于网易云
Rust 私有边界：只有形如 `m` + 1–4 个 ASCII 数字 +
`.music.126.net` 的精确自有 CDN host 可以从 HTTP 原位升级为 HTTPS；
path/query 完整保留，userinfo、显式端口、fragment、伪装后缀、其它 label
和其它 scheme 均拒绝。已是 HTTPS 的合法响应继续原样保留。QQ 的 host
规则未复用，也没有 source substitution、代理或媒体预下载。

修复后的同一在线测试输出 HTTPS，HTTP/HTTPS A/B 仍均取得相同的 206
和媒体签名。该结果证明 transport 规范化成立，不证明用户账号下每首歌曲
都有播放权益。真实登录、实际音频进度和系统控件反向操作仍必须按
[Android runtime checklist](android-system-playback-runtime-checklist.md)
由 Human 在物理设备上验收。

## 证据强度与调查边界

| 结论 | 强度 | 依据 |
| --- | --- | --- |
| 元数据 HTTPS 链路正常 | 已由现有 Android 集成测试设计和用户现象支持 | Android 专用 live test 能从 Rust Core 取匿名 QQ 搜索页；用户也能看到歌曲信息 |
| 生产媒体源可能为 HTTP | 已由代码和 2026-09-10 线上响应确认 | CDN parser 接受 HTTP，URL 拼接保留 scheme，线上 dispatch 的全部候选为 HTTP |
| Android 平台拒绝该 HTTP 媒体源 | Android 官方行为 + 当前 manifest/target + 播放器实现共同证明 | API 28+ 默认禁止明文；MediaPlayer 明确遵守；当前 target 36 且无明文例外 |
| 同一路径可直接升级为 HTTPS | 已对一个匿名、可播放样本实测 | HTTP/HTTPS 均为 206 且包含有效 MP3 字节；4 个 CDN host TLS 均通过 |
| `Referer` 是当前主因 | 已排除该样本 | 带与不带 `Referer` 的 Range 响应一致 |
| 音频编码器不支持是当前主因 | 高概率排除 | 当前样本为标准 MP3，Android 官方支持；传输策略在解码前已可阻断 |
| 账号/VKey 无效是当前主因 | 高概率排除当前样本 | 同一个解析后的资源路径可通过 HTTP/HTTPS 取到有效字节 |
| 修复后所有歌曲和所有真机必然可播 | 尚未证明 | 仍需对真实设备、不同音质、后台恢复、OEM 行为做验收 |

为避免泄漏，在线核对没有输出或持久化完整歌曲身份、媒体 URL、VKey、Cookie 或账号凭证；只保留 scheme、host、状态码、字节数和签名类型等粗粒度结果。

## 实际数据流与故障点

```text
Flutter 页面
  │ 搜索/详情
  ▼
typed flutter_rust_bridge
  ▼
Rust Core / QQ Provider ── HTTPS ──> u.y.qq.com 元数据与 VKey
  │
  │ ResolvedMediaSource(uri = http://QQ-CDN/...)
  ▼
AudioplayersForegroundAudioEngine
  ▼
audioplayers_android 5.3.0
  ▼
android.media.MediaPlayer.setDataSource(http://...)
  ▼
Android Network Security Policy 拒绝明文媒体流  ← 当前故障点
```

### 1. QQ Core 保留了 HTTP scheme

`crates/qqmusic-client/src/media_resolution.rs` 中：

- QQ Music RPC 入口本身是 HTTPS：`MUSICU_URL = https://u.y.qq.com/cgi-bin/musicu.fcg`；
- `parse_cdn_bases` 同时接受 `http` 和 `https`；
- `join_source_path` 要求拼接后与 base 的 scheme/authority 相同，因此刻意保留了 HTTP；
- `cdn_preference` 只按 host 形态排序，没有优先 HTTPS；
- 单元测试 fixture 明确使用 HTTP，并断言最终 URI 为 `http://dl.stream.qqmusic.qq.com/...`。

换言之，当前行为不是 Android 偶发改写，而是 Rust 解析器的稳定、被测试锁定的输出。

### 2. Flutter 播放适配器原样传递 URL

`apps/flutter/lib/playback/foreground_audio_player.dart` 的 `loadRemote` 同时允许 HTTP/HTTPS；`prepare` 直接执行 `AudioPlayer.setSourceUrl(source.toString())`，没有 scheme 升级、代理下载或 provider host 约束。

这层保持 provider-neutral 是正确的。QQ 私有 CDN 规则应留在 QQ Provider；不建议在 Flutter 层看见 `qqmusic.qq.com` 就替换字符串。

### 3. Android 后端使用平台 MediaPlayer

锁定依赖为 `audioplayers_android 5.3.0`。其 Android `UrlSource` 对远程 URL 调用平台 `MediaPlayer.setDataSource(url)`，没有独立的 HTTPS 代理或 Rust 下载器。该包就是 `audioplayers` 的 Android endorsed implementation。[^audioplayers-android]

Android 官方文档明确说明：target API 28 及以上应用默认 `usesCleartextTraffic=false`；当该设置为 false 时，`MediaPlayer` 等平台组件会拒绝明文请求。[^android-cleartext-app] 当前应用：

- `targetSdkVersion = 36`；
- manifest 有 `INTERNET`，但没有 `usesCleartextTraffic=true`；
- 没有允许 QQ CDN 明文的 Network Security Config；
- 新构建 APK 的 manifest 同样显示 target 36。

这与“元数据成功、远程音频 load 失败”的症状完全吻合。

## 2026-09-10 在线协议核对

本次只使用匿名、公开数据完成最小请求，不使用用户账号，也不输出完整授权媒体地址。

### CDN Dispatch

请求：

- Host/path：`POST https://u.y.qq.com/cgi-bin/musicu.fcg`
- Module：`music.audioCdnDispatch.cdnDispatch`
- Method：`GetCdnDispatch`

响应的 outer code、RPC code 和 data code 均为 0。5 个 base 全部为 HTTP，host 分布为：

- `aqqmusic.tc.qq.com`（重复出现）；
- `sjy6.stream.qqmusic.qq.com`；
- `ws6.stream.qqmusic.qq.com`；
- `ws.stream.qqmusic.qq.com`。

### 匿名 VKey 与媒体探测

从最多 10 个公开新歌候选中找到 1 个可解析标准 MP3 的匿名样本。对同一 path 做 `Range: bytes=0-4095`：

| 变体 | 状态 | 字节数 | 内容判断 |
| --- | ---: | ---: | --- |
| HTTP，无 Referer | 206 | 4096 | 有效 MP3 签名 |
| HTTP，有 Referer | 206 | 4096 | 有效 MP3 签名 |
| HTTPS，无 Referer | 206 | 4096 | 有效 MP3 签名 |
| HTTPS，有 Referer | 206 | 4096 | 有效 MP3 签名 |

所有 4 个唯一 host 的 HTTPS 根路径探测均完成 TLS 证书验证；根路径返回 403 是没有资源 path 时的预期业务响应，关键是 TLS 端点真实存在。由此可见：

1. 当前样本不是缺 VKey或资源不存在；
2. 当前样本不依赖 Referer；
3. 只把同一可信媒体 URL 的 scheme 升级为 HTTPS 即可绕开 Android 的明文策略，同时保留 path/query/VKey；
4. 不需要把媒体内容先下载到 Flutter，也不需要引入 localhost sidecar。

## 推荐修复

### 已实施结果（2026-09-10）

实际改动保持在既有 `Flutter UI → typed FFI → Rust Core → QQ Music` 边界内：

- `qqmusic-client` 的 CDN base 解析现在只接受 `aqqmusic.tc.qq.com`、`stream.qqmusic.qq.com` 及严格域边界下的 `*.stream.qqmusic.qq.com`；
- 可信 HTTP base 在拼接媒体 path 之前转换为 HTTPS，重复 base 去重；已有 HTTPS 与合法目录 path 保持不变；
- 第三方 host、伪装后缀、userinfo、自定义端口、query、fragment、非 HTTP(S) scheme 和非目录 path 会被过滤；全部候选非法时返回协议错误，不向 Flutter 暴露不可信源；
- Provider 测试已把 HTTP dispatch fixture 的最终期望锁定为 HTTPS，防止以后回退到明文输出；
- Android manifest 没有加入 `usesCleartextTraffic=true`，也没有引入 localhost proxy、下载中转或 Flutter 侧 QQ 域名判断；
- Android live integration test 现可在显式设置 `QQMUSIC_ANDROID_PLAYBACK_LIVE_TESTS=true` 时，从匿名搜索到媒体解析再进入现有 `AudioplayersForegroundAudioEngine`，以静音方式等待 `positionMs > 0`；断言和失败信息不输出完整 URI；
- 系统媒体会话初始化失败会写入固定、去敏的一次性诊断信息，同时继续保留前台播放，不把系统控制绑定失败升级为歌曲播放失败；
- Android backup/data-transfer 规则明确排除应用数据，避免 QQ credential/session 随备份迁移；manifest 显式声明通知能力，但 media-session 播放不依赖用户授予普通通知权限。

本轮没有修改 Rust，其完整工作区基线沿用上轮 535 passed / 0 failed / 20 explicit live-Human ignored、Rust format 和 workspace/all-target strict Clippy 通过的结果，没有为本项改动重跑。本轮 Flutter 528 项测试全部通过；`dart analyze` 无问题；237 个 Dart 文件格式检查无改动；Linux system-playback real session-bus integration 与 ARM64 Release APK 构建成功。最新 APK 为 43,768,152 bytes，只含 `arm64-v8a`，并通过 16 KB zip alignment；本轮 Android Release lint 为 0 error、1 个已有的 Gradle 版本提示 warning。真机远程媒体播放和新的 app-lifetime 系统媒体生命周期仍待 Human Review。

### P0：在 QQ Provider 内规范化可信 CDN 为 HTTPS

现已把 `parse_cdn_bases` 改造成 provider-private 的规范化步骤，语义如下：

1. 解析 URL，继续拒绝 userinfo、query、fragment，以及不是目录形式的 base；
2. 只接受明确证实的 QQ 音频 CDN host：
   - 精确 host `aqqmusic.tc.qq.com`；
   - 精确 `stream.qqmusic.qq.com` 或以 `.stream.qqmusic.qq.com` 为域边界后缀的子域；
3. 拒绝自定义端口，或只允许与输入 scheme 对应的默认端口；
4. 对可信 `http` base 设置 scheme 为 `https`，清除显式默认端口；
5. 已是 HTTPS 的可信 base 保持不变；
6. host 不可信、形似但越界（例如 `stream.qqmusic.qq.com.evil.test`）或 URL 结构异常时直接拒绝，不把带 VKey 的 path 发给它；
7. `ResolvedMediaSource` 只向 domain/Flutter 输出 HTTPS。

这里的 host 白名单既是 Android 兼容修复，也是安全边界。当前 parser 只验证“有 host”，理论上如果上游响应被污染，就可能把授权 path 拼到任意域名；升级 scheme 时应顺手收紧这一边界，但不要泛化成新的通用网络框架。

### 为什么不建议全局放开 cleartext

不要用以下方式作为正式修复：

```xml
<application android:usesCleartextTraffic="true" ... />
```

也不要使用 `base-config cleartextTrafficPermitted="true"`。Android 官方指出，明文连接缺少机密性、真实性和防篡改保护；媒体 URL 中还可能携带短期授权材料。[^android-cleartext-app][^android-network-security]

如果未来出现一个确实不支持 HTTPS 的 QQ CDN，才应基于新的线上证据讨论 domain-scoped Network Security Config；即便如此，它也应是有期限、有遥测、有明确 host 的兼容兜底，而不是默认路线。当前已验证的 CDN 不需要这个例外。

### 为什么不在 Flutter 层改 URL

Flutter 播放层不应理解 QQ 的域名和协议：

- 会破坏现有 `Flutter UI → typed FFI → Rust Core → Provider` 边界；
- 其他平台或其他 provider 会继承一段不属于自己的规则；
- Flutter 字符串替换更容易漏掉 host 边界、端口、userinfo 和重定向风险；
- Rust 已经拥有 URL parser、CDN 排序和 media-source 测试，是最小责任面。

### P0 测试改动

已补充并通过这些 Rust 单元测试：

- HTTP dispatch fixture 最终返回 HTTPS；
- 原生 HTTPS base 保持 HTTPS；
- `aqqmusic.tc.qq.com` 和合法 `*.stream.qqmusic.qq.com` 可接受；
- `stream.qqmusic.qq.com.evil.test`、任意第三方 host、userinfo、自定义端口被拒绝；
- path、filename 和 query/VKey 不因 scheme 规范化而改变；
- Debug 输出继续不包含完整 host、VKey 或授权 URI；
- 多个 CDN base 中一个无效时，仍可使用后续合法候选；全部无效时返回明确协议错误，而不是空字符串。

原先断言 HTTP URI 的测试也已更新为 HTTPS，避免旧行为重新进入生产输出。

### P0 Android 端到端验收

新增 opt-in、不会在普通 CI 自动访问 QQ 的 Android live integration test：

1. 使用匿名公开检索取得一个标准音质 MP3 track；
2. 经 Rust Core 正常解析媒体源；
3. 只断言 scheme 为 HTTPS，不打印 URL；
4. 通过现有 `ForegroundAudioEngine` 加载；
5. 音量设为 0；
6. 调用 play，并在有界超时内观察首个 `positionMs > 0`；
7. stop/dispose，确认没有遗留 session。

随后在至少一台 API 28+ 的 ARM64 真机上人工播放。验收时以“实际进度推进”为准，不能只以 URL resolve 成功、播放器状态变为 loading 或按钮图标变化为准。

### P1：改善不泄密的阶段诊断

当前 Flutter adapter 会把底层错误折叠为 `load`/`playback`，这是为了防止 `AudioPlayerException.toString()` 把带授权信息的 source URL写进日志，安全方向正确。但这使 Android 网络策略、解码错误和音频焦点失败看起来一样。

建议保留粗粒度 UI 错误，同时增加结构化、去敏的内部诊断字段：

- stage：`resolve` / `engine_prepare` / `engine_play` / `position_timeout`；
- platform：Android；
- scheme：HTTP/HTTPS；
- format：MP3/M4A/FLAC；
- native error code / exception type（经过白名单映射）；
- 是否发生重定向、是否取得首帧/首个正进度。

禁止记录完整 URL、query、VKey、Cookie、账号 ID，以及可能内嵌 URL 的原始 exception message。

## 为什么其他候选不是当前首因

### Rust TLS 初始化

`FuraApplication.onCreate` 在进程启动时加载 Rust native library 并初始化平台证书验证器；Android 专用集成测试也专门覆盖首次 QQ Music HTTPS 请求。若这一层失败，搜索/歌曲信息也会失败，而不是只在交给播放器后失败。

### 权限

manifest 已有 `INTERNET`，无需运行时授权。已有前台播放服务所需的 `FOREGROUND_SERVICE` 和 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`，与 Android 官方 MediaSessionService 要求一致。[^android-background-playback]

### 编码格式

Android 平台支持 MP3，亦支持 AAC/M4A 和 FLAC（具体 container/API 组合存在版本条件）。[^android-formats] 当前线上探测样本为标准 MP3；明文网络策略会在解码前失败，所以不应先迁移解码器来掩盖传输错误。

如果 HTTPS 修复后仅特定 SQ/HQ 档仍失败，再按格式分别验证：

- 标准 MP3；
- 低码率/回退 M4A；
- SQ FLAC；
- 24-bit、较高采样率和异常 container 的设备差异。

### Referer / Header

当前样本带或不带 Referer 都能取得相同的 Range 内容；`audioplayers_android` 不支持本项目在此处额外注入 QQ header 也不是这个样本的阻塞因素。未来若不同 host 返回 403，应以具体响应证据建模，不能一概加入伪装 header。

### 音频焦点

Android 15 起，target 35+ 的应用只有在顶层应用或运行 foreground service 时才能取得音频焦点；否则请求会失败。[^android-audio-focus] 用户从前台点击播放时满足“顶层应用”条件，所以它不解释当前普遍的首次播放失败，但会影响锁屏/后台恢复，需单独验收。

## 现有测试为何没有发现

`apps/flutter/integration_test/playback_engine_test.dart` 存在三类覆盖：

- Android 能执行的只是本地临时 MP3 文件播放；
- 远程 loopback MP3 测试被 `skip: !Platform.isLinux` 限制为 Linux；
- M4A 与 FLAC 的远程测试同样仅在 Linux 执行。

修复前，`apps/flutter/integration_test/android_anonymous_https_test.dart` 只验证 Rust Core 能通过 Android HTTPS 读取 1 条搜索结果，没有继续执行媒体解析和播放器加载。本轮已在同一文件补充显式 opt-in 的远程播放闭环；它只有在 Android 设备和 `QQMUSIC_ANDROID_PLAYBACK_LIVE_TESTS=true` 同时存在时才运行，普通离线 CI 不会访问 QQ Music。

所以当前测试分别证明了“Android 能解本地 MP3”和“Rust 能取 HTTPS 元数据”，中间恰好缺少“Android 播放 QQ HTTPS/HTTP 远程媒体源”的交叉覆盖。

历史 readiness 记录中的 Android 本地 MP3 通过也不能代替远程流验收；Linux loopback HTTP 测试则不受 Android Network Security Policy 约束。

## 其他 Android 平台排查结果

### A. Release 构建：当前可构建，但仍是开发签名

执行：

```text
flutter build apk --release --target-platform android-arm64
```

结果：成功，生成 43.0 MB ARM64 APK。当前 artifact：

- minSdk 24；
- target/compile SDK 36；
- 仅包含 `arm64-v8a`；
- APK Signature Scheme v2 校验通过；
- 16 KB zip alignment 校验通过；
- 仍由 Android Debug certificate 签名，因为 `build.gradle.kts` 的 Release 配置明确引用 debug signing；官方明确指出 debug certificate 不适合应用商店发布。[^android-signing]

因此它可用于 Human Review 和真机安装，但不是可发布产物。

### B. Android lint：0 error、1 warning

在先通过 Flutter 正式构建刷新插件注册表后，执行：

```text
./gradlew :app:lintRelease -Ptarget-platform=android-arm64 --console=plain
```

结果：lint 完整运行，报告 0 个错误、1 个警告。已处理：

- manifest 显式声明 `POST_NOTIFICATIONS`，但按照 Android media-session 豁免语义，不让前台点歌依赖运行时通知授权；[^android-notification]
- `AudioService` 继续采用 `audio_service 0.18.19` 文档要求的 exported MediaBrowser 配置，并对该已核对场景做精确 lint suppression；未盲目增加可能阻断 Android Auto/系统媒体浏览器的 binder permission；
- 增加 Android 12+ `dataExtractionRules` 并关闭 legacy full backup，明确排除 credential/session 和数据库；
- 合并多余的 `drawable-v21` 启动背景到基础 `drawable`，保持系统主题背景并清除 obsolete qualifier。

唯一剩余 lint warning 是 Gradle wrapper 9.3.1 有 9.7.1 可用。构建日志还包含 AGP 9 built-in Kotlin 迁移提醒、部分第三方插件 Java 8 target 提醒，以及 Android Studio/command-line SDK XML 版本差异提醒。这些涉及 Flutter SDK与多个插件的升级矩阵，应单列依赖迁移任务，不能和播放 P0 混在一次改动中。

验证期间还确认一个工具并发陷阱：同一工作区运行 `flutter run -d linux --debug` 或 Flutter tests 时，会把共享的 Android `GeneratedPluginRegistrant.java` 重写为 Debug 版本，其中包含 dev-only `integration_test`；若此时绕过 Flutter 工具直接并发执行 Release Gradle task，会出现 Release classpath 找不到测试插件。停止并发 Debug run、先执行正式 `flutter build apk --release` 后，Release 构建与 lint 均正常。这不是生产依赖缺失，不应通过把 `integration_test` 打入 Release 来规避。

### C. 后台播放和系统媒体控制

2026-09-11 的静态复核确认这里不是“Android 端没加播放插件”：

- `pubspec.yaml` 已锁定 `audio_service 0.18.19`、`audio_session 0.2.4` 和 `audioplayers 6.8.1`；
- Flutter 生成的 Android plugin registrant 已注册 `audio_service`、`audio_session` 与 `audioplayers_android`；
- manifest 已具备唤醒锁、media-playback foreground-service 权限、`AudioService` 与 `MediaButtonReceiver`；
- `MainActivity` 已继承 `AudioServiceActivity`；
- `ProjectSystemAudioHandler` 已声明系统 Play/Pause/Seek/Next/Previous/Shuffle/Repeat 到 `QueuePlaybackController` 的委托。

但后续物理 Android 操作推翻了“注册齐全就等于系统控制可用”这一过早结论：用户在实际系统播放面板中无法控制音乐。重新追踪生命周期发现，真正的 `QueuePlaybackController`、`TrackPlaybackController` 和音频引擎由 `UserLibraryPage` 的 `State` 创建、再临时 attach 给 handler，并随该页面 dispose 而 detach/dispose；`AudioService` 只是借用页面对象。这样 Activity、登录态或导航生命周期一变化，原生 MediaSession 仍可能存在，但已没有稳定的播放 owner 可供系统命令调用。这是 Dart 所有权错误，不是 manifest 缺项。

因此增加 `just_audio_background` 或第二个媒体服务仍不是正确修复。`audio_service` 本来就负责 Android Service、MediaSession、通知、锁屏和耳机键；项目只需提供一个把现有 Rust Queue/Provider 路径接到插件回调的薄 handler。`just_audio_background` 面向单一 `just_audio` player 的简单场景，而本项目有 Rust positional Queue、动态媒体解析、歌词与多 Provider 生命周期，直接替换会同时迁移播放引擎并引入第二套状态真相。[^audio-service][^just-audio-background]

2026-09-12 已按插件推荐的 owner 方向收口：

1. 新增 root-owned `AppPlaybackHost`，在 `main()` 中、账号凭证恢复之前一次性创建 Queue、播放控制器、歌词控制器和音频引擎；
2. `ProjectSystemAudioHandler` 构造时永久持有这个唯一 controller，`AudioService.init` 接收同一个 handler；页面只能监听和调用，不能 attach/detach/dispose；
3. `UserLibraryPage` 销毁只移除自己的 listener，登录、退出、Provider 切换或页面导航不再拆掉系统命令路径；应用根销毁才关闭 handler 与播放 owner；
4. `AudioService.init` 失败时，保留同一个 controller 作为 foreground-only host，不另造播放器或 Queue；audio-focus 配置失败也不反向拆掉已经初始化的 MediaSession；
5. 保留 `androidStopForegroundOnPause=false`、`androidResumeOnClick=true`、专用单色通知图标和去敏诊断；增加系统命令、task removal、通知删除的无凭证日志；
6. 单元回归明确验证页面 listener detach 后系统 Pause/Play/Next 仍操作同一 session；Linux 实际 session-bus integration 继续验证同一 handler 能被平台侧发现和调用。

Android 13+ 的系统媒体控件从 `MediaSession` 的 metadata 和 playback state 派生，而不是要求应用自己复制一套通知播放状态。[^android-media-controls] Media-session 通知也属于 Android 13 通知运行时权限的豁免类型；manifest 仍显式声明权限，但前台点播不应以普通通知授权为前置条件。[^android-notification]

这轮修复闭合的是已定位的 owner 生命周期缺陷，但仍然需要一台物理 Android 设备完成最终验收：播放时通知和锁屏应显示正确歌曲/进度，系统 Pause/Resume/Seek/Next/Previous 应反向改变同一个 Fura 播放 session；从 Library 切到 Search/Settings、退到后台、锁屏和移除 Activity 后控制仍应落在同一 session；暂停后锁屏恢复不应触发 `ForegroundServiceStartNotAllowedException`；拔出耳机应触发暂停。当前主机没有连接物理 Android，自动化不能将这一项写成“已实测通过”，也不证明进程被系统杀死后的 Queue 恢复（该能力仍未实现）。

Android 官方对新应用推荐 Media3/ExoPlayer，而不是平台 MediaPlayer。[^android-mediaplayer] 但本次不建议为解决 HTTP 策略立刻迁移引擎：HTTPS 规范化更小、更准确。只有在修复后仍能稳定复现 redirect/range、特定 container、缓冲或后台生命周期问题时，才应在现有 `ForegroundAudioEngine` 接口后评估 Android 专用 Media3 实现。

### D. ABI、16 KB page 与体积

当前 ARM64 Release APK 的 16 KB zip alignment 校验成功，native libraries 均被打包到 `arm64-v8a`。这降低了 Android 15+ 16 KB page 兼容风险，但最终发布仍应对 AAB 和 Play Console 产物做同样检查；Android 对包含 native code 的发布应用有 16 KB page size 兼容要求。[^android-page-size]

APK 的主要体积来自 Flutter engine、libmpv、Rust Core 与 app snapshot。播放器当前使用 audioplayers，而视频依赖带入 libmpv；如果 Android 安装体积成为问题，可另做“媒体依赖是否重复”的 release-size 分析，但不应在播放故障修复中顺带删除 video 能力。

## 建议实施顺序

| 阶段 | 工作 | 完成标准 | Gate |
| --- | --- | --- | --- |
| P0-1 | Rust QQ CDN host 校验 + HTTP→HTTPS 规范化 | 已完成；单元测试覆盖合法/恶意 host，domain 只输出 HTTPS | Automated passed |
| P0-2 | Android live integration test | 测试已实现；匿名标准 MP3 在 Android `positionMs > 0` 仍待设备执行 | Device/Human |
| P0-3 | 真机前台回归 | 搜索、播放、暂停、seek、切歌均正常 | Human Review |
| P1-1 | 分档音质回归 | MP3、M4A、FLAC 按 entitlement 分别验证 | Human Review |
| P1-2 | 系统媒体生命周期 | 锁屏、后台、通知、耳机、来电/焦点恢复 | Human Review |
| P1-3 | 处理 lint 门禁 | 已完成；`lintRelease` 0 error、1 个版本提示 warning | Automated passed |
| P1-4 | 正式签名与发布产物 | 非 debug cert，AAB/APK 16 KB 与 ABI 校验通过 | Release |
| P2 | 必要时评估 Media3 | 仅在 HTTPS 修复后仍有 Android engine 证据时启动 | Evidence-gated |

## 真机验收矩阵

至少记录以下组合，不要只写“能播”：

| 场景 | 预期 |
| --- | --- |
| 未登录、标准 MP3 | resolve 为 HTTPS；首次进度推进；无明文策略错误 |
| 已登录、标准 MP3 | 同上；切换账号后不复用旧授权 URL |
| HQ/SQ 不具备权益 | 返回 provider entitlement/source error，不进入假播放状态 |
| HQ/SQ 具备权益 | 对应 M4A/FLAC 可 load，进度推进 |
| Wi-Fi ↔ 移动网络切换 | 当前 session 有明确恢复/失败状态，不无限 loading |
| App 前台 → 后台 | 音频继续，通知和锁屏状态同步 |
| 暂停后锁屏恢复 | 不因 foreground service/audio focus 规则静默失败 |
| 蓝牙/有线耳机拔出 | becoming-noisy 触发暂停 |
| 来电/导航抢焦点 | 按 music audio-session 策略暂停/恢复或 duck |
| URL 过期 | 有界重新 resolve，不重放旧 VKey，不泄漏原 URL |
| 进程被系统回收 | UI/系统媒体状态不冒充仍在播放 |

建议同时抓取一份去敏 Logcat，只保留 Android network security / MediaPlayer error code、应用阶段和时间，不保留完整 URL。

## 完成状态

| 项目 | 状态 |
| --- | --- |
| Android 播放链路代码审计 | 完成 |
| QQ CDN 当前线上行为抽样 | 完成（匿名、限量） |
| 根因定位 | 高可信完成：HTTP 媒体源与 Android cleartext policy 冲突 |
| 推荐修复设计 | 完成 |
| 播放代码修复 | 完成：可信 QQ CDN 严格校验并统一输出 HTTPS |
| 系统媒体适配修复 | 机器侧完成：app-lifetime owner 保持不变；`audio_session` 成为唯一焦点 owner，`audioplayers` 不再重复请求焦点；AudioService 初始化/状态/命令与引擎阶段有去敏诊断和成功/失败回归 |
| 网易云 Android transport 修复 | 机器侧完成：严格自有 CDN HTTP→HTTPS 规范化；同 URL 的 HTTP/HTTPS Range A/B 均为 206、4096 bytes、MP4 签名；无额外 header |
| Rust 自动化回归 | 通过：560 项、0 失败，26 个显式 live/Human 测试保持 ignored；workspace/all-target format 与 strict Clippy 通过 |
| Flutter 自动化回归 | 通过：601 项测试，`dart analyze` 无问题，253 文件格式检查通过；Linux real-session system-playback integration 通过 |
| 最新 ARM64 Debug/Release 构建 | 均通过；Release 45,033,904 bytes、min 24、target 36、仅 arm64-v8a，含 `librust_lib_flutterustmusic.so` |
| APK 签名与对齐 | v2 签名；16 KB ZIP alignment 及全部 native ELF LOAD alignment 通过；仍为开发 Debug certificate |
| Android Release lint | 通过：0 error、1 个 Gradle 版本提示 warning |
| Android 真机播放验证 | 未执行：当前无已连接设备；QQ 与网易云真实媒体进度均不可由构建结果替代 |
| Android 系统控件真机验证 | 未完成：旧实现已有失败报告；焦点单 owner 修复等待重新安装本轮 APK 后按 checklist Human Review |
| 问题最终关闭 | 未完成，等待真机远程媒体进度、系统控件反向操作与后台生命周期 Human Review |

## Sources

[^android-cleartext-app]: Android Developers, [`<application>` / `android:usesCleartextTraffic`](https://developer.android.com/guide/topics/manifest/application-element.html). target API 28+ 默认 false，且 `MediaPlayer` 会拒绝明文请求。
[^android-network-security]: Android Developers, [Network security configuration](https://developer.android.com/privacy-and-security/security-config). Android 9+ 明文默认禁用，并建议避免全局 opt-in。
[^audioplayers-android]: pub.dev, [`audioplayers_android` 5.3.0](https://pub.dev/packages/audioplayers_android/versions/5.3.0). 本项目锁定版本的 Android endorsed implementation；本地锁定源码进一步确认 URL 交给平台 `MediaPlayer.setDataSource`。
[^android-formats]: Android Developers, [Supported media formats](https://developer.android.com/media/platform/supported-formats). MP3、AAC/M4A、FLAC 的平台支持矩阵。
[^android-mediaplayer]: Android Developers, [About MediaPlayer](https://developer.android.com/media/platform/mediaplayer). 官方对新应用推荐 Jetpack Media3/ExoPlayer。
[^android-audio-focus]: Android Developers, [Manage audio focus](https://developer.android.com/media/optimize/audio-focus). target 35+ 只有顶层应用或 foreground service 能请求音频焦点。
[^android-background-playback]: Android Developers, [Background playback with a MediaSessionService](https://developer.android.com/media/media3/session/background-playback). playback foreground service 的权限和 manifest 要求。
[^android-notification]: Android Developers, [Notification runtime permission — media session exemption](https://developer.android.com/develop/ui/compose/notifications/notification-permission#exemptions). media-session notifications 属于权限行为变化的豁免。
[^android-media-controls]: Android Developers, [Media controls](https://developer.android.com/media/implement/surfaces/mobile). Android 13+ 系统媒体控制基于 MediaSession 状态与 metadata 生成。
[^audio-service]: pub.dev, [`audio_service` 0.18.19](https://pub.dev/packages/audio_service/versions/0.18.19). 为 Flutter 音频引擎提供后台、通知、锁屏、耳机键和媒体会话适配。
[^just-audio-background]: pub.dev, [`just_audio_background`](https://pub.dev/packages/just_audio_background). 官方说明它适合单一 `AudioPlayer` 的简单场景，更复杂需求应直接使用 `audio_service`。
[^android-page-size]: Android Developers, [Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes). Native-code 应用的 16 KB page compatibility 要求与检查方法。
[^android-signing]: Android Developers, [Sign your app](https://developer.android.com/studio/publish/app-signing). Debug certificate 只适合开发调试，不适合应用商店发布。
