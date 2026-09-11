# Platform-native authorization plan

- **Date:** 2026-09-03
- **Execution mode:** `HUMAN_GATED_REGRESSION`
- **Domain:** Mixed Core/Bridge/Flutter presentation
- **Status:** Desktop QQ Core flow live-verified on Linux; Fura UI acceptance pending; mobile installed-client authorization externally blocked

## Target clarified by the maintainer

### Desktop QQ

Match the QQ Music quick-login behavior semantically:

1. Show QQ and WeChat authorization choices.
2. Start a QQ Web QR as the fallback.
3. Ask a running desktop QQ client for its signed-in account choices.
4. Show each account's nickname and a masked account hint immediately; use a generic account icon until real avatars can load lazily without exposing the raw identifier.
5. On explicit selection, ask desktop QQ for a one-time ticket and complete the existing QQ Connect → QQ Music credential exchange.

### Android and iOS

The requested target is installed-client authorization through QQ and WeChat. Opening an HTTPS QR target in a browser is not accepted as equivalent.

## Desktop protocol evidence

The current QQ login page reported version `202609011612` and loaded:

```text
https://qq-web.cdn-go.cn/monorepo/c1db8078/ptlogin/js/c_login_2.js
```

The script uses the following current quick-login sequence:

```text
GET https://localhost.ptlogin2.qq.com:{4301,4303,4305,4307,4309}/pt_get_uins
  -> local account choices

GET https://localhost.ptlogin2.qq.com:<selected-port>/pt_get_st
  -> one-time clientkey cookie for the explicitly selected account

GET https://ssl.ptlogin2.qq.com/jump
  -> signed check_sig callback

GET https://ssl.ptlogin2.graph.qq.com/check_sig
  -> QQ Connect p_skey and login_jump redirect

POST https://graph.qq.com/oauth2.0/authorize
  -> short-lived QQ Connect code

POST https://u.y.qq.com/cgi-bin/musicu.fcg
  -> QQ Music credential
```

The inspected Linux host had the current QQ client listening on `127.0.0.1:4301`. A read-only TLS check found a publicly trusted Tencent certificate whose SAN includes `localhost.ptlogin2.qq.com`. With the maintainer's explicit authorization on 2026-09-11, a content-free live test discovered the sole local account and completed the local ticket, `jump`, `check_sig`, QQ Connect authorization, and QQ Music credential exchange. It printed and persisted no account identity, nickname, ticket, cookie, OAuth code, credential, or response body.

The concrete failure was protocol drift in the candidate rather than a desktop-QQ product limitation. The current Tencent local-login script computes `pt_local_tk` with `hash33(clientkey)` starting from zero; the previous implementation incorrectly reused the 5381 seed associated with QQ Connect's `g_tk`. The wrong token led `jump` into a fallback redirect without the required `p_skey`. Current desktop QQ also wraps account and ticket results in fixed JavaScript assignments, and the successful path requires following the validated `check_sig` URL before posting QQ Connect authorization. The implementation now handles those current shapes without evaluating JavaScript, retains legacy direct callbacks, and validates the account plus QQ/Connect application identities before following the signed URL.

## Implemented desktop boundary

- `ReqwestTransport` pins `localhost.ptlogin2.qq.com` to `127.0.0.1`; URL ports still select QQ's official odd-port sequence.
- Discovery starts only after the user opens Fura's sign-in dialog.
- Local responses are size/time bounded and parsed only from the exact `ptui_getuins_CB` / `ptui_getst_CB` shapes.
- Odd-port discovery is staggered and concurrent like the current Tencent script; each local probe has a three-second bound instead of racing normal local TLS/response latency with the former 500 ms serial timeout.
- At most ten choices are accepted. Raw QQ identifiers stay inside the Rust session.
- Flutter receives only an attempt-local selection ID, nickname, and masked hint.
- The initial QQ/WeChat choice performs no discovery or QR request. Choosing QQ starts both explicitly.
- Account discovery no longer waits for `getface`; a generic account icon keeps selection immediately available. Real avatars remain a deferred lazy-loading refinement.
- Clicking a choice requests the one-time ticket. No account is authorized during discovery.
- Ticket, cookies, QQ Connect code, and QQ Music credential stay redacted and are never persisted outside the existing secure credential document.
- Cancellation, replacement, concurrent calls, invalid selection, unavailable client, network/service failure, rejection, and secure-vault persistence remain typed.
- QQ QR and WeChat QR remain available; absence of desktop QQ does not break them.

## Mobile implementation gate

QQ Connect and WeChat OpenSDK validate the registered mobile application identity. A production mobile implementation needs:

- final Android application ID and release-signature fingerprints;
- final iOS Bundle ID and verified Universal Links where required;
- reviewed QQ/WeChat mobile applications and granted login capabilities;
- privacy disclosures for the selected SDK versions;
- server-side secret custody where the authorization-code exchange requires an AppSecret;
- evidence that the issued authorization can legally and technically become the QQ Music credential Fura needs.

Using QQ Music's AppID with Fura's package/signature is not a valid substitute. Using a Fura-owned QQ/WeChat social identity and assuming it is a QQ Music session is also invalid. Mobile remains `BLOCKED` until this external boundary is supplied or Tencent documents a client-safe QQ Music authorization path.

## Verification and Human checklist

Automated coverage uses synthetic identities only. The ignored local discovery test can be run manually without requesting an authorization ticket:

```bash
QQMUSIC_DESKTOP_QUICK_LOGIN_TEST=1 \
  cargo test -p qqmusic-client --test live_qq_desktop_quick_login \
  -- --ignored --nocapture
```

The end-to-end live check is separately gated and authorizes only when the local client exposes exactly one unambiguous account. It does not persist or print the resulting credential:

```bash
QQMUSIC_DESKTOP_QUICK_AUTHORIZATION_TEST=1 \
  cargo test -p qqmusic-client --test live_qq_desktop_quick_login \
  authorizes_the_sole_desktop_qq_account_without_persisting \
  -- --ignored --nocapture
```

For complete acceptance, the maintainer should:

1. Open and sign in to desktop QQ.
2. Open Fura's sign-in dialog, choose QQ, and confirm the expected nickname/masked hint appears beside the QQ QR within the bounded local probe time.
3. Select that account and confirm the Fura dialog completes authorization. The Core protocol exchange is live-verified, but this visible application-layer behavior remains Human evidence.
4. Confirm Fura enters the authenticated Home only after the provider exchange succeeds.
5. Restart Fura and confirm the saved session verifies successfully.
6. Repeat desktop QR and WeChat QR once to ensure the fallback paths remain intact.

Do not capture or share screenshots/logs containing a real QR, full QQ number, local ticket, cookie, OAuth code, or credential.
