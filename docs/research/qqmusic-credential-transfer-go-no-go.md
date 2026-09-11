# QQ Music Credential 跨设备迁移 Go / No-Go

## 结论

当前 Core 的 QQ Music 认证请求不依赖 QQ Connect AppID、`p_skey`、`skey`、GUID、device id 或官方 QQ Music App 的私有文件。现有请求的必需集合是 `music_id + music_key + login_type`；其他 session secret 和本地 expiry 是可选保留信息。这使“已登录 Fura 设备把 Core credential 安全迁移到新 Fura 设备”在代码与协议结构上可行。

但这不等于 QQ Music 服务端已证明接受跨设备 credential。最终结论必须来自第二台设备的真实账号验证。在此之前，不实现 LAN listener、配对二维码或正式手机端“从另一台 Fura 登录”UI。

## Credential 真实依赖表

以 `crates/qqmusic-client/src/credential.rs`、登录 credential 创建以及 Provider restore/request 路径为代码事实：

| 字段/依赖 | 是否保存 | 当前请求是否必需 | 实际用途 |
| --- | --- | --- | --- |
| `music_id` | 是 | 是 | 当前请求中的 UIN/账号标识；登录响应优先使用非空 `str_musicid`，再回退数字 `musicid` |
| `music_key` | 是 | 是 | 同时填充 Cookie 中的 `qqmusic_key` 和 `qm_keyst` |
| `login_type` | 是 | 是 | 非零透传到 `tmeLoginType`；QQ 和微信语义分开 |
| expiry metadata | 可选 | 否 | 只能在本地证明“已过期”，不能证明“仍有效” |
| `open_id` / `access_token` / refresh fields / `union_id` / encrypted UIN | 可选 | 当前核心请求不必需 | 为刷新或后续协议保真保留，不会输出到 Flutter |
| `p_skey` / `skey` | 否 | 否 | 当前 credential 模型和 musicu Cookie 均不使用 |
| GUID / device id | 否 | 否 | 不属于 credential persistence；不会为迁移伪造设备指纹 |
| QQ/QQ Music 客户端私有本机状态 | 否 | 否 | 当前 authenticated request 不读取 |

当前 QQ 登录的基础 Cookie 字段数是 4：`uin`、`qqmusic_key`、`qm_keyst`、`tmeLoginType`。微信 login type 另外附加 `wxuin`。这个统计只记录字段名/数量，不记录真实值。

## 导入后的认证边界

Core 已有的 restore 语义没有改变：

```text
encrypted bundle
  -> XChaCha20-Poly1305 authentication/decryption
  -> versioned Credential invariant validation
  -> PendingVerification / LocallyExpired
  -> reserve exact verification attempt
  -> QQ Music account-summary verification
  -> Authenticated only after server success
```

- 解密成功不代表登录成功；
- JSON 字段合法不代表登录成功；
- 明确 credential rejection 会清理 candidate；
- 网络/服务暂时失败保留 candidate 以便显式重试；
- 新登录、退出或更新的 verification attempt 会使旧异步结果失效；
- 未验证 candidate 不能导出到正式 Credential Vault。

## 开发版迁移实验实现

本轮增加的是“决定性实验原语”，不是正式配对产品：

- `qqmusic-client` 提供 `export_encrypted_credential_bundle` / `import_encrypted_credential_bundle`；
- `provider-qqmusic` 只允许 authenticated credential 导出，导入后只安装 pending candidate；
- Provider 在当前进程中记录已消费 session id，同一 bundle 第二次导入返回 `AlreadyConsumed`；
- typed Flutter Bridge 只增加 `debugExportQqMusicCredentialTransfer` / `debugImportQqMusicCredentialTransfer`；Flutter 只传入两个文件路径，不接收 credential、ciphertext 或 transfer-secret bytes；
- Release 构建中这两个入口固定返回 `DisabledOutsideDebugBuild`，且当前没有任何产品 UI 调用它们；
- Bridge 只暴露 typed path、restore state 与 failure enum；credential、密文和 transfer-secret byte buffers 始终留在 Rust 内，没有 raw JSON bridge；
- Rust 以 create-new 语义写文件，拒绝覆盖旧 artifact；Unix 平台建立时直接使用 `0600` 权限；导入拒绝符号链接、非普通文件和超大文件；
- Debug 输出只包含是否写入和 failure 类别，不包含密文、key、账号或 credential 值。

### Bundle 格式

```text
CredentialTransferBundleV1
├── version = 1
├── provider = qqmusic
├── issued_at_unix_seconds
├── random 128-bit session_id
├── random 192-bit XChaCha nonce
└── authenticated ciphertext

TransferSecretV1  (必须与 bundle 分开传递)
├── version = 1
├── same session_id
└── random 256-bit key
```

加密使用 RustCrypto `chacha20poly1305 0.11.0` 的 XChaCha20-Poly1305 AEAD；`version/provider/issued_at/session_id` 同时作为 associated data，所以修改元数据也会导致认证失败。[^chacha-docs] 密钥与 credential plaintext 使用 `zeroize 1.9.0` 包装，尽量在生命周期结束时擦除。[^zeroize-docs]

两个 crate 均为 `MIT OR Apache-2.0`，当前版本 MSRV 均不高于本项目 Rust 1.97.1；加密实现是 pure Rust，不要求 Android 特定硬件指令。RustCrypto 对库的安全审计状态有自己的明确说明，正式 LAN 配对仍应使用小而标准的 X25519/HKDF/AEAD 组合，不自行创造密码协议。[^rustcrypto-aeads]

### 安全限制

- bundle 只有 10 分钟有效期，容许 60 秒时钟偏差；
- bundle 上限 32 KiB，secret document 上限 1 KiB；
- bundle 不含明文 credential，也不含非必要账号指纹；
- bundle 与 transfer secret 同时泄露等同于 credential 泄露；它们不能放在同一个二维码、URL、剪贴板、日志或公开附件中；
- 当前原语只保证同一进程内的单次消费；正式 LAN 配对还需要短时 listener、ephemeral key agreement、SAS 人工确认、成功/失败/超时即销毁的完整状态机；
- 开发实验不得输出真实 credential、transfer secret 或密文内容到测试日志。

## Human Go / No-Go 步骤

实验仅在明确的 Debug 构建中执行，不由 Agent 自动读取本机 Credential Vault。

1. 设备 A 的 Fura 已通过现有 QQ/QQ Music 兼容登录，并已经过一次 account-summary 服务端验证。
2. 在 Debug 实验入口调用 `debugExportQqMusicCredentialTransfer(encryptedBundlePath, transferSecretPath)`。两个目标必须不存在、不同路径；Rust 直接写入，Dart 不持有两份材料的 bytes。将 encrypted bundle 与 transfer secret 分开传送给设备 B，不截图/不粘贴内容。
3. 设备 B 使用全新 Fura 数据目录，在 10 分钟内调用 `debugImportQqMusicCredentialTransfer(encryptedBundlePath, transferSecretPath)`；Rust 直接读取两份 artifact。
4. 确认返回 `VerificationRequired`，此时 UI 仍不得显示已登录。
5. 执行现有 reserve/verify flow，验证 profile；成功后再写入设备 B 的 Credential Vault。
6. 使用同一 candidate 依次验证 favorites、owned/saved playlists、QQ 云端最近播放与一首需 authenticated vkey 的媒体。
7. 设备 A 不退出，再次执行 profile/favorites 读取，观察两设备是否可同时使用。
8. 实验后删除两台设备的 bundle/secret 实验文件；若设备 B 失败，退出并清理 candidate/vault。

当 QQ Music 返回拒绝时，只记录安全分类：`parsed / request_sent / rejected / error_category`。不记录 request body、Cookie、UIN、vkey 或原始响应。

## Go / No-Go 矩阵

| 能力 | 当前结果 |
| --- | --- |
| Credential 最小字段已确认 | YES（代码路径核对） |
| Credential 可序列化迁移 | YES（加密 round-trip 自动测试） |
| 第二设备可解析 | AWAITING HUMAN TEST |
| 第二设备 profile 验证 | NOT RUN |
| 第二设备 favorites | NOT RUN |
| 第二设备 playlists | NOT RUN |
| 第二设备云端最近播放 | NOT RUN |
| 第二设备 authenticated media | NOT RUN |
| 原设备登录状态是否受影响 | NOT RUN |
| 两设备是否可同时使用 | NOT RUN |
| 观察到设备绑定 | UNKNOWN |

## 自动化验证

- `qqmusic-client` 的加密 round-trip、错误版本/provider、篡改元数据/密文、错误 key、session mismatch、过期/未来时间和大小上限测试通过；
- `provider-qqmusic` 的 authenticated-only 导出、pending-only 导入、server accept/reject、logout、单进程 replay 拒绝及失败不覆盖旧 candidate 测试通过；
- Rust Bridge 的 typed/redacted 结果、owner-private create-new 文件、拒绝覆盖和 release-build 禁用边界通过；
- `cargo test --workspace --all-targets` 为 528 passed / 0 failed / 20 explicit live-Human ignored，`cargo fmt --all -- --check` 与 workspace/all-target strict Clippy 全部通过；
- Flutter 513 项测试、`dart analyze`、235 文件格式门禁、Linux Release、Android ARM64 Release 与 Android Release lint 通过。

这些自动化只证明格式、状态机与边界正确，不证明 QQ Music 服务端会接受第二台真实设备上的同一 credential。

## 与最近播放的状态分离

云端最近播放读取已经通过当前官方 Windows 协议证据更正为 `music.musicasset.PlayRecentlyRead / GetPlayRecentlyInfo`，而不再使用早期公开 wrapper 中已返回 `500003` 的 `RecentPlayList / GetRecentPlayList`。这是现有已完成、已有 Human 成功读取报告的独立能力，不依赖 QQ Connect AppID 或 credential transfer。

普通 QQ Music credential 下的云端最近播放写回仍没有满足“双独立证据，或一份实现+一次真实账号验证”的门槛，因此 `RecentHistoryWrite` 仍保持 false，播放器生命周期中没有加入任何猜测性上报。

## 当前任务状态

| 项目 | 状态 |
| --- | --- |
| QQ Connect AppID 依赖 | REMOVED FROM CURRENT PATH |
| 跨设备 Credential 可用性 | AWAITING HUMAN GO/NO-GO |
| 开发版 Credential Transfer | DONE（Core + typed debug bridge） |
| 正式 E2E Device Pairing | DEFERRED |
| QQ 云端最近播放读取 | DONE（现有能力） |
| QQ 云端最近播放写回 | BLOCKED（协议证据不足） |
| 跨端双向最近播放同步 | NOT DONE |
| 首次登录 | EXISTING QR / DESKTOP QUICK LOGIN |
| 移动端已有设备登录 | BLOCKED UNTIL GO/NO-GO |

## Sources

[^chacha-docs]: RustCrypto, [`chacha20poly1305` 0.11.0 documentation](https://docs.rs/chacha20poly1305/latest/chacha20poly1305/). 包含 XChaCha20-Poly1305 AEAD 与 `zeroize` feature。
[^zeroize-docs]: RustCrypto, [`zeroize` 1.9.0 documentation](https://docs.rs/zeroize/latest/zeroize/). 提供不易被编译器优化掉的秘密内存清理原语。
[^rustcrypto-aeads]: RustCrypto, [AEAD implementations repository](https://github.com/RustCrypto/AEADs). 实现来源、维护状态与安全声明。
