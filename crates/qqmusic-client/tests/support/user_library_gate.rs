use std::io;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};

use qqmusic_client::{Credential, HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use serde_json::Value;

use super::{QqMusicClient, ReqwestTransport};

const GATE: &str = "FURA_QQ_USER_LIBRARY_GATE";
const MUSICU: &str = "https://u.y.qq.com/cgi-bin/musicu.fcg";
const ALBUMS: &str = "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg";

#[derive(Clone, Copy)]
struct Read {
    phase: &'static str,
    result_key: Option<&'static str>,
    list_key: &'static str,
    total_key: &'static str,
    more_key: &'static str,
}

const ACCOUNT: Read = Read {
    phase: "account_verification",
    result_key: Some("music.UserInfo.userInfoServer"),
    list_key: "",
    total_key: "",
    more_key: "",
};
const OWNED: Read = Read {
    phase: "owned_request",
    result_key: Some("music.musicasset.PlaylistBaseRead"),
    list_key: "v_playlist",
    total_key: "",
    more_key: "bFinish",
};
const FAVORITE: Read = Read {
    phase: "favorite_request",
    result_key: Some("music.musicasset.PlaylistFavRead"),
    list_key: "v_list",
    total_key: "total",
    more_key: "hasmore",
};
const LIKED: Read = Read {
    phase: "liked_songs_detail",
    result_key: Some("music.srfDissInfo.DissInfo"),
    list_key: "songlist",
    total_key: "total_song_num",
    more_key: "hasmore",
};
const ALBUM: Read = Read {
    phase: "favorite_albums",
    result_key: None,
    list_key: "albumlist",
    total_key: "totalalbum",
    more_key: "has_more",
};
const ARTIST: Read = Read {
    phase: "favorite_artists",
    result_key: Some("req_0"),
    list_key: "List",
    total_key: "Total",
    more_key: "HasMore",
};

#[derive(Debug, Default, Eq, PartialEq)]
enum JsonShape {
    #[default]
    Missing,
    Object,
    Array,
    Other,
}

impl JsonShape {
    fn of(value: Option<&Value>) -> Self {
        match value {
            None => Self::Missing,
            Some(Value::Object(_)) => Self::Object,
            Some(Value::Array(_)) => Self::Array,
            Some(_) => Self::Other,
        }
    }
}

#[derive(Debug, Default)]
struct WireObservation {
    http_status: Option<u16>,
    global_code: Option<i64>,
    subrequest_code: Option<i64>,
    envelope_shape: JsonShape,
    result_shape: JsonShape,
    data_shape: JsonShape,
    list_shape: JsonShape,
    total_present: bool,
    continuation_type: &'static str,
    has_more: Option<bool>,
    raw_count: Option<usize>,
    data_code: Option<i64>,
}

impl WireObservation {
    fn from_response(read: Read, response: &HttpResponse) -> Self {
        let mut shape = Self {
            http_status: Some(response.status()),
            continuation_type: "missing",
            ..Self::default()
        };
        let Ok(body) = serde_json::from_slice::<Value>(response.body()) else {
            return shape;
        };
        shape.envelope_shape = JsonShape::of(Some(&body));
        shape.global_code = body.get("code").and_then(Value::as_i64);
        let result = read.result_key.map_or(Some(&body), |key| body.get(key));
        shape.result_shape = JsonShape::of(result);
        shape.subrequest_code = if read.result_key.is_some() {
            result.and_then(|value| value.get("code"))
        } else {
            body.get("subcode")
        }
        .and_then(Value::as_i64);
        let data = result.and_then(|value| value.get("data"));
        shape.data_shape = JsonShape::of(data);
        shape.data_code = data
            .and_then(|value| value.get("code"))
            .and_then(Value::as_i64);
        let list = data.and_then(|value| value.get(read.list_key));
        shape.list_shape = JsonShape::of(list);
        shape.raw_count = list.and_then(Value::as_array).map(Vec::len);
        shape.total_present = data.and_then(|value| value.get(read.total_key)).is_some();
        let continuation = data.and_then(|value| value.get(read.more_key));
        shape.continuation_type = match continuation {
            None => "missing",
            Some(Value::Bool(_)) => "bool",
            Some(Value::Number(_)) => "number",
            Some(Value::Null) => "null",
            Some(_) => "other",
        };
        shape.has_more = continuation.and_then(|value| {
            value.as_bool().or_else(|| match value.as_i64() {
                Some(0) => Some(false),
                Some(1) => Some(true),
                _ => None,
            })
        });
        shape
    }

    fn category(&self, sent: bool, parsed: bool) -> &'static str {
        let codes = [self.global_code, self.subrequest_code, self.data_code];
        if self
            .http_status
            .is_some_and(|status| matches!(status, 401 | 403))
            || codes
                .iter()
                .flatten()
                .any(|code| matches!(code, 1000 | 104_400 | 104_401))
        {
            "rejected"
        } else if self.http_status == Some(429)
            || codes.iter().flatten().any(|code| {
                matches!(
                    code,
                    2001 | 20_271 | 20_272 | 20_274 | 20_277 | 20_278 | 20_279 | 20_450 | 104_604
                )
            })
        {
            "risk_control"
        } else if self
            .http_status
            .is_some_and(|status| !(200..300).contains(&status))
        {
            "http"
        } else if !sent {
            "local_failure"
        } else if self.http_status.is_none() {
            "transport"
        } else if codes.iter().flatten().any(|code| *code != 0) {
            "upstream"
        } else if parsed {
            "accepted"
        } else if self.envelope_shape != JsonShape::Object {
            "malformed"
        } else if self.result_shape != JsonShape::Object
            || self.data_shape != JsonShape::Object
            || self.list_shape != JsonShape::Array
            || !self.total_present
        {
            "missing_field_or_shape"
        } else {
            "shape_or_pagination"
        }
    }

    // Only an explicitly successful wire envelope permits another independent
    // read after a parser failure. No retry or alternate profile is attempted.
    fn permits_next(&self, read: Read) -> bool {
        self.http_status
            .is_some_and(|status| (200..300).contains(&status))
            && self.global_code == Some(0)
            && if read.result_key.is_some() {
                self.subrequest_code == Some(0)
            } else {
                self.subrequest_code.is_none_or(|code| code == 0)
            }
            && self.data_code.is_none_or(|code| code == 0)
    }
}

struct OneRead<T> {
    transport: T,
    read: Read,
    sent: AtomicBool,
    observation: Mutex<WireObservation>,
}

impl<T> OneRead<T> {
    fn new(transport: T, read: Read) -> Self {
        Self {
            transport,
            read,
            sent: AtomicBool::new(false),
            observation: Mutex::new(WireObservation::default()),
        }
    }

    fn report(&self, counts: Option<(usize, u32)>) -> bool {
        let observation = self.observation.lock().expect("wire observation");
        let sent = self.sent.load(Ordering::SeqCst);
        let mut category = observation.category(sent, counts.is_some());
        if self.read.phase == FAVORITE.phase
            && category == "accepted"
            && observation.has_more == Some(true)
            && observation.raw_count == Some(0)
        {
            category = "pagination";
        }
        let (count, omitted) = counts.unzip();
        eprintln!(
            "{GATE} phase={} material_sufficient=true request_sent={sent} failure_category={category} parsed={} mapped_count={count:?} omitted_count={omitted:?} wire={observation:?}",
            self.read.phase,
            counts.is_some(),
        );
        observation.permits_next(self.read)
    }
}

impl<T: HttpTransport> HttpTransport for OneRead<T> {
    type Error = io::Error;

    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
        let (expected_method, expected_url) = if self.read.result_key.is_some() {
            (HttpMethod::Post, MUSICU)
        } else {
            (HttpMethod::Get, ALBUMS)
        };
        if request.method() != expected_method
            || request.url() != expected_url
            || self.sent.swap(true, Ordering::SeqCst)
        {
            return Err(io::Error::other("disposable read budget or route rejected"));
        }
        let response = self
            .transport
            .execute(request.follow_redirects(false))
            .await
            .map_err(|_| io::Error::other("disposable read transport failed"))?;
        *self.observation.lock().expect("wire observation") =
            WireObservation::from_response(self.read, &response);
        Ok(response)
    }
}

fn skipped(read: Read, reason: &'static str) {
    eprintln!(
        "{GATE} phase={} request_sent=false result=NOT_RUN reason={reason}",
        read.phase
    );
}

pub(super) async fn run_reads(transport: ReqwestTransport, credential: &Credential) {
    let secrets = credential.session_secrets();
    let encrypted = secrets
        .encrypted_uin()
        .is_some_and(|value| !value.trim().is_empty());
    eprintln!(
        "{GATE} phase=credential_preflight login_type={} music_id_present={} music_key_present={} encrypted_uin_present={encrypted} refresh_token_present={} refresh_key_present={} openid_present={} unionid_present={}",
        credential.login_type().value(),
        !credential.music_id().is_empty(),
        !credential.music_key().is_empty(),
        secrets.refresh_token().is_some(),
        secrets.refresh_key().is_some(),
        secrets.open_id().is_some(),
        secrets.union_id().is_some()
    );

    let client = |read| QqMusicClient::new(OneRead::new(transport.clone(), read));
    let account = client(ACCOUNT);
    let verified = account.verify_credential(credential).await.is_ok();
    if !account.transport().report(verified.then_some((0, 0))) || !verified {
        eprintln!("{GATE} phase=complete result=STOPPED reason=account_verification");
        return;
    }

    let owned = client(OWNED);
    let collection = owned.owned_playlists(credential).await;
    if !owned.transport().report(
        collection
            .as_ref()
            .ok()
            .map(|rows| (rows.playlists().len(), rows.omitted_playlist_count())),
    ) {
        eprintln!("{GATE} phase=complete result=STOPPED reason=owned_wire_not_accepted");
        return;
    }
    let liked_directory_present = collection
        .as_ref()
        .ok()
        .map(|rows| rows.playlists().iter().any(|row| row.directory_id() == 201));
    eprintln!("{GATE} phase=owned_mapping liked_directory_present={liked_directory_present:?}");

    if encrypted {
        let favorite = client(FAVORITE);
        let result = favorite.favorite_playlists_page(credential, 0, 100).await;
        if !favorite.transport().report(
            result
                .ok()
                .map(|page| (page.playlists().len(), page.omitted_playlist_count())),
        ) {
            eprintln!("{GATE} phase=complete result=STOPPED reason=favorite_wire_not_accepted");
            return;
        }
        let liked = client(LIKED);
        let result = liked.liked_songs_page(credential, 0, 20).await;
        if !liked.transport().report(
            result
                .ok()
                .map(|page| (page.tracks().len(), page.omitted_track_count())),
        ) {
            eprintln!("{GATE} phase=complete result=STOPPED reason=liked_wire_not_accepted");
            return;
        }
    } else {
        skipped(FAVORITE, "missing_material");
        skipped(LIKED, "missing_material");
    }

    let album = client(ALBUM);
    let result = album.favorite_albums(credential, 0, 20).await;
    if !album.transport().report(
        result
            .ok()
            .map(|page| (page.albums().len(), page.omitted_album_count())),
    ) {
        eprintln!("{GATE} phase=complete result=STOPPED reason=album_wire_not_accepted");
        return;
    }
    if encrypted {
        let artist = client(ARTIST);
        let result = artist.favorite_artists(credential, 0, 20).await;
        if !artist.transport().report(
            result
                .ok()
                .map(|page| (page.artists().len(), page.omitted_artist_count())),
        ) {
            eprintln!("{GATE} phase=complete result=STOPPED reason=artist_wire_not_accepted");
            return;
        }
    } else {
        skipped(ARTIST, "missing_material");
    }
    eprintln!("{GATE} phase=complete result=OBSERVED_READS_ONLY");
}

#[test]
fn wire_observation_keeps_only_codes_counts_and_shape() {
    let response = HttpResponse::new(
        200,
        br#"{
        "code":0,"music.musicasset.PlaylistFavRead":{"code":0,"data":{
            "v_list":[{"title":"secret-fixture-row"}],"total":1,"hasmore":false
        }},"private":"secret-fixture-body"
    }"#
        .to_vec(),
    );
    let observation = WireObservation::from_response(FAVORITE, &response);
    assert!(observation.permits_next(FAVORITE));
    assert_eq!(observation.category(true, false), "shape_or_pagination");
    assert_eq!(observation.raw_count, Some(1));
    assert_eq!(observation.continuation_type, "bool");
    assert!(!format!("{observation:?}").contains("secret-fixture"));
    let limited = WireObservation::from_response(FAVORITE, &HttpResponse::new(429, Vec::new()));
    assert!(!limited.permits_next(FAVORITE));
    assert_eq!(limited.category(true, false), "risk_control");
}

#[tokio::test]
async fn bounded_transport_blocks_wrong_route_redirects_and_second_request() {
    struct Fake;
    impl HttpTransport for Fake {
        type Error = std::convert::Infallible;
        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse, Self::Error> {
            assert!(!request.redirects_are_followed());
            Ok(HttpResponse::new(302, Vec::new()))
        }
    }
    let probe = OneRead::new(Fake, OWNED);
    assert!(probe.execute(HttpRequest::get(ALBUMS)).await.is_err());
    let response = probe
        .execute(HttpRequest::post(MUSICU))
        .await
        .expect("one send");
    assert_eq!(response.status(), 302);
    assert!(probe.execute(HttpRequest::post(MUSICU)).await.is_err());
    assert!(!probe.report(None));
}
