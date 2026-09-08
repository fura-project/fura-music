use std::collections::{BTreeMap, BTreeSet};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use qqmusic_client::{
    HttpRequest, HttpTransport, QqMusicClient, QqMusicNewSongCategory, ReqwestTransport,
};
use serde_json::{Value, json};

const MUSICU_URL: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const SAMPLE_TRACKS_PER_CATEGORY: usize = 4;
const MAX_CANDIDATES_PER_REQUEST: usize = 90;
const RESPONSE_LIMIT: usize = 256 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const CATEGORIES: [(QqMusicNewSongCategory, &str); 6] = [
    (QqMusicNewSongCategory::MainlandChina, "mainland"),
    (QqMusicNewSongCategory::Western, "western"),
    (QqMusicNewSongCategory::Japan, "japan"),
    (QqMusicNewSongCategory::Korea, "korea"),
    (QqMusicNewSongCategory::Latest, "latest"),
    (QqMusicNewSongCategory::HongKongTaiwan, "hk_tw"),
];

/// Opt-in, content-free comparison of bounded anonymous media strategies.
///
/// Six public catalog reads supply at most four in-memory Tracks per category.
/// Each `VKey` route then receives the same bounded candidate matrix in one
/// request. The probe reports only aggregate counts and item result codes:
/// Track identity, title, filename, purl, vkey, CDN host, and response bodies
/// are never printed or persisted.
#[tokio::test]
#[ignore = "live QQ Music service; run explicitly with QQMUSIC_LIVE_TESTS=1"]
async fn compares_bounded_anonymous_media_candidates() {
    if std::env::var("QQMUSIC_LIVE_TESTS").as_deref() != Ok("1") {
        eprintln!("skipped: set QQMUSIC_LIVE_TESTS=1 for the live request");
        return;
    }

    let client = QqMusicClient::new(ReqwestTransport::new().expect("native HTTPS transport"));
    let tracks = load_track_seeds(&client).await;
    let candidates = tracks.iter().flat_map(media_candidates).collect::<Vec<_>>();
    assert!(!candidates.is_empty(), "public sample contained no Tracks");

    let guid = comparison_guid();
    let url = evaluate_route(client.transport(), Route::UrlGetVkey, &candidates, &guid).await;
    let cgi = evaluate_route(client.transport(), Route::CgiGetVkey, &candidates, &guid).await;

    let base_failures = tracks
        .iter()
        .filter(|track| {
            !url.playable_tracks.contains(&track.track_index)
                && !cgi.playable_tracks.contains(&track.track_index)
        })
        .collect::<Vec<_>>();
    let extended_candidates = base_failures
        .iter()
        .flat_map(|track| extended_media_candidates(track))
        .collect::<Vec<_>>();
    let extended_url = evaluate_route(
        client.transport(),
        Route::UrlGetVkey,
        &extended_candidates,
        &guid,
    )
    .await;
    let extended_cgi = evaluate_route(
        client.transport(),
        Route::CgiGetVkey,
        &extended_candidates,
        &guid,
    )
    .await;

    for format in [MediaFormat::Mp3Standard, MediaFormat::AacFallback] {
        let source = cgi
            .probe_sources
            .get(&format)
            .unwrap_or_else(|| panic!("{} produced no source for a byte probe", format.label()));
        probe_source_bytes(client.transport(), source, format).await;
        eprintln!("source-byte probe: format={}, result=valid", format.label());
    }
    for format in [MediaFormat::OggStandard, MediaFormat::AacLow] {
        if let Some(source) = extended_cgi.probe_sources.get(&format) {
            probe_source_bytes(client.transport(), source, format).await;
            eprintln!("source-byte probe: format={}, result=valid", format.label());
        }
    }

    let both = url
        .playable_tracks
        .intersection(&cgi.playable_tracks)
        .count();
    let url_only = url.playable_tracks.difference(&cgi.playable_tracks).count();
    let cgi_only = cgi.playable_tracks.difference(&url.playable_tracks).count();
    let neither = tracks.len() - url.playable_tracks.union(&cgi.playable_tracks).count();

    eprintln!(
        "media-source comparison: sample_tracks={}, candidates={}, both={}, url_only={}, cgi_only={}, neither={}",
        tracks.len(),
        candidates.len(),
        both,
        url_only,
        cgi_only,
        neither,
    );
    url.print_summary();
    cgi.print_summary();
    eprintln!(
        "extended-format comparison: base_failures={}, candidates={}, rescued_tracks={}",
        base_failures.len(),
        extended_candidates.len(),
        extended_url
            .playable_tracks
            .union(&extended_cgi.playable_tracks)
            .count(),
    );
    extended_url.print_summary();
    extended_cgi.print_summary();
    for outcome in [&url, &cgi, &extended_url, &extended_cgi] {
        assert_eq!(
            outcome.returned,
            outcome.submitted,
            "{} did not return one item per submitted candidate",
            outcome.route.label()
        );
        assert_eq!(
            outcome.correlated,
            outcome.submitted,
            "{} returned an incomplete candidate correlation",
            outcome.route.label()
        );
        assert_eq!(
            outcome.unexpected,
            0,
            "{} returned an unrequested candidate",
            outcome.route.label()
        );
    }
}

async fn load_track_seeds(client: &QqMusicClient<ReqwestTransport>) -> Vec<TrackSeed> {
    let mut tracks = Vec::new();
    for (category, label) in CATEGORIES {
        let collection = client
            .new_songs(category)
            .await
            .unwrap_or_else(|error| panic!("{label} public collection failed: {error:?}"));
        for track in collection.tracks().iter().take(SAMPLE_TRACKS_PER_CATEGORY) {
            tracks.push(TrackSeed {
                track_index: tracks.len(),
                category: label,
                song_mid: track.song_mid().to_owned(),
                file_media_mid: track.file_media_mid().map(ToOwned::to_owned),
            });
        }
    }
    tracks
}

struct TrackSeed {
    track_index: usize,
    category: &'static str,
    song_mid: String,
    file_media_mid: Option<String>,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Route {
    UrlGetVkey,
    CgiGetVkey,
}

impl Route {
    const fn label(self) -> &'static str {
        match self {
            Self::UrlGetVkey => "url_get_vkey",
            Self::CgiGetVkey => "cgi_get_vkey",
        }
    }
}

#[derive(Clone, Copy, Eq, Ord, PartialEq, PartialOrd)]
enum MediaFormat {
    FlacLossless,
    OggHigh,
    OggStandard,
    OggLow,
    Mp3High,
    Mp3Standard,
    AacHigh,
    AacFallback,
    AacLow,
}

impl MediaFormat {
    const ALL: [Self; 9] = [
        Self::FlacLossless,
        Self::OggHigh,
        Self::OggStandard,
        Self::OggLow,
        Self::Mp3High,
        Self::Mp3Standard,
        Self::AacHigh,
        Self::AacFallback,
        Self::AacLow,
    ];
    const CORE: [Self; 3] = [Self::Mp3High, Self::Mp3Standard, Self::AacFallback];
    const EXTENDED: [Self; 6] = [
        Self::FlacLossless,
        Self::OggHigh,
        Self::OggStandard,
        Self::OggLow,
        Self::AacHigh,
        Self::AacLow,
    ];

    const fn prefix(self) -> &'static str {
        match self {
            Self::FlacLossless => "F000",
            Self::OggHigh => "O800",
            Self::OggStandard => "O600",
            Self::OggLow => "O400",
            Self::Mp3High => "M800",
            Self::Mp3Standard => "M500",
            Self::AacHigh => "C600",
            Self::AacFallback => "C400",
            Self::AacLow => "C200",
        }
    }

    const fn extension(self) -> &'static str {
        match self {
            Self::FlacLossless => ".flac",
            Self::OggHigh | Self::OggStandard | Self::OggLow => ".ogg",
            Self::Mp3High | Self::Mp3Standard => ".mp3",
            Self::AacHigh | Self::AacFallback | Self::AacLow => ".m4a",
        }
    }

    const fn label(self) -> &'static str {
        match self {
            Self::FlacLossless => "f000",
            Self::OggHigh => "o800",
            Self::OggStandard => "o600",
            Self::OggLow => "o400",
            Self::Mp3High => "m800",
            Self::Mp3Standard => "m500",
            Self::AacHigh => "c600",
            Self::AacFallback => "c400",
            Self::AacLow => "c200",
        }
    }
}

#[derive(Clone, Copy, Eq, Ord, PartialEq, PartialOrd)]
enum FilenameIdentity {
    Canonical,
    SongMidOnly,
    SongMidPlusFileMid,
}

impl FilenameIdentity {
    const fn label(self) -> &'static str {
        match self {
            Self::Canonical => "canonical",
            Self::SongMidOnly => "song_mid_only",
            Self::SongMidPlusFileMid => "song_mid_plus_file_mid",
        }
    }
}

struct Candidate {
    track_index: usize,
    category: &'static str,
    song_mid: String,
    filename: String,
    format: MediaFormat,
    identity: FilenameIdentity,
}

fn media_candidates(track: &TrackSeed) -> Vec<Candidate> {
    let mut candidates = Vec::new();
    for format in MediaFormat::CORE {
        let canonical_body = track
            .file_media_mid
            .as_deref()
            .map_or_else(|| format!("{0}{0}", track.song_mid), ToOwned::to_owned);
        push_candidate(
            &mut candidates,
            track.track_index,
            track.category,
            &track.song_mid,
            &canonical_body,
            format,
            FilenameIdentity::Canonical,
        );
        push_candidate(
            &mut candidates,
            track.track_index,
            track.category,
            &track.song_mid,
            &track.song_mid,
            format,
            FilenameIdentity::SongMidOnly,
        );
        if let Some(file_media_mid) = track.file_media_mid.as_deref() {
            push_candidate(
                &mut candidates,
                track.track_index,
                track.category,
                &track.song_mid,
                &format!("{}{file_media_mid}", track.song_mid),
                format,
                FilenameIdentity::SongMidPlusFileMid,
            );
        }
    }
    candidates
}

fn extended_media_candidates(track: &TrackSeed) -> Vec<Candidate> {
    let mut candidates = Vec::new();
    let canonical_body = track
        .file_media_mid
        .as_deref()
        .map_or_else(|| format!("{0}{0}", track.song_mid), ToOwned::to_owned);
    for format in MediaFormat::EXTENDED {
        push_candidate(
            &mut candidates,
            track.track_index,
            track.category,
            &track.song_mid,
            &canonical_body,
            format,
            FilenameIdentity::Canonical,
        );
    }
    candidates
}

fn push_candidate(
    candidates: &mut Vec<Candidate>,
    track_index: usize,
    category: &'static str,
    song_mid: &str,
    filename_body: &str,
    format: MediaFormat,
    identity: FilenameIdentity,
) {
    let filename = format!("{}{filename_body}{}", format.prefix(), format.extension());
    if candidates
        .iter()
        .any(|candidate| candidate.track_index == track_index && candidate.filename == filename)
    {
        return;
    }
    candidates.push(Candidate {
        track_index,
        category,
        song_mid: song_mid.to_owned(),
        filename,
        format,
        identity,
    });
}

struct RouteOutcome {
    route: Route,
    request_count: usize,
    submitted: usize,
    returned: usize,
    correlated: usize,
    unexpected: usize,
    playable_items: usize,
    playable_tracks: BTreeSet<usize>,
    playable_by_format: BTreeMap<MediaFormat, BTreeSet<usize>>,
    playable_by_identity: BTreeMap<FilenameIdentity, BTreeSet<usize>>,
    playable_by_category: BTreeMap<&'static str, BTreeSet<usize>>,
    result_codes: BTreeMap<i64, usize>,
    missing_result: usize,
    sip_count: usize,
    probe_sources: BTreeMap<MediaFormat, String>,
}

impl RouteOutcome {
    fn empty(route: Route) -> Self {
        Self {
            route,
            request_count: 0,
            submitted: 0,
            returned: 0,
            correlated: 0,
            unexpected: 0,
            playable_items: 0,
            playable_tracks: BTreeSet::new(),
            playable_by_format: BTreeMap::new(),
            playable_by_identity: BTreeMap::new(),
            playable_by_category: BTreeMap::new(),
            result_codes: BTreeMap::new(),
            missing_result: 0,
            sip_count: 0,
            probe_sources: BTreeMap::new(),
        }
    }

    fn merge(&mut self, other: Self) {
        self.request_count += other.request_count;
        self.submitted += other.submitted;
        self.returned += other.returned;
        self.correlated += other.correlated;
        self.unexpected += other.unexpected;
        self.playable_items += other.playable_items;
        self.playable_tracks.extend(other.playable_tracks);
        for (format, tracks) in other.playable_by_format {
            self.playable_by_format
                .entry(format)
                .or_default()
                .extend(tracks);
        }
        for (identity, tracks) in other.playable_by_identity {
            self.playable_by_identity
                .entry(identity)
                .or_default()
                .extend(tracks);
        }
        for (category, tracks) in other.playable_by_category {
            self.playable_by_category
                .entry(category)
                .or_default()
                .extend(tracks);
        }
        for (code, count) in other.result_codes {
            *self.result_codes.entry(code).or_default() += count;
        }
        self.missing_result += other.missing_result;
        self.sip_count = self.sip_count.max(other.sip_count);
        for (format, source) in other.probe_sources {
            self.probe_sources.entry(format).or_insert(source);
        }
    }

    fn print_summary(&self) {
        let formats = MediaFormat::ALL
            .map(|format| {
                format!(
                    "{}:{}",
                    format.label(),
                    self.playable_by_format
                        .get(&format)
                        .map_or(0, BTreeSet::len)
                )
            })
            .join(",");
        let identities = [
            FilenameIdentity::Canonical,
            FilenameIdentity::SongMidOnly,
            FilenameIdentity::SongMidPlusFileMid,
        ]
        .map(|identity| {
            format!(
                "{}:{}",
                identity.label(),
                self.playable_by_identity
                    .get(&identity)
                    .map_or(0, BTreeSet::len)
            )
        })
        .join(",");
        let categories = CATEGORIES
            .map(|(_, category)| {
                format!(
                    "{}:{}",
                    category,
                    self.playable_by_category
                        .get(category)
                        .map_or(0, BTreeSet::len)
                )
            })
            .join(",");
        eprintln!(
            "route={}: requests={}, submitted={}, returned={}, correlated={}, unexpected={}, playable_items={}, playable_tracks={}, sip_count={}, formats=[{}], identities=[{}], categories=[{}], result_codes={:?}, missing_result={}",
            self.route.label(),
            self.request_count,
            self.submitted,
            self.returned,
            self.correlated,
            self.unexpected,
            self.playable_items,
            self.playable_tracks.len(),
            self.sip_count,
            formats,
            identities,
            categories,
            self.result_codes,
            self.missing_result,
        );
    }
}

async fn evaluate_route(
    transport: &ReqwestTransport,
    route: Route,
    candidates: &[Candidate],
    guid: &str,
) -> RouteOutcome {
    let mut outcome = RouteOutcome::empty(route);
    for candidates in candidates.chunks(MAX_CANDIDATES_PER_REQUEST) {
        outcome.merge(evaluate_route_batch(transport, route, candidates, guid).await);
    }
    outcome
}

async fn evaluate_route_batch(
    transport: &ReqwestTransport,
    route: Route,
    candidates: &[Candidate],
    guid: &str,
) -> RouteOutcome {
    let response = transport
        .execute(comparison_request(route, candidates, guid))
        .await
        .unwrap_or_else(|error| panic!("{} transport failed: {error:?}", route.label()));
    assert!(
        (200..300).contains(&response.status()),
        "{} returned HTTP {}",
        route.label(),
        response.status()
    );
    parse_route_outcome(route, candidates, response.body())
}

fn comparison_request(route: Route, candidates: &[Candidate], guid: &str) -> HttpRequest {
    let filenames = candidates
        .iter()
        .map(|candidate| candidate.filename.as_str())
        .collect::<Vec<_>>();
    let song_mids = candidates
        .iter()
        .map(|candidate| candidate.song_mid.as_str())
        .collect::<Vec<_>>();
    let song_types = vec![0_u8; candidates.len()];
    let (module, method, comm, param) = match route {
        Route::UrlGetVkey => (
            "music.vkey.GetVkey",
            "UrlGetVkey",
            json!({
                "cv": 13_020_508,
                "v": 13_020_508,
                "ct": "11",
                "tmeAppID": "qqmusic",
                "format": "json",
                "inCharset": "utf-8",
                "outCharset": "utf-8",
                "uid": "0",
                "qq": "0"
            }),
            json!({
                "uin": "0",
                "filename": filenames,
                "guid": guid,
                "songmid": song_mids,
                "songtype": song_types,
                "ctx": 0
            }),
        ),
        Route::CgiGetVkey => (
            "vkey.GetVkeyServer",
            "CgiGetVkey",
            json!({"uin": "0", "format": "json", "ct": 24, "cv": 0}),
            json!({
                "uin": "0",
                "filename": filenames,
                "guid": guid,
                "songmid": song_mids,
                "songtype": song_types,
                "loginflag": 1,
                "platform": "20"
            }),
        ),
    };
    let body = serde_json::to_vec(&json!({
        "comm": comm,
        "req_0": {"module": module, "method": method, "param": param}
    }))
    .expect("comparison request serializes");
    HttpRequest::post(MUSICU_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://y.qq.com")
        .header("Referer", "https://y.qq.com/")
        .body(body)
        .response_body_limit(RESPONSE_LIMIT)
        .timeout(REQUEST_TIMEOUT)
}

fn parse_route_outcome(route: Route, candidates: &[Candidate], body: &[u8]) -> RouteOutcome {
    let envelope: Value = serde_json::from_slice(body)
        .unwrap_or_else(|_| panic!("{} returned invalid JSON", route.label()));
    let global_code = envelope.get("code").and_then(Value::as_i64);
    let request = envelope.get("req_0");
    let request_code = request
        .and_then(|value| value.get("code"))
        .and_then(Value::as_i64);
    assert_eq!(
        global_code,
        Some(0),
        "{} global code changed",
        route.label()
    );
    assert_eq!(
        request_code,
        Some(0),
        "{} request code changed",
        route.label()
    );
    let data = request
        .and_then(|value| value.get("data"))
        .and_then(Value::as_object)
        .unwrap_or_else(|| panic!("{} response omitted data", route.label()));
    let data_code = data.get("retcode").and_then(Value::as_i64);
    assert!(
        data_code.is_none_or(|code| code == 0),
        "{} data code changed: {data_code:?}",
        route.label()
    );
    let items = data
        .get("midurlinfo")
        .and_then(Value::as_array)
        .unwrap_or_else(|| panic!("{} response omitted media items", route.label()));

    let mut outcome = RouteOutcome {
        route,
        request_count: 1,
        submitted: candidates.len(),
        returned: items.len(),
        correlated: 0,
        unexpected: 0,
        playable_items: 0,
        playable_tracks: BTreeSet::new(),
        playable_by_format: BTreeMap::new(),
        playable_by_identity: BTreeMap::new(),
        playable_by_category: BTreeMap::new(),
        result_codes: BTreeMap::new(),
        missing_result: 0,
        sip_count: data
            .get("sip")
            .and_then(Value::as_array)
            .map_or(0, Vec::len),
        probe_sources: BTreeMap::new(),
    };
    for item in items {
        record_item(&mut outcome, route, candidates, data, item);
    }
    outcome
}

fn record_item(
    outcome: &mut RouteOutcome,
    route: Route,
    candidates: &[Candidate],
    data: &serde_json::Map<String, Value>,
    item: &Value,
) {
    let filename = item.get("filename").and_then(Value::as_str);
    let song_mid = item.get("songmid").and_then(Value::as_str);
    let Some(candidate) = candidates.iter().find(|candidate| {
        Some(candidate.filename.as_str()) == filename
            && Some(candidate.song_mid.as_str()) == song_mid
    }) else {
        outcome.unexpected += 1;
        return;
    };
    outcome.correlated += 1;
    match item.get("result").and_then(Value::as_i64) {
        Some(code) => *outcome.result_codes.entry(code).or_default() += 1,
        None => outcome.missing_result += 1,
    }
    let playable = item
        .get("purl")
        .and_then(Value::as_str)
        .is_some_and(|path| !path.trim().is_empty());
    if !playable {
        return;
    }
    outcome.playable_items += 1;
    outcome.playable_tracks.insert(candidate.track_index);
    outcome
        .playable_by_format
        .entry(candidate.format)
        .or_default()
        .insert(candidate.track_index);
    outcome
        .playable_by_identity
        .entry(candidate.identity)
        .or_default()
        .insert(candidate.track_index);
    outcome
        .playable_by_category
        .entry(candidate.category)
        .or_default()
        .insert(candidate.track_index);
    if route == Route::CgiGetVkey
        && let Some(source) = safe_source_uri(data, item, &candidate.filename)
    {
        outcome
            .probe_sources
            .entry(candidate.format)
            .or_insert(source);
    }
}

fn safe_source_uri(
    data: &serde_json::Map<String, Value>,
    item: &Value,
    expected_filename: &str,
) -> Option<String> {
    let path = item.get("purl")?.as_str()?;
    if path.trim() != path || path.starts_with('/') || path.starts_with("//") {
        return None;
    }
    let raw_bases = data.get("sip")?.as_array()?;
    for raw_base in raw_bases.iter().filter_map(Value::as_str) {
        let base = reqwest::Url::parse(raw_base).ok()?;
        let allowed_host = base
            .host_str()
            .is_some_and(|host| host.ends_with(".stream.qqmusic.qq.com"));
        let valid_base = matches!(base.scheme(), "http" | "https")
            && allowed_host
            && base.username().is_empty()
            && base.password().is_none()
            && base.query().is_none()
            && base.fragment().is_none()
            && base.path().ends_with('/');
        if !valid_base {
            continue;
        }
        let source = base.join(path).ok()?;
        let same_authority = source.scheme() == base.scheme()
            && source.host_str() == base.host_str()
            && source.port_or_known_default() == base.port_or_known_default();
        let exact_file = source
            .path_segments()
            .and_then(Iterator::last)
            .is_some_and(|filename| filename == expected_filename);
        if same_authority && exact_file {
            return Some(source.into());
        }
    }
    None
}

async fn probe_source_bytes(transport: &ReqwestTransport, source: &str, format: MediaFormat) {
    let response = transport
        .execute(
            HttpRequest::get(source)
                .header("Range", "bytes=0-4095")
                .header("Referer", "https://y.qq.com/")
                .response_body_limit(8 * 1024)
                .timeout(Duration::from_secs(20)),
        )
        .await
        .unwrap_or_else(|error| panic!("{} source byte probe failed: {error:?}", format.label()));
    assert!(
        matches!(response.status(), 200 | 206),
        "{} source byte probe returned HTTP {}",
        format.label(),
        response.status()
    );
    let body = response.body();
    let valid_signature = match format {
        MediaFormat::FlacLossless => body.starts_with(b"fLaC"),
        MediaFormat::OggHigh | MediaFormat::OggStandard | MediaFormat::OggLow => {
            body.starts_with(b"OggS")
        }
        MediaFormat::Mp3High | MediaFormat::Mp3Standard => {
            body.starts_with(b"ID3")
                || body
                    .get(..2)
                    .is_some_and(|header| header[0] == 0xff && header[1] & 0xe0 == 0xe0)
        }
        MediaFormat::AacHigh | MediaFormat::AacFallback | MediaFormat::AacLow => {
            body.get(4..8) == Some(b"ftyp")
        }
    };
    assert!(
        valid_signature,
        "{} source signature changed",
        format.label()
    );
}

fn comparison_guid() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock after Unix epoch")
        .as_nanos();
    format!("{:010}", nanos % 10_000_000_000)
}
