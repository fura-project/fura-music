use super::*;
use music_domain::{ProviderId, TrackSearchPage, TrackSummary};
use provider_api::{MusicProvider, ProviderDescriptor};
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex, atomic::AtomicUsize};

const QUERY: &str = "synthetic-query-not-a-diagnostic";
const TITLE: &str = "Synthetic title only on terminal";
const ARTIST: &str = "Synthetic artist only on terminal";
const ALBUM: &str = "Synthetic album only on terminal";
const HASH: &str = "0123456789ABCDEF0123456789ABCDEF";

struct FakeTransport {
    calls: Arc<AtomicUsize>,
    reply: Mutex<Option<Result<Response, Error>>>,
}

impl Transport for FakeTransport {
    async fn send(&self, request: Request) -> Result<Response, Error> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        // Any detail, ranking, second page or fallback fails, even in error tests.
        let url = url::Url::parse(request.url()).unwrap();
        assert_eq!(url.host_str(), Some("songsearch.kugou.com"));
        assert_eq!(url.path(), "/song_search_v2");
        let query: std::collections::BTreeMap<_, _> = url.query_pairs().collect();
        assert_eq!(query["page"], "1");
        assert_eq!(query["pagesize"], SEARCH_PAGE_SIZE.to_string());
        assert_eq!(query["keyword"], QUERY);
        self.reply.lock().unwrap().take().expect("no second send")
    }
}

fn row(mix: &str) -> Value {
    json!({
        "MixSongID":mix, "FileHash":HASH, "Audioid":42,
        "OriSongName":TITLE, "Singers":[{"id":7,"name":ARTIST}],
        "AlbumID":"9", "AlbumName":ALBUM, "Duration":123,
    })
}

fn response(rows: Vec<Value>) -> Response {
    Response {
        status: 200,
        content_type: Some("application/json".into()),
        body: serde_json::to_vec(&json!({
            "status":1, "error_code":0,
            "data":{"page":1,"pagesize":SEARCH_PAGE_SIZE,"size":rows.len(),
                "total":100,"lists":rows},
        }))
        .unwrap(),
    }
}

fn provider(
    reply: Result<Response, Error>,
) -> (KuGouProvider<OneSearch<FakeTransport>>, Arc<AtomicUsize>) {
    let calls = Arc::new(AtomicUsize::new(0));
    (
        KuGouProvider::new(KuGouClient::new(OneSearch::new(FakeTransport {
            calls: calls.clone(),
            reply: Mutex::new(Some(reply)),
        }))),
        calls,
    )
}

#[derive(Default)]
struct Script {
    search_authority: bool,
    query: Option<String>,
    selection: Option<String>,
    playback_authority: bool,
    events: VecDeque<&'static str>,
    diagnostics: Vec<Diagnostic>,
}

impl Script {
    fn approved() -> Self {
        Self {
            search_authority: true,
            query: Some(QUERY.into()),
            selection: Some("1".into()),
            playback_authority: true,
            ..Self::default()
        }
    }
}

impl Interaction for Script {
    fn approve_search(&mut self) -> bool {
        self.events.push_back("phase_a");
        self.search_authority
    }
    fn query(&mut self) -> Option<String> {
        self.events.push_back("query");
        self.query.take()
    }
    fn selection(&mut self, items: &[TrackSearchItem]) -> Option<String> {
        assert!(!items.is_empty());
        self.events.push_back("selection");
        self.selection.take()
    }
    fn approve_playback(&mut self) -> bool {
        self.events.push_back("phase_b");
        self.playback_authority
    }
    fn approve_range(&mut self, _: &str, _: &impl Fn() -> bool) -> bool {
        panic!("range is not authorized by either search or gate authority")
    }
    fn diagnostic(&mut self, value: Diagnostic) {
        self.diagnostics.push(value);
    }
}

#[derive(Default)]
struct RecordingGate(Mutex<Vec<TrackId>>);

impl PlaybackGate for RecordingGate {
    async fn enter(&self, id: &TrackId, _: &mut impl Interaction) {
        self.0.lock().unwrap().push(id.clone());
    }
}

fn no_gate(gate: &RecordingGate) {
    assert!(gate.0.lock().unwrap().is_empty());
}

#[tokio::test]
async fn unauthorized_search_does_not_read_query_or_send_or_enter_gate() {
    let (provider, calls) = provider(Ok(response(vec![row("123")])));
    let mut human = Script::approved();
    human.search_authority = false;
    let gate = RecordingGate::default();
    assert_eq!(
        workflow(&provider, &mut human, &gate).await,
        Err(Stop::SearchNotAuthorized)
    );
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(human.events, ["phase_a"]);
    no_gate(&gate);
}

#[tokio::test]
async fn two_authorities_hand_off_the_exact_provider_mapped_selected_track() {
    // Deliberately identical presentation, different identities: no fuzzy matching.
    let (provider, calls) = provider(Ok(response(vec![row("123"), row("456")])));
    let mut human = Script::approved();
    human.selection = Some("2".into());
    let gate = RecordingGate::default();
    assert_eq!(workflow(&provider, &mut human, &gate).await, Ok(()));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(human.events, ["phase_a", "query", "selection", "phase_b"]);
    let ids = gate.0.lock().unwrap();
    assert_eq!(ids.len(), 1);
    assert_eq!(ids[0].provider(), &provider_kugou::provider_id());
    assert_eq!(ids[0].opaque(), format!("v1:456:{HASH}:42:123:9"));
    assert_eq!(
        human.diagnostics[..4],
        [
            Diagnostic::SearchBudget,
            Diagnostic::ResultCount(2),
            Diagnostic::HumanSelection,
            Diagnostic::PlaybackAuthority
        ]
    );
}

#[tokio::test]
async fn errors_and_rate_risk_or_invalid_responses_never_retry_or_fallback() {
    let mut rate = response(vec![row("123")]);
    rate.status = 429;
    let mut denied = response(vec![row("123")]);
    denied.status = 403;
    let mut malformed = response(vec![]);
    malformed.body = b"synthetic-invalid".to_vec();
    for reply in [
        Err(Error::TemporaryNetworkFailure),
        Err(Error::SecurityVerificationRequired),
        Ok(rate),
        Ok(denied),
        Ok(malformed),
    ] {
        let (provider, calls) = provider(reply);
        let mut human = Script::approved();
        let gate = RecordingGate::default();
        assert_eq!(
            workflow(&provider, &mut human, &gate).await,
            Err(Stop::SearchFailed)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(human.events, ["phase_a", "query"]);
        no_gate(&gate);
    }
}

#[tokio::test]
async fn same_owner_cannot_refill_the_search_budget_after_completion_or_failure() {
    for reply in [
        Ok(response(vec![row("123")])),
        Err(Error::TemporaryNetworkFailure),
    ] {
        let (provider, calls) = provider(reply);
        let gate = RecordingGate::default();
        let _ = workflow(&provider, &mut Script::approved(), &gate).await;
        let gate_count = gate.0.lock().unwrap().len();
        assert_eq!(
            workflow(&provider, &mut Script::approved(), &gate).await,
            Err(Stop::SearchFailed)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(gate.0.lock().unwrap().len(), gate_count);
    }
}

#[tokio::test]
async fn concurrent_search_calls_still_only_send_once() {
    let (provider, calls) = provider(Ok(response(vec![row("123")])));
    let (a, b) = tokio::join!(
        provider.search_tracks(QUERY.into(), 1, SEARCH_PAGE_SIZE),
        provider.search_tracks(QUERY.into(), 1, SEARCH_PAGE_SIZE),
    );
    assert_ne!(a.is_ok(), b.is_ok());
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn dropping_a_pending_search_does_not_refund_its_send_budget() {
    struct Pending(AtomicUsize);
    impl Transport for Pending {
        async fn send(&self, _: Request) -> Result<Response, Error> {
            self.0.fetch_add(1, Ordering::SeqCst);
            std::future::pending().await
        }
    }
    let provider = KuGouProvider::new(KuGouClient::new(OneSearch::new(Pending(AtomicUsize::new(
        0,
    )))));
    let mut first = Box::pin(provider.search_tracks(QUERY.into(), 1, SEARCH_PAGE_SIZE));
    assert!(
        std::future::poll_fn(|cx| std::task::Poll::Ready(first.as_mut().poll(cx)))
            .await
            .is_pending()
    );
    drop(first);
    assert!(
        provider
            .search_tracks(QUERY.into(), 1, SEARCH_PAGE_SIZE)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn cancellation_invalidates_before_and_awaits_gate_cleanup() {
    let owner = Arc::new(AuthenticatedStandardCandidate::new(()));
    let id = TrackId::new(
        provider_kugou::provider_id(),
        format!("v1:123:{HASH}:42:123:9"),
    )
    .unwrap();
    let attempt = owner.begin_capture(&id).unwrap();
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let cleaned = AtomicBool::new(false);
    let current = Arc::new(AtomicBool::new(true));
    let signal_current = Arc::clone(&current);
    let signal_owner = Arc::clone(&owner);
    let cancellation = tokio::spawn(async move {
        started_rx.await.unwrap();
        signal_current.store(false, Ordering::SeqCst);
        signal_owner.clear();
    });
    await_gate_cleanup(
        async {
            started_tx.send(()).unwrap();
            while current.load(Ordering::SeqCst) {
                tokio::task::yield_now().await;
            }
            assert!(!owner.is_capture_current(&attempt));
            tokio::task::yield_now().await;
            cleaned.store(true, Ordering::SeqCst);
        },
        cancellation,
    )
    .await;
    assert!(cleaned.load(Ordering::SeqCst));
    assert_eq!(
        owner.begin_capture(&id).unwrap_err(),
        kugou_client::web_playback_candidate::WebPlaybackError::AttemptConsumed
    );
}

#[tokio::test]
async fn empty_search_stops_without_selecting_or_entering_cdp() {
    let mut reply = response(vec![]);
    // A valid exhausted zero-result page, not malformed empty-with-more.
    let mut body: Value = serde_json::from_slice(&reply.body).unwrap();
    body["data"]["total"] = json!(0);
    reply.body = serde_json::to_vec(&body).unwrap();
    let (provider, calls) = provider(Ok(reply));
    let mut human = Script::approved();
    let gate = RecordingGate::default();
    assert_eq!(
        workflow(&provider, &mut human, &gate).await,
        Err(Stop::EmptySearch)
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(human.events, ["phase_a", "query"]);
    no_gate(&gate);
}

#[tokio::test]
async fn all_omitted_first_page_with_more_never_fetches_a_second_page() {
    let mut omitted = row("123");
    omitted.as_object_mut().unwrap().remove("FileHash");
    let (provider, calls) = provider(Ok(response(vec![omitted])));
    let mut human = Script::approved();
    let gate = RecordingGate::default();
    assert_eq!(
        workflow(&provider, &mut human, &gate).await,
        Err(Stop::EmptySearch)
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(human.events, ["phase_a", "query"]);
    no_gate(&gate);
}

#[tokio::test]
async fn cancelling_query_or_selection_ends_run_without_cdp() {
    for at_query in [true, false] {
        let (provider, calls) = provider(Ok(response(vec![row("123")])));
        let mut human = Script::approved();
        if at_query {
            human.query = None;
        } else {
            human.selection = None;
        }
        let gate = RecordingGate::default();
        assert_eq!(
            workflow(&provider, &mut human, &gate).await,
            Err(Stop::Cancelled)
        );
        assert_eq!(calls.load(Ordering::SeqCst), usize::from(!at_query));
        assert!(!human.events.contains(&"phase_b"));
        no_gate(&gate);
    }
}

#[tokio::test]
async fn invalid_ordinals_and_pasted_track_context_are_not_identity_inputs() {
    for selection in [
        "0",
        "2",
        "-1",
        "1.0",
        "1 2",
        "qq-music:123",
        "v1:123:0123456789ABCDEF0123456789ABCDEF:42:123:9",
        HASH,
        "18446744073709551616",
    ] {
        let (provider, calls) = provider(Ok(response(vec![row("123")])));
        let mut human = Script::approved();
        human.selection = Some(selection.into());
        let gate = RecordingGate::default();
        assert_eq!(
            workflow(&provider, &mut human, &gate).await,
            Err(Stop::InvalidSelection)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(!human.events.contains(&"phase_b"));
        no_gate(&gate);
    }
}

#[tokio::test]
async fn missing_album_or_duration_context_stops_without_detail_or_phase_b() {
    for (album, duration) in [("0", 123), ("9", 0)] {
        let mut value = row("123");
        value["AlbumID"] = json!(album);
        value["AlbumName"] = json!("");
        value["Duration"] = json!(duration);
        let (provider, calls) = provider(Ok(response(vec![value])));
        let mut human = Script::approved();
        let gate = RecordingGate::default();
        assert_eq!(
            workflow(&provider, &mut human, &gate).await,
            Err(Stop::TrackContextUnavailable)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(!human.events.contains(&"phase_b"));
        no_gate(&gate);
    }
}

#[tokio::test]
async fn an_absent_album_title_is_not_confused_with_absent_provider_context() {
    let mut value = row("123");
    value["AlbumName"] = Value::Null;
    let (provider, calls) = provider(Ok(response(vec![value])));
    let gate = RecordingGate::default();
    assert_eq!(
        workflow(&provider, &mut Script::approved(), &gate).await,
        Ok(())
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert_eq!(gate.0.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn phase_a_does_not_authorize_authenticated_gate_or_range() {
    let (provider, calls) = provider(Ok(response(vec![row("123")])));
    let mut human = Script::approved();
    human.playback_authority = false;
    let gate = RecordingGate::default();
    assert_eq!(
        workflow(&provider, &mut human, &gate).await,
        Err(Stop::PlaybackNotAuthorized)
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    assert!(!human.diagnostics.contains(&Diagnostic::PlaybackAuthority));
    no_gate(&gate);
}

struct ReplacedMapping(TrackId);
impl MusicProvider for ReplacedMapping {
    fn descriptor(&self) -> ProviderDescriptor {
        unreachable!()
    }
}
impl TrackSearchProvider for ReplacedMapping {
    type Error = SearchError;
    async fn search_tracks(
        &self,
        _: String,
        _: u32,
        _: u32,
    ) -> Result<TrackSearchPage, SearchError> {
        let track = TrackSummary::new(self.0.clone(), TITLE, vec![ARTIST.into()]).unwrap();
        Ok(TrackSearchPage::new(
            1,
            1,
            false,
            vec![TrackSearchItem::new(track, None, vec![])],
        ))
    }
}

#[tokio::test]
async fn foreign_provider_and_invalid_context_never_enter_cdp() {
    for (provider, opaque) in [
        ("qq-music", format!("v1:123:{HASH}:42:123:9")),
        ("netease-cloud-music", format!("v1:123:{HASH}:42:123:9")),
        ("kugou-music", "123".into()),
    ] {
        let provider =
            ReplacedMapping(TrackId::new(ProviderId::new(provider).unwrap(), opaque).unwrap());
        let gate = RecordingGate::default();
        let mut human = Script::approved();
        assert_eq!(
            workflow(&provider, &mut human, &gate).await,
            Err(Stop::TrackContextUnavailable)
        );
        assert!(!human.events.contains(&"phase_b"));
        no_gate(&gate);
    }
}

#[test]
fn bounded_terminal_input_rejects_eof_and_oversized_or_unterminated_lines() {
    for input in [
        String::new(),
        "1".into(),
        format!("{}\n", "a".repeat(258)),
        "中".repeat(100),
    ] {
        assert!(completed_line(input.as_bytes()).is_none());
    }
    assert_eq!(completed_line(b"1\r\n"), Some("1".into()));
    assert_eq!(completed_line(b"\n"), Some(String::new()));
    assert_eq!(selection_index(" 1 ", 1), Some(0));
    assert_eq!(selection_index("+1", 1), None);
}

#[test]
fn terminal_range_wait_is_cancellable_without_another_keystroke() {
    let (mut reader, mut writer) = std::os::unix::net::UnixStream::pair().unwrap();
    let current = Arc::new(AtomicBool::new(true));
    let cancelled = Arc::clone(&current);
    // A partial approval must not block indefinitely or become approval after
    // authority retirement. This is local pipe/TTY I/O, never a Range request.
    writer.write_all(b"AUTHORIZE ONE ").unwrap();
    let retire = std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(20));
        cancelled.store(false, Ordering::SeqCst);
    });
    let start = std::time::Instant::now();
    assert!(terminal_line(&mut reader, &|| current.load(Ordering::SeqCst)).is_none());
    assert!(start.elapsed() < std::time::Duration::from_secs(2));
    retire.join().unwrap();
    writer.write_all(b"RANGE\n").unwrap();
    assert!(terminal_line(&mut reader, &|| false).is_none());
}

#[test]
fn real_input_reader_enforces_length_eof_and_ordinal_only_parsing() {
    for input in [
        b"1\n".to_vec(),
        b"v1:123:opaque\n".to_vec(),
        vec![b'x'; 258],
        vec![],
    ] {
        let (mut reader, mut writer) = std::os::unix::net::UnixStream::pair().unwrap();
        writer.write_all(&input).unwrap();
        drop(writer);
        let line = terminal_line(&mut reader, &|| true);
        if input == b"1\n" {
            assert_eq!(selection_index(line.as_deref().unwrap(), 1), Some(0));
        } else if input == b"v1:123:opaque\n" {
            assert_eq!(selection_index(line.as_deref().unwrap(), 1), None);
        } else {
            assert!(line.is_none());
        }
    }
}

#[test]
fn real_terminal_range_prompt_requires_its_own_current_approval() {
    for (answer, current, expected) in [
        ("AUTHORIZE ONE RANGE\n", true, true),
        ("AUTHORIZE ONE PUBLIC SEARCH\n", true, false),
        ("AUTHORIZE ONE AUTHENTICATED GATE\n", true, false),
        ("\n", true, false),
        ("AUTHORIZE ONE RANGE\n", false, false),
    ] {
        let (reader, mut writer) = std::os::unix::net::UnixStream::pair().unwrap();
        writer.write_all(answer.as_bytes()).unwrap();
        drop(writer);
        let mut terminal = Terminal {
            reader: File::from(std::os::fd::OwnedFd::from(reader)),
            display: OpenOptions::new().write(true).open("/dev/null").unwrap(),
        };
        assert_eq!(
            terminal.approve_range("offline-media.example.org", &|| current),
            expected
        );
    }
}

#[test]
fn cargo_default_production_graph_excludes_harness_and_its_kugou_dependencies() {
    let metadata = std::process::Command::new(env!("CARGO"))
        .args([
            "metadata",
            "--offline",
            "--locked",
            "--no-deps",
            "--format-version",
            "1",
        ])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .unwrap();
    assert!(
        metadata.status.success(),
        "offline Cargo metadata must be available"
    );
    let metadata: Value = serde_json::from_slice(&metadata.stdout).unwrap();
    let package = metadata["packages"]
        .as_array()
        .unwrap()
        .iter()
        .find(|package| package["name"] == "rust_lib_flutterustmusic")
        .unwrap();
    let target = package["targets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|target| target["name"] == "kugou-human-gate")
        .unwrap();
    assert_eq!(target["required-features"], json!(["kugou-cdp-gate"]));
    let mut pending = vec!["default".to_owned()];
    let mut visited = std::collections::BTreeSet::new();
    while let Some(feature) = pending.pop() {
        assert_ne!(
            feature, "kugou-cdp-gate",
            "default must not enable the gate"
        );
        if !visited.insert(feature.clone()) {
            continue;
        }
        if let Some(children) = package["features"][feature].as_array() {
            pending.extend(
                children
                    .iter()
                    .map(|value| value.as_str().unwrap().to_owned()),
            );
        }
    }
    let tree = std::process::Command::new(env!("CARGO"))
        .args([
            "tree",
            "--offline",
            "--locked",
            "-p",
            "rust_lib_flutterustmusic",
            "--no-default-features",
            "-e",
            "normal",
        ])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .unwrap();
    assert!(
        tree.status.success(),
        "offline Cargo dependency graph must be available"
    );
    let tree = String::from_utf8(tree.stdout).unwrap();
    assert!(!tree.contains("kugou-client"));
    assert!(!tree.contains("provider-kugou"));
}

#[tokio::test]
async fn diagnostic_channel_never_contains_presentation_query_or_protocol_context() {
    let (provider, _) = self::provider(Ok(response(vec![row("123")])));
    let mut human = Script::approved();
    workflow(&provider, &mut human, &RecordingGate::default())
        .await
        .unwrap();
    for diagnostic in &human.diagnostics {
        let output = format!("{diagnostic}\n{diagnostic:?}");
        for forbidden in [
            QUERY,
            TITLE,
            ARTIST,
            ALBUM,
            HASH,
            "v1:",
            "MixSongID",
            "Audioid",
            "KugooID=",
            "token=",
            "https://",
        ] {
            assert!(!output.contains(forbidden));
        }
    }
    let (provider, _) = self::provider(Ok(response(vec![row("123")])));
    let page = provider
        .search_tracks(QUERY.into(), 1, SEARCH_PAGE_SIZE)
        .await
        .unwrap();
    let mut terminal = Vec::new();
    present_results(&mut terminal, page.items()).unwrap();
    let output = String::from_utf8(terminal).unwrap();
    assert_eq!(output, format!("1. {TITLE} | {ARTIST} | {ALBUM} | 2:03\n"));
    for forbidden in [QUERY, HASH, "v1:", "123", "42", "9"] {
        assert!(!output.contains(forbidden));
    }
}
