use crate::{Credential, Error, NeteaseClient, Transport};
use serde::Deserialize;
use serde_json::{Value, json};

/// Raw endpoint model, never a Domain or Bridge identity.
#[derive(Clone, Deserialize)]
pub struct Artist {
    pub id: u64,
    pub name: String,
    #[serde(default, rename = "picUrl")]
    pub artwork: Option<String>,
}
#[derive(Clone, Deserialize)]
pub struct Album {
    pub id: u64,
    pub name: String,
    #[serde(default, rename = "picUrl")]
    pub artwork: Option<String>,
    #[serde(default)]
    pub artists: Vec<Artist>,
    #[serde(default)]
    pub description: Option<String>,
}
#[derive(Clone, Deserialize)]
pub struct Song {
    pub id: u64,
    pub name: String,
    #[serde(alias = "ar")]
    pub artists: Vec<Artist>,
    #[serde(alias = "al")]
    pub album: Album,
    #[serde(alias = "dt")]
    pub duration: u32,
}
#[derive(Clone, Deserialize)]
pub struct Playlist {
    pub id: u64,
    pub name: String,
    #[serde(default, rename = "coverImgUrl", alias = "picUrl")]
    pub artwork: Option<String>,
    #[serde(rename = "trackCount")]
    pub track_count: u32,
}
pub struct Page<T> {
    pub items: Vec<T>,
    pub offset: u32,
    pub total: u32,
    pub more: bool,
}
#[derive(Clone, Copy)]
pub enum SearchKind {
    Tracks,
    Albums,
    Artists,
    Playlists,
}
impl SearchKind {
    const fn fields(self) -> (u32, &'static str, &'static str) {
        match self {
            Self::Tracks => (1, "songs", "songCount"),
            Self::Albums => (10, "albums", "albumCount"),
            Self::Artists => (100, "artists", "artistCount"),
            Self::Playlists => (1000, "playlists", "playlistCount"),
        }
    }
}
pub(crate) fn bounds(offset: u32, size: u32) -> Result<(), Error> {
    if size == 0 || size > 100 || offset > 100_000 || offset.checked_add(size).is_none() {
        Err(Error::InputBound)
    } else {
        Ok(())
    }
}
pub(crate) fn id(id: u64) -> Result<(), Error> {
    if id == 0 || id > 9_007_199_254_740_991 {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}
pub(crate) fn text(value: &str) -> Result<(), Error> {
    if value.trim().is_empty() || value.len() > 4096 {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}
/// # Errors
/// Rejects non-HTTPS, userinfo, fragment, missing host or oversized artwork.
pub fn artwork(value: Option<String>) -> Result<Option<String>, Error> {
    value
        .map(|v| {
            if v.len() > 4096 {
                return Err(Error::ResponseShapeMismatch);
            }
            let mut uri = url::Url::parse(&v).map_err(|_| Error::ResponseShapeMismatch)?;
            // NetEase catalog returns its own CDN over HTTP as well; same-host HTTPS only.
            if uri.scheme() == "http"
                && uri
                    .host_str()
                    .is_some_and(|h| h.ends_with(".music.126.net"))
            {
                uri.set_scheme("https")
                    .map_err(|()| Error::ResponseShapeMismatch)?;
            }
            if uri.scheme() != "https"
                || uri.host_str().is_none()
                || !uri.username().is_empty()
                || uri.password().is_some()
                || uri.fragment().is_some()
            {
                return Err(Error::ResponseShapeMismatch);
            }
            Ok(uri.into())
        })
        .transpose()
}
impl Artist {
    pub(crate) fn validate(&self) -> Result<(), Error> {
        id(self.id)?;
        text(&self.name)?;
        artwork(self.artwork.clone())?;
        Ok(())
    }
}
impl Album {
    pub(crate) fn validate(&self) -> Result<(), Error> {
        id(self.id)?;
        text(&self.name)?;
        artwork(self.artwork.clone())?;
        if self.artists.len() > 32
            || self
                .description
                .as_ref()
                .is_some_and(|d| d.len() > 128 * 1024)
        {
            return Err(Error::ResponseBound);
        }
        for a in &self.artists {
            text(&a.name)?;
            if a.id > 0 {
                a.validate()?;
            }
        }
        Ok(())
    }
}
impl Song {
    pub(crate) fn validate(&self) -> Result<(), Error> {
        id(self.id)?;
        text(&self.name)?;
        self.album.validate()?;
        if self.artists.len() > 32 || self.duration > 86_400_000 {
            return Err(Error::ResponseBound);
        }
        for a in &self.artists {
            text(&a.name)?;
            if a.id > 0 {
                a.validate()?;
            }
        }
        Ok(())
    }
}
impl Playlist {
    pub(crate) fn validate(&self) -> Result<(), Error> {
        id(self.id)?;
        text(&self.name)?;
        artwork(self.artwork.clone())?;
        Ok(())
    }
}
pub(crate) fn decode<T: serde::de::DeserializeOwned>(v: Value) -> Result<T, Error> {
    serde_json::from_value(v).map_err(|_| Error::ResponseShapeMismatch)
}
impl<T: Transport> NeteaseClient<T> {
    async fn search(
        &self,
        q: &str,
        kind: SearchKind,
        offset: u32,
        size: u32,
    ) -> Result<Page<Value>, Error> {
        bounds(offset, size)?;
        if size > 30 || q.trim().is_empty() || q.len() > 256 {
            return Err(Error::InputBound);
        }
        let (kind, key, count) = kind.fields();
        let (v, _) = self
            .request(
                "/api/search/get",
                json!({"s":q,"type":kind,"offset":offset,"limit":size,"total":true}),
                false,
                None,
            )
            .await?;
        let result = v.get("result").ok_or(Error::ResponseShapeMismatch)?;
        let total = decode::<u32>(
            result
                .get(count)
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let rows = match result.get(key) {
            Some(Value::Array(rows)) => rows.clone(),
            None if total == 0 => vec![],
            _ => return Err(Error::ResponseShapeMismatch),
        };
        if rows.len() > size as usize
            || offset.saturating_add(u32::try_from(rows.len()).map_err(|_| Error::ResponseBound)?)
                > total
                && !rows.is_empty()
        {
            return Err(Error::ResponseShapeMismatch);
        }
        let more = offset
            .saturating_add(u32::try_from(rows.len()).map_err(|_| Error::ResponseBound)?)
            < total;
        if more && rows.is_empty() {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(Page {
            items: rows,
            offset,
            total,
            more,
        })
    }
}
macro_rules! search_method {
    ($method:ident,$kind:ident,$model:ty) => {
        impl<T: Transport> NeteaseClient<T> {
            /// One bounded anonymous search page.
            ///
            /// # Errors
            /// Invalid input, protocol shape, network, authentication or upstream STOP.
            pub async fn $method(
                &self,
                q: &str,
                offset: u32,
                size: u32,
            ) -> Result<Page<$model>, Error> {
                let p = self.search(q, SearchKind::$kind, offset, size).await?;
                let items = p
                    .items
                    .into_iter()
                    .map(|v| {
                        let item: $model = decode(v)?;
                        item.validate()?;
                        Ok(item)
                    })
                    .collect::<Result<Vec<_>, Error>>()?;
                Ok(Page {
                    items,
                    offset: p.offset,
                    total: p.total,
                    more: p.more,
                })
            }
        }
    };
}
search_method!(search_tracks, Tracks, Song);
search_method!(search_albums, Albums, Album);
search_method!(search_artists, Artists, Artist);
search_method!(search_playlists, Playlists, Playlist);

/// A bounded playlist window; unavailable IDs consume the raw cursor.
pub struct PlaylistPage {
    pub playlist: Playlist,
    pub tracks: Vec<Song>,
    pub offset: u32,
    pub next: u32,
    pub total: u32,
    pub omitted: u32,
}
/// One validated identity window, allowing the Provider to check its session
/// generation before issuing the separate song-detail request.
pub struct PlaylistSelection {
    playlist: Playlist,
    selected: Vec<u64>,
    offset: u32,
    next: u32,
    total: u32,
}
impl PlaylistSelection {
    #[must_use]
    pub fn ids(&self) -> &[u64] {
        &self.selected
    }
    /// # Errors
    /// Rejects duplicate, malformed or unrelated song details. Missing IDs remain omissions.
    pub fn with_songs(self, songs: Vec<Song>) -> Result<PlaylistPage, Error> {
        let mut by_id = std::collections::HashMap::new();
        for song in songs {
            song.validate()?;
            if !self.selected.contains(&song.id) || by_id.insert(song.id, song).is_some() {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        let tracks: Vec<_> = self
            .selected
            .iter()
            .filter_map(|id| by_id.remove(id))
            .collect();
        let omitted =
            u32::try_from(self.selected.len() - tracks.len()).map_err(|_| Error::ResponseBound)?;
        Ok(PlaylistPage {
            playlist: self.playlist,
            tracks,
            offset: self.offset,
            next: self.next,
            total: self.total,
            omitted,
        })
    }
}
pub struct AlbumContent {
    pub album: Album,
    pub songs: Vec<Song>,
}
impl<T: Transport> NeteaseClient<T> {
    /// # Errors
    /// Rejects invalid/duplicate IDs, oversized responses, unrelated returned IDs or upstream failures.
    pub async fn songs(&self, ids: &[u64]) -> Result<Vec<Song>, Error> {
        self.songs_with_cookie(ids, None).await
    }
    /// # Errors
    /// Applies the same exact-ID and response bounds as anonymous song details.
    pub async fn authenticated_songs(
        &self,
        credential: &Credential,
        ids: &[u64],
    ) -> Result<Vec<Song>, Error> {
        self.songs_with_cookie(ids, Some(&credential.cookie()))
            .await
    }
    async fn songs_with_cookie(
        &self,
        ids: &[u64],
        cookie: Option<&str>,
    ) -> Result<Vec<Song>, Error> {
        if ids.is_empty() || ids.len() > 100 {
            return Err(Error::InputBound);
        }
        let unique: std::collections::HashSet<_> = ids.iter().copied().collect();
        if unique.len() != ids.len() {
            return Err(Error::InputBound);
        }
        for value in ids {
            id(*value)?;
        }
        let c = serde_json::to_string(&ids.iter().map(|id| json!({"id":id})).collect::<Vec<_>>())
            .map_err(|_| Error::InputBound)?;
        let (v, _) = self
            .request("/api/v3/song/detail", json!({"c":c}), false, cookie)
            .await?;
        let songs: Vec<Song> = decode(
            v.get("songs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if songs.len() > ids.len() {
            return Err(Error::ResponseBound);
        }
        let mut seen = std::collections::HashSet::new();
        for s in &songs {
            s.validate()?;
            if !unique.contains(&s.id) || !seen.insert(s.id) {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        Ok(songs)
    }
    /// # Errors
    /// A playlist exceeding 1,000 identity entries stops instead of being silently truncated.
    /// At most two serial requests retrieve one requested window, never the complete Track list.
    pub async fn playlist_page(
        &self,
        playlist: u64,
        offset: u32,
        size: u32,
    ) -> Result<PlaylistPage, Error> {
        let selection = self
            .playlist_selection(playlist, offset, size, None)
            .await?;
        let songs = if selection.ids().is_empty() {
            vec![]
        } else {
            self.songs(selection.ids()).await?
        };
        selection.with_songs(songs)
    }
    /// # Errors
    /// One authenticated metadata request; the caller controls subsequent detail requests.
    pub async fn authenticated_playlist_selection(
        &self,
        credential: &Credential,
        playlist: u64,
        offset: u32,
        size: u32,
    ) -> Result<PlaylistSelection, Error> {
        self.playlist_selection(playlist, offset, size, Some(&credential.cookie()))
            .await
    }
    async fn playlist_selection(
        &self,
        playlist: u64,
        offset: u32,
        size: u32,
        cookie: Option<&str>,
    ) -> Result<PlaylistSelection, Error> {
        id(playlist)?;
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/v6/playlist/detail",
                json!({"id":playlist,"n":100,"s":0}),
                false,
                cookie,
            )
            .await?;
        let p = v.get("playlist").ok_or(Error::ResponseShapeMismatch)?;
        if p.get("id").and_then(Value::as_u64) != Some(playlist) {
            return Err(Error::ResponseShapeMismatch);
        }
        let total: u32 = decode(
            p.get("trackCount")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let ids = p
            .get("trackIds")
            .and_then(Value::as_array)
            .ok_or(Error::ResponseShapeMismatch)?;
        if total > 1000 || ids.len() > 1000 {
            return Err(Error::ResponseBound);
        }
        if ids.len() != total as usize {
            return Err(Error::ResponseShapeMismatch);
        }
        let mut selected = Vec::new();
        for entry in ids.iter().skip(offset as usize).take(size as usize) {
            let value = entry
                .get("id")
                .and_then(Value::as_u64)
                .ok_or(Error::ResponseShapeMismatch)?;
            id(value)?;
            selected.push(value);
        }
        let next = offset
            .checked_add(u32::try_from(selected.len()).map_err(|_| Error::ResponseBound)?)
            .ok_or(Error::InputBound)?;
        if selected
            .iter()
            .collect::<std::collections::HashSet<_>>()
            .len()
            != selected.len()
        {
            return Err(Error::ResponseShapeMismatch);
        }
        let playlist: Playlist = decode(p.clone())?;
        playlist.validate()?;
        Ok(PlaylistSelection {
            playlist,
            selected,
            offset,
            next,
            total,
        })
    }
    /// # Errors
    /// Rejects a mismatched Album and whole responses above 1,000 Tracks; never hides a drain loop.
    pub async fn album(&self, album: u64) -> Result<AlbumContent, Error> {
        id(album)?;
        let (v, _) = self
            .request(&format!("/api/v1/album/{album}"), json!({}), false, None)
            .await?;
        let a: Album = decode(
            v.get("album")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        a.validate()?;
        if a.id != album {
            return Err(Error::ResponseShapeMismatch);
        }
        let songs: Vec<Song> = decode(
            v.get("songs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if songs.len() > 1000 {
            return Err(Error::ResponseBound);
        }
        for song in &songs {
            song.validate()?;
            if song.album.id != album {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        Ok(AlbumContent { album: a, songs })
    }
    /// # Errors
    /// Returns input, pagination, decoding or upstream STOP failures for one public page.
    pub async fn artist_tracks(
        &self,
        artist: u64,
        offset: u32,
        size: u32,
    ) -> Result<Page<Song>, Error> {
        id(artist)?;
        bounds(offset, size)?;
        let (v,_)=self.request("/api/v1/artist/songs",json!({"id":artist,"private_cloud":false,"work_type":1,"order":"hot","offset":offset,"limit":size}),false,None).await?;
        let items: Vec<Song> = decode(
            v.get("songs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let total: u32 = decode(
            v.get("total")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(v.get("more").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        check_page(items.len(), offset, size, total, more)?;
        for s in &items {
            s.validate()?;
        }
        Ok(Page {
            items,
            offset,
            total,
            more,
        })
    }
    /// # Errors
    /// Returns input, pagination, decoding or upstream STOP failures for one public page.
    pub async fn artist_albums(
        &self,
        artist: u64,
        offset: u32,
        size: u32,
    ) -> Result<Page<Album>, Error> {
        id(artist)?;
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                &format!("/api/artist/albums/{artist}"),
                json!({"offset":offset,"limit":size,"total":true}),
                false,
                None,
            )
            .await?;
        let a = v.get("artist").ok_or(Error::ResponseShapeMismatch)?;
        if a.get("id").and_then(Value::as_u64) != Some(artist) {
            return Err(Error::ResponseShapeMismatch);
        }
        let total: u32 = decode(
            a.get("albumSize")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(v.get("more").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        let items: Vec<Album> = decode(
            v.get("hotAlbums")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        check_page(items.len(), offset, size, total, more)?;
        for a in &items {
            a.validate()?;
        }
        Ok(Page {
            items,
            offset,
            total,
            more,
        })
    }
    /// # Errors
    /// Rejects missing/oversized ranking lists or malformed summary fields.
    pub async fn rankings(&self) -> Result<Vec<Playlist>, Error> {
        let (v, _) = self.request("/api/toplist", json!({}), false, None).await?;
        let items: Vec<Playlist> =
            decode(v.get("list").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if items.len() > 100 {
            return Err(Error::ResponseBound);
        }
        for p in &items {
            p.validate()?;
        }
        Ok(items)
    }
    /// One bounded, unpaged public recommendation sample.
    /// # Errors
    /// Rejects invalid bounds, malformed or oversized output and upstream failures.
    pub async fn recommendations(&self, size: u32) -> Result<Vec<Playlist>, Error> {
        bounds(0, size)?;
        let (v, _) = self
            .request(
                "/api/personalized/playlist",
                json!({"limit":size,"total":true,"n":size}),
                false,
                None,
            )
            .await?;
        let items: Vec<Playlist> = decode(
            v.get("result")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if items.len() > size as usize {
            return Err(Error::ResponseBound);
        }
        for p in &items {
            p.validate()?;
        }
        Ok(items)
    }
}
pub(crate) fn check_page(
    len: usize,
    offset: u32,
    size: u32,
    total: u32,
    more: bool,
) -> Result<(), Error> {
    let next = offset
        .checked_add(u32::try_from(len).map_err(|_| Error::ResponseBound)?)
        .ok_or(Error::ResponseBound)?;
    if len > size as usize
        || (more && (len == 0 || next >= total))
        || (!more && next < total)
        || (next > total && len > 0)
    {
        Err(Error::ResponseShapeMismatch)
    } else {
        Ok(())
    }
}
