//! Human-operated evidence only. The Agent must never run this gate.
//! No credential files, browser cookies, account writes or source downloads.
use netease_client::{Error, HttpsTransport, NeteaseClient, Request, Response, Transport};
use provider_api::{
    AccountSummaryProvider, QrAuthenticationChannel, QrAuthenticationProgress,
    QrAuthenticationProvider, QrAuthenticationSession,
};
use provider_netease::NeteaseProvider;
use std::{
    io::Write,
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
};
struct Budget {
    http: HttpsTransport,
    calls: AtomicUsize,
}
impl Transport for Budget {
    async fn send(&self, r: Request) -> Result<Response, Error> {
        if self.calls.fetch_add(1, Ordering::SeqCst) >= 60 {
            return Err(Error::InputBound);
        }
        self.http.send(r).await
    }
}
#[tokio::test]
#[ignore = "HUMAN_EVIDENCE_REQUIRED: Human opens temporary QR and explicitly approves account reads"]
async fn human_qr_restore_and_account_summary() {
    assert_eq!(
        std::env::var("FURA_NETEASE_HUMAN_QR").as_deref(),
        Ok("I_APPROVE_QR_AND_ACCOUNT_READS")
    );
    let provider = NeteaseProvider::new(NeteaseClient::new(Budget {
        http: HttpsTransport::new().unwrap(),
        calls: AtomicUsize::new(0),
    }));
    let mut qr = provider
        .begin_qr_authentication(QrAuthenticationChannel::ProviderDefault)
        .await
        .unwrap();
    let mut file = tempfile::Builder::new()
        .prefix("fura-netease-qr-")
        .suffix(".png")
        .tempfile()
        .unwrap();
    file.write_all(qr.challenge().image_bytes()).unwrap();
    file.flush().unwrap();
    println!(
        "Human: open the temporary QR image and approve only if intended: {}",
        file.path().display()
    );
    let mut confirmed = false;
    for _ in 0..45 {
        tokio::time::sleep(Duration::from_secs(2)).await;
        match qr.advance().await.unwrap() {
            QrAuthenticationProgress::WaitingForScan
            | QrAuthenticationProgress::ScannedAwaitingConfirmation => {}
            QrAuthenticationProgress::Authenticated => {
                confirmed = true;
                break;
            }
            _ => break,
        }
    }
    assert!(
        confirmed,
        "Human QR approval did not complete within this bounded window"
    );
    // The QR file is erased now, including on panic through NamedTempFile's RAII cleanup.
    drop(file);
    provider.account_summary().await.unwrap();
    println!("Human gate: QR and Account Summary PASS");
    let mut bytes = provider.export_credential().unwrap().unwrap();
    provider.sign_out();
    provider.import_credential(&bytes).unwrap();
    bytes.fill(0);
    assert!(!provider.has_authenticated_credential());
    provider.verify_restored_credential().await.unwrap();
    provider.account_summary().await.unwrap();
    provider.sign_out();
    println!("Human gate: opaque restore and verified Account Summary PASS");
}
