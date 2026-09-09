use crate::catalog::{artwork, decode, id, text};
use crate::{Artist, Error, NeteaseClient, Transport};
use serde::Deserialize;
use serde_json::json;

const REQUESTED_RESOLUTION: u32 = 1080;

pub struct MusicVideo {
    pub id: u64,
    pub title: String,
    pub artist_names: Vec<String>,
    pub artwork: Option<String>,
    pub duration_millis: u32,
    pub source: MusicVideoSource,
}

pub struct MusicVideoSource {
    uri: String,
    pub resolution: u32,
}

impl MusicVideoSource {
    #[must_use]
    pub fn uri(&self) -> &str {
        &self.uri
    }
}

impl std::fmt::Debug for MusicVideoSource {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("NetEaseMusicVideoSource")
            .field("uri", &"[REDACTED]")
            .field("resolution", &self.resolution)
            .finish()
    }
}

#[derive(Deserialize)]
struct Detail {
    id: u64,
    name: String,
    #[serde(default, rename = "artistName")]
    artist_name: String,
    #[serde(default)]
    artists: Vec<Artist>,
    #[serde(default)]
    cover: Option<String>,
    duration: u32,
}

#[derive(Deserialize)]
struct Source {
    id: u64,
    code: i64,
    url: Option<String>,
    #[serde(rename = "r")]
    resolution: u32,
}

impl<T: Transport> NeteaseClient<T> {
    /// Resolves the exact 0/1 MV association carried by one Track detail. It
    /// performs no video search and never downloads the returned media body.
    ///
    /// # Errors
    /// Missing Track details, malformed associations/metadata/sources,
    /// unavailable sources and upstream failures remain distinct STOP results.
    pub async fn music_video(&self, track: u64) -> Result<Option<MusicVideo>, Error> {
        id(track)?;
        let songs = self.songs(&[track]).await?;
        let song = songs.first().ok_or(Error::TrackUnavailable)?;
        if song.mv_id == 0 {
            return Ok(None);
        }
        let mv = song.mv_id;
        let (detail_value, _) = self
            .request("/api/v1/mv/detail", json!({"id":mv}), false, None)
            .await?;
        let detail: Detail = decode(
            detail_value
                .get("data")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        validate_detail(&detail, mv)?;

        let (source_value, _) = self
            .request(
                "/api/song/enhance/play/mv/url",
                json!({"id":mv,"r":REQUESTED_RESOLUTION}),
                false,
                None,
            )
            .await?;
        let source: Source = decode(
            source_value
                .get("data")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let source = validate_source(source, mv)?;
        let artist_names = if detail.artists.is_empty() {
            vec![detail.artist_name]
        } else {
            detail
                .artists
                .into_iter()
                .map(|artist| artist.name)
                .collect()
        };
        Ok(Some(MusicVideo {
            id: detail.id,
            title: detail.name,
            artist_names,
            artwork: artwork(detail.cover)?,
            duration_millis: detail.duration,
            source,
        }))
    }
}

fn validate_detail(detail: &Detail, expected: u64) -> Result<(), Error> {
    if detail.id != expected {
        return Err(Error::ResponseShapeMismatch);
    }
    id(detail.id)?;
    text(&detail.name)?;
    if detail.duration == 0 || detail.duration > 86_400_000 || detail.artists.len() > 32 {
        return Err(Error::ResponseBound);
    }
    if detail.artists.is_empty() {
        text(&detail.artist_name)?;
    } else {
        for artist in &detail.artists {
            text(&artist.name)?;
            if artist.id > 0 {
                artist.validate()?;
            }
        }
    }
    artwork(detail.cover.clone())?;
    Ok(())
}

fn validate_source(source: Source, expected: u64) -> Result<MusicVideoSource, Error> {
    if source.id != expected {
        return Err(Error::ResponseShapeMismatch);
    }
    if source.code != 200 {
        return Err(Error::UpstreamUnknown);
    }
    if !matches!(source.resolution, 240 | 360 | 480 | 720 | 1080) {
        return Err(Error::ProtocolUnavailable);
    }
    let mut uri = source.url.ok_or(Error::TrackUnavailable)?;
    if uri.len() > 8192 {
        return Err(Error::ResponseBound);
    }
    let mut parsed = url::Url::parse(&uri).map_err(|_| Error::ResponseShapeMismatch)?;
    if parsed.scheme() == "http"
        && parsed
            .host_str()
            .is_some_and(|host| host.ends_with(".126.net"))
    {
        parsed
            .set_scheme("https")
            .map_err(|()| Error::ResponseShapeMismatch)?;
        uri = parsed.to_string();
    }
    if parsed.scheme() != "https"
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.fragment().is_some()
    {
        return Err(Error::ResponseShapeMismatch);
    }
    Ok(MusicVideoSource {
        uri,
        resolution: source.resolution,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sources_are_https_bounded_and_redacted() {
        let source = validate_source(
            Source {
                id: 7,
                code: 200,
                url: Some("http://vod.example.126.net/source".into()),
                resolution: 720,
            },
            7,
        )
        .unwrap();
        assert!(source.uri().starts_with("https://"));
        assert!(!format!("{source:?}").contains("example.126.net"));
        for uri in [
            "http://untrusted.invalid/source",
            "file:///tmp/source",
            "https://user:pass@example.invalid/source",
            "https://example.invalid/source#secret",
        ] {
            assert!(
                validate_source(
                    Source {
                        id: 7,
                        code: 200,
                        url: Some(uri.into()),
                        resolution: 720,
                    },
                    7,
                )
                .is_err()
            );
        }
    }
}
