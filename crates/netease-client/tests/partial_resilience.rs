use netease_client::{Error, NeteaseClient, Request, Response, Transport};
use serde_json::{Value, json};
use std::sync::Mutex;

struct SequenceTransport {
    responses: Mutex<Vec<Value>>,
}

impl Transport for SequenceTransport {
    async fn send(&self, _request: Request) -> Result<Response, Error> {
        let value = self.responses.lock().unwrap().remove(0);
        Ok(Response {
            status: 200,
            body: serde_json::to_vec(&value).unwrap(),
            set_cookies: Vec::new(),
        })
    }
}

fn song(id: u64, name: Option<&str>) -> Value {
    let mut value = json!({
        "id": id,
        "name": name.unwrap_or_default(),
        "dt": 180_000,
        "ar": [{"id": 9, "name": "Artist"}],
        "al": {"id": 7, "name": "Album", "picUrl": "https://p1.music.126.net/a.jpg"}
    });
    if name.is_none() {
        value.as_object_mut().unwrap().remove("name");
    }
    value
}

#[tokio::test]
async fn playlist_good_bad_good_keeps_raw_cursor_and_counts_omission() {
    let client = NeteaseClient::new(SequenceTransport {
        responses: Mutex::new(vec![
            json!({
                "code": 200,
                "playlist": {
                    "id": 99,
                    "name": "Fixture",
                    "trackCount": 3,
                    "trackIds": [{"id": 11}, {"id": 12}, {"id": 13}]
                }
            }),
            json!({"code": 200, "songs": [song(11, Some("A")), song(12, None), song(13, Some("B"))]}),
        ]),
    });

    let page = client.playlist_page(99, 0, 3).await.unwrap();
    assert_eq!(
        page.tracks.iter().map(|track| track.id).collect::<Vec<_>>(),
        [11, 13]
    );
    assert_eq!(
        (page.offset, page.next, page.total, page.omitted),
        (0, 3, 3, 1)
    );
}

#[tokio::test]
async fn singleton_song_detail_keeps_canonical_row_strict() {
    let client = NeteaseClient::new(SequenceTransport {
        responses: Mutex::new(vec![json!({"code": 200, "songs": [song(12, None)]})]),
    });
    assert!(matches!(
        client.songs(&[12]).await,
        Err(Error::ResponseShapeMismatch)
    ));
}
