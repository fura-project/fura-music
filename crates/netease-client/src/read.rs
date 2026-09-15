use crate::catalog::{bounds, check_page, decode, id, text};
use crate::{Album, Error, NeteaseClient, Song, Transport};
use serde::Deserialize;
use serde_json::json;

const MAX_HOT_COMMENTS: usize = 100;
const MAX_RELATED_TRACKS: usize = 50;
const MAX_NEW_SONGS: usize = 200;

#[derive(Clone, Deserialize)]
pub struct Comment {
    #[serde(rename = "commentId")]
    pub id: u64,
    pub content: String,
    pub time: u64,
    #[serde(rename = "likedCount")]
    pub praise_count: u64,
    pub user: CommentUser,
}

#[derive(Clone, Deserialize)]
pub struct CommentUser {
    pub nickname: String,
    #[serde(default, rename = "avatarUrl")]
    pub avatar: Option<String>,
}

impl Comment {
    fn validate(&self) -> Result<(), Error> {
        id(self.id)?;
        text(&self.content)?;
        text(&self.user.nickname)?;
        if self.time == 0 {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }
}

pub struct CommentsPage {
    pub offset: u32,
    pub total: u32,
    pub more: bool,
    pub hot: Vec<Comment>,
    pub latest: Vec<Comment>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NewSongArea {
    All,
    Western,
    Japan,
    Korea,
}

impl NewSongArea {
    const fn protocol_value(self) -> u32 {
        match self {
            Self::All => 0,
            Self::Western => 96,
            Self::Japan => 8,
            Self::Korea => 16,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NewAlbumArea {
    Western,
    Korea,
    Japan,
}

impl NewAlbumArea {
    const fn protocol_value(self) -> &'static str {
        match self {
            Self::Western => "EA",
            Self::Korea => "KR",
            Self::Japan => "JP",
        }
    }
}

#[derive(Clone, Deserialize)]
pub struct NewAlbum {
    #[serde(flatten)]
    pub album: Album,
    #[serde(default, rename = "publishTime")]
    pub publish_time_millis: Option<u64>,
}

impl NewAlbum {
    fn validate(&self) -> Result<(), Error> {
        self.album.validate()?;
        if self.publish_time_millis == Some(0) {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }
}

impl<T: Transport> NeteaseClient<T> {
    /// One exact, bounded read-only comment page. Hot comments are surfaced
    /// only for offset zero; continuation applies to latest comments.
    ///
    /// # Errors
    /// Invalid identities/bounds, contradictory paging, malformed text,
    /// duplicates and upstream failures stop without partial success.
    pub async fn comments(
        &self,
        track: u64,
        offset: u32,
        size: u32,
    ) -> Result<CommentsPage, Error> {
        id(track)?;
        bounds(offset, size)?;
        let (value, _) = self
            .request(
                &format!("/api/v1/resource/comments/R_SO_4_{track}"),
                json!({"rid":track,"limit":size,"offset":offset,"beforeTime":0}),
                false,
                None,
            )
            .await?;
        let total: u32 = decode(
            value
                .get("total")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(
            value
                .get("more")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let latest: Vec<Comment> = decode(
            value
                .get("comments")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        check_page(latest.len(), offset, size, total, more)?;
        let hot: Vec<Comment> = if offset == 0 {
            decode(
                value
                    .get("hotComments")
                    .cloned()
                    .unwrap_or_else(|| json!([])),
            )?
        } else {
            Vec::new()
        };
        if hot.len() > MAX_HOT_COMMENTS {
            return Err(Error::ResponseBound);
        }
        validate_comments(&latest)?;
        validate_comments(&hot)?;
        Ok(CommentsPage {
            offset,
            total,
            more,
            hot,
            latest,
        })
    }

    /// One bounded anonymous related-Track batch for an exact seed.
    ///
    /// # Errors
    /// Invalid seeds, duplicate/seed rows, oversized data and upstream failures stop.
    pub async fn related_tracks(&self, seed: u64) -> Result<Vec<Song>, Error> {
        id(seed)?;
        let (value, _) = self
            .request(
                "/api/v1/discovery/simiSong",
                json!({"songid":seed,"limit":MAX_RELATED_TRACKS,"offset":0}),
                false,
                None,
            )
            .await?;
        let items: Vec<Song> = decode(
            value
                .get("songs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if items.len() > MAX_RELATED_TRACKS {
            return Err(Error::ResponseBound);
        }
        validate_songs(&items, Some(seed))?;
        Ok(items)
    }

    /// One bounded whole-response new-song category. The upstream operation
    /// has no pagination inputs, so this method invents no cursor.
    ///
    /// # Errors
    /// Malformed/duplicate/oversized rows and upstream failures stop.
    pub async fn new_songs(&self, area: NewSongArea) -> Result<Vec<Song>, Error> {
        let (value, _) = self
            .request(
                "/api/v1/discovery/new/songs",
                json!({"areaId":area.protocol_value(),"total":true}),
                false,
                None,
            )
            .await?;
        let items: Vec<Song> = decode(
            value
                .get("data")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if items.len() > MAX_NEW_SONGS {
            return Err(Error::ResponseBound);
        }
        validate_songs(&items, None)?;
        Ok(items)
    }

    /// One true offset page of new Album releases for a protocol-native area.
    ///
    /// # Errors
    /// Invalid bounds, contradictory pagination, duplicate Albums, malformed
    /// metadata and upstream failures stop.
    pub async fn new_albums(
        &self,
        area: NewAlbumArea,
        offset: u32,
        size: u32,
    ) -> Result<crate::Page<NewAlbum>, Error> {
        bounds(offset, size)?;
        let (value, _) = self
            .request(
                "/api/album/new",
                json!({"limit":size,"offset":offset,"total":true,"area":area.protocol_value()}),
                false,
                None,
            )
            .await?;
        let items: Vec<NewAlbum> = decode(
            value
                .get("albums")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let total: u32 = decode(
            value
                .get("total")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let len = u32::try_from(items.len()).map_err(|_| Error::ResponseBound)?;
        let more = offset.checked_add(len).ok_or(Error::ResponseBound)? < total;
        check_page(items.len(), offset, size, total, more)?;
        let mut seen = std::collections::HashSet::new();
        for item in &items {
            item.validate()?;
            if !seen.insert(item.album.id) {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        Ok(crate::Page {
            items,
            offset,
            total,
            more,
        })
    }
}

fn validate_comments(items: &[Comment]) -> Result<(), Error> {
    let mut seen = std::collections::HashSet::new();
    for item in items {
        item.validate()?;
        if !seen.insert(item.id) {
            return Err(Error::ResponseShapeMismatch);
        }
    }
    Ok(())
}

fn validate_songs(items: &[Song], excluded: Option<u64>) -> Result<(), Error> {
    let mut seen = std::collections::HashSet::new();
    for item in items {
        item.validate()?;
        if Some(item.id) == excluded || !seen.insert(item.id) {
            return Err(Error::ResponseShapeMismatch);
        }
    }
    Ok(())
}
