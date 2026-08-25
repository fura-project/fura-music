use std::convert::Infallible;

use qqmusic_client::{
    HttpRequest, HttpResponse, HttpTransport, QqMusicClient, ReqwestTransport,
    WechatCredentialExchangeError, WechatQrPollResult,
};

struct InvalidCodeFixtureTransport;

impl HttpTransport for InvalidCodeFixtureTransport {
    type Error = Infallible;

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
        let body = if request.url() == "https://open.weixin.qq.com/connect/qrconnect" {
            br#"<a href="?uuid=invalid-code-fixture">login</a>"#.to_vec()
        } else if request
            .url()
            .starts_with("https://open.weixin.qq.com/connect/qrcode/")
        {
            b"\xff\xd8\xfffixture-jpeg".to_vec()
        } else {
            b"window.wx_errcode=405;window.wx_code='invalid-flutterustmusic-compatibility-probe';"
                .to_vec()
        };
        Ok(HttpResponse::new(200, body))
    }
}

/// Opt-in compatibility probe using an explicitly invalid OAuth code. It cannot
/// authenticate or access an account and retains no upstream response.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn rejects_invalid_wechat_code_with_structured_upstream_status() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let fixture_client = QqMusicClient::new(InvalidCodeFixtureTransport);
    let session = fixture_client
        .create_wechat_qr()
        .await
        .expect("synthetic QR session");
    let poll = fixture_client
        .poll_wechat_qr(&session)
        .await
        .expect("synthetic authorized poll");
    let WechatQrPollResult::Authorized(code) = poll else {
        panic!("fixture must produce an authorization code");
    };

    let live_client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let error = live_client
        .exchange_wechat_code(&code)
        .await
        .expect_err("invalid OAuth code must be rejected");

    assert!(matches!(
        error,
        WechatCredentialExchangeError::Upstream {
            global_code: 0,
            login_code: Some(1000)
        }
    ));
}
