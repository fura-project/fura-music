use super::super::*;
use kugou_client::{
    Response,
    web_playback_candidate::{CapturedWebRequest, WebPlaybackResponse},
};
use std::{
    future::Future,
    net::{Ipv4Addr, SocketAddr},
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::{net::TcpListener, task::JoinHandle};
use tokio_tungstenite::accept_async;

pub(super) const HASH: &str = "11111111111111111111111111111111";
pub(super) const SESSION: &str = "synthetic-page-session";
pub(super) const FRAME: &str = "synthetic-root-frame";
pub(super) const REQUEST: &str = "synthetic-paused-request";
const IO_TIMEOUT: Duration = Duration::from_secs(5);

pub(super) fn track_id() -> TrackId {
    TrackId::new(
        provider_kugou::provider_id(),
        format!("v1:9:{HASH}:8:180:7"),
    )
    .unwrap()
}

pub(super) fn songinfo_url() -> String {
    format!(
        "https://wwwapi.kugou.com/play/songinfo?hash={HASH}&album_id=7&album_audio_id=9&mid=synthetic-mid&dfid=synthetic-dfid&userid=42&token=synthetic-token&signature=00000000000000000000000000000000"
    )
}

pub(super) fn cookies() -> Value {
    json!([
        {"name":"KugooID", "value":"42", "domain":".kugou.com", "path":"/", "secure":true},
        {"name":"t", "value":"synthetic-token", "domain":".kugou.com", "path":"/", "secure":true}
    ])
}

pub(super) fn paused() -> Value {
    json!({
        "method":"Fetch.requestPaused", "sessionId":SESSION,
        "params":{
            "requestId":REQUEST, "frameId":FRAME, "resourceType":"XHR",
            "request":{
                "url":songinfo_url(), "method":"GET",
                "headers":{
                    "User-Agent":"SyntheticOfficialBrowser/1",
                    "Origin":"https://www.kugou.com",
                    "Referer":"https://www.kugou.com/"
                }
            }
        }
    })
}

pub(super) fn frame(url: &str) -> Value {
    json!({"method":"Page.frameNavigated", "sessionId":SESSION,
        "params":{"frame":{"id":FRAME, "url":url}}})
}

pub(super) struct Scenario {
    pub frame: Value,
    pub events: Vec<Value>,
    pub cookies: Value,
    pub target_kind: &'static str,
}

impl Default for Scenario {
    fn default() -> Self {
        Self {
            frame: frame(OFFICIAL_PAGE),
            events: vec![paused()],
            cookies: cookies(),
            target_kind: "page",
        }
    }
}

pub(super) struct TestTask(JoinHandle<()>);

impl TestTask {
    pub async fn join(&mut self) {
        timeout(IO_TIMEOUT, &mut self.0)
            .await
            .expect("synthetic server did not finish")
            .expect("synthetic server failed");
    }
}

impl Drop for TestTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

pub(super) type ServerSocket = WebSocketStream<TcpStream>;

pub(super) async fn cdp_peer<F, Fut>(serve: F) -> (CdpClient, TestTask)
where
    F: FnOnce(ServerSocket) -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
    let address = listener.local_addr().unwrap();
    let task = TestTask(tokio::spawn(async move {
        let (stream, _) = timeout(IO_TIMEOUT, listener.accept())
            .await
            .unwrap()
            .unwrap();
        let socket = timeout(IO_TIMEOUT, accept_async(stream))
            .await
            .unwrap()
            .unwrap();
        serve(socket).await;
    }));
    let url = Url::parse(&format!("ws://{address}/devtools/browser/synthetic-test")).unwrap();
    (CdpClient::connect(url).await.unwrap(), task)
}

pub(super) async fn send_json(socket: &mut ServerSocket, value: Value) {
    socket
        .send(Message::Text(value.to_string().into()))
        .await
        .unwrap();
}

pub(super) async fn read_command(socket: &mut ServerSocket) -> Value {
    let message = timeout(IO_TIMEOUT, socket.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let Message::Text(text) = message else {
        panic!("expected synthetic CDP command");
    };
    serde_json::from_str(&text).unwrap()
}

pub(super) fn reply(command: &Value, result: Value) -> Value {
    let mut value = json!({"id":command["id"], "result":result});
    if let Some(session) = command.get("sessionId") {
        value["sessionId"] = session.clone();
    }
    value
}

pub(super) struct SyntheticBrowser {
    pub cdp: CdpClient,
    pub interceptor: Interceptor,
    trace: Arc<Mutex<Vec<Value>>>,
    server: TestTask,
}

impl SyntheticBrowser {
    pub async fn start(scenario: Scenario, upstream: SocketAddr) -> Self {
        let trace = Arc::new(Mutex::new(Vec::new()));
        let recorded = trace.clone();
        let (mut cdp, server) = cdp_peer(move |mut socket| async move {
            while let Some(message) = socket.next().await {
                let Message::Text(text) = message.expect("synthetic CDP socket failed") else {
                    break;
                };
                let command: Value = serde_json::from_str(&text).unwrap();
                recorded.lock().unwrap().push(command.clone());
                let mut result = json!({});
                match command["method"].as_str().unwrap() {
                    "Target.setAutoAttach" if command.get("sessionId").is_none() => {
                        // Deliberately precedes the command response, as real CDP events can.
                        send_json(&mut socket, json!({"method":"Target.attachedToTarget", "params":{
                            "sessionId":SESSION, "waitingForDebugger":true,
                            "targetInfo":{"targetId":"synthetic-page", "type":scenario.target_kind,
                                "url":"about:blank"}
                        }})).await;
                    }
                    "Page.navigate" => {
                        send_json(&mut socket, scenario.frame.clone()).await;
                        for event in &scenario.events {
                            send_json(&mut socket, event.clone()).await;
                        }
                    }
                    "Runtime.runIfWaitingForDebugger" if scenario.target_kind != "page" => {
                        send_json(&mut socket, scenario.frame.clone()).await;
                        for event in &scenario.events {
                            send_json(&mut socket, event.clone()).await;
                        }
                    }
                    "Fetch.continueRequest" => {
                        let request = command["params"]["requestId"].as_str().unwrap();
                        if let Some(event) = scenario
                            .events
                            .iter()
                            .find(|event| event["params"]["requestId"].as_str() == Some(request))
                        {
                            let url =
                                Url::parse(event["params"]["request"]["url"].as_str().unwrap())
                                    .unwrap();
                            if url.path().starts_with("/play/songinfo") {
                                // A continue really opens the upstream socket; a fail never does.
                                http_request(upstream, "Browser", &url, &[]).await.unwrap();
                            }
                        }
                    }
                    "Storage.getCookies" => result = json!({"cookies":scenario.cookies}),
                    _ => (),
                }
                send_json(&mut socket, reply(&command, result)).await;
            }
        })
        .await;
        let interceptor = Interceptor::arm(&mut cdp).await.unwrap();
        Self {
            cdp,
            interceptor,
            trace,
            server,
        }
    }

    pub async fn handle_next(&mut self) -> Result<Option<OfficialWebCapture>, GateFailure> {
        let event = timeout(IO_TIMEOUT, async {
            loop {
                if let Some(event) = self.cdp.next_event().await.unwrap() {
                    break event;
                }
            }
        })
        .await
        .expect("expected a synthetic CDP event");
        self.interceptor
            .handle(&mut self.cdp, event, OFFICIAL_PAGE)
            .await
    }

    pub async fn attach_and_navigate(&mut self) {
        assert_eq!(
            self.cdp.events.len(),
            1,
            "attachment must survive arm response"
        );
        assert!(self.handle_next().await.unwrap().is_none());
        assert!(self.handle_next().await.unwrap().is_none());
    }

    pub fn commands(&self, method: &str) -> Vec<Value> {
        self.trace
            .lock()
            .unwrap()
            .iter()
            .filter(|command| command["method"] == method)
            .cloned()
            .collect()
    }

    pub fn methods(&self) -> Vec<String> {
        self.trace
            .lock()
            .unwrap()
            .iter()
            .map(|command| command["method"].as_str().unwrap().to_owned())
            .collect()
    }

    pub async fn finish(mut self) {
        self.cdp.socket.close(None).await.unwrap();
        self.server.join().await;
    }
}

pub(super) struct Upstream {
    pub address: SocketAddr,
    pub accepts: Arc<AtomicUsize>,
    pub rust_requests: Arc<AtomicUsize>,
    pub browser_requests: Arc<AtomicUsize>,
    _server: TestTask,
}

impl Upstream {
    pub async fn start() -> Self {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let address = listener.local_addr().unwrap();
        let accepts = Arc::new(AtomicUsize::new(0));
        let rust_requests = Arc::new(AtomicUsize::new(0));
        let browser_requests = Arc::new(AtomicUsize::new(0));
        let (physical, rust, browser) = (
            accepts.clone(),
            rust_requests.clone(),
            browser_requests.clone(),
        );
        let server = TestTask(tokio::spawn(async move {
            loop {
                let (mut stream, _) = listener.accept().await.unwrap();
                physical.fetch_add(1, Ordering::SeqCst);
                let mut request = Vec::new();
                loop {
                    let mut chunk = [0; 2048];
                    let count = timeout(IO_TIMEOUT, stream.read(&mut chunk))
                        .await
                        .unwrap()
                        .unwrap();
                    assert_ne!(count, 0, "incomplete synthetic HTTP request");
                    request.extend_from_slice(&chunk[..count]);
                    assert!(request.len() <= 32 * 1024);
                    if request.windows(4).any(|part| part == b"\r\n\r\n") {
                        break;
                    }
                }
                let request = std::str::from_utf8(&request).unwrap();
                assert!(request.starts_with("GET /play/songinfo?"));
                if request.contains("\r\nX-Synthetic-Owner: Rust\r\n") {
                    rust.fetch_add(1, Ordering::SeqCst);
                    assert!(request.contains("\r\nCookie: KugooID=42; t=synthetic-token\r\n"));
                    assert!(request.contains("\r\norigin: https://www.kugou.com\r\n"));
                    assert!(request.contains("\r\nuser-agent: SyntheticOfficialBrowser/1\r\n"));
                    assert!(!request.contains("analytics-sentinel"));
                } else {
                    assert!(request.contains("\r\nX-Synthetic-Owner: Browser\r\n"));
                    browser.fetch_add(1, Ordering::SeqCst);
                }
                let body = json!({"status":1,"data":{
                    "hash":HASH,"album_audio_id":9,"album_id":7,"privilege":0,"is_free_part":0,
                    "play_url":"https://offline-media.example.org/synthetic.mp3",
                    "bitrate":128000,"timelength":180000,"filesize":2880000,
                    "extname":"mp3","quality":"standard"
                }})
                .to_string();
                let response = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(response.as_bytes()).await.unwrap();
                stream.shutdown().await.unwrap();
            }
        }));
        Self {
            address,
            accepts,
            rust_requests,
            browser_requests,
            _server: server,
        }
    }

    pub fn assert_counts(&self, total: usize, rust: usize, browser: usize) {
        assert_eq!(
            self.accepts.load(Ordering::SeqCst),
            total,
            "physical TCP accepts"
        );
        assert_eq!(
            self.rust_requests.load(Ordering::SeqCst),
            rust,
            "Rust HTTP requests"
        );
        assert_eq!(
            self.browser_requests.load(Ordering::SeqCst),
            browser,
            "browser HTTP requests"
        );
    }

    pub fn transport(&self) -> LoopbackTransport {
        LoopbackTransport(self.address)
    }
}

// Test transport only: official-looking URLs are never resolved. Both fake browser
// forwarding and Rust replay can reach only the listener's literal loopback address.
async fn http_request(
    address: SocketAddr,
    owner: &str,
    url: &Url,
    headers: &[(String, String)],
) -> Result<Vec<u8>, WebPlaybackError> {
    assert!(address.ip().is_loopback());
    timeout(IO_TIMEOUT, async {
        let mut stream = TcpStream::connect(address).await.map_err(|_| WebPlaybackError::Network)?;
        let mut request = format!("GET {}?{} HTTP/1.1\r\nHost: wwwapi.kugou.com\r\nX-Synthetic-Owner: {owner}\r\nConnection: close\r\n", url.path(), url.query().unwrap_or(""));
        for (name, value) in headers {
            request.push_str(&format!("{name}: {value}\r\n"));
        }
        request.push_str("\r\n");
        stream.write_all(request.as_bytes()).await.map_err(|_| WebPlaybackError::Network)?;
        let mut response = Vec::new();
        stream.take(64 * 1024).read_to_end(&mut response).await.map_err(|_| WebPlaybackError::Network)?;
        let split = response.windows(4).position(|part| part == b"\r\n\r\n")
            .ok_or(WebPlaybackError::InvalidResponse)?;
        if !response.starts_with(b"HTTP/1.1 200 OK\r\n") {
            return Err(WebPlaybackError::InvalidResponse);
        }
        Ok(response[split + 4..].to_vec())
    }).await.map_err(|_| WebPlaybackError::Network)?
}

pub(super) struct LoopbackTransport(SocketAddr);

impl WebPlaybackTransport for LoopbackTransport {
    async fn send_web(
        &self,
        request: &CapturedWebRequest,
    ) -> Result<WebPlaybackResponse, WebPlaybackError> {
        assert!(
            request.url() == songinfo_url(),
            "replay must preserve captured URL"
        );
        assert!(
            request.cookie_header() == "KugooID=42; t=synthetic-token",
            "profile cookie subset"
        );
        let url = Url::parse(request.url()).unwrap();
        let mut headers = request.replay_headers().to_vec();
        headers.push(("Cookie".into(), request.cookie_header().into()));
        let body = http_request(self.0, "Rust", &url, &headers).await?;
        Ok(WebPlaybackResponse {
            security_challenge: false,
            response: Response {
                status: 200,
                content_type: Some("application/json".into()),
                body,
            },
        })
    }
}
