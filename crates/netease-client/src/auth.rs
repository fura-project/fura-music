use crate::catalog::{bounds, decode, id, text};
use crate::{Error, NeteaseClient, Playlist, Song, Transport};
use serde::Deserialize;
use serde_json::{Value, json};

#[derive(Clone, Eq, PartialEq)]
pub struct Credential {
    version: u8,
    provider: String,
    music_u: String,
    csrf: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StoredCredential {
    version: u8,
    provider: String,
    music_u: String,
    csrf: String,
}
impl std::fmt::Debug for Credential {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NetEaseCredential([REDACTED])")
    }
}
impl Credential {
    fn validate(&self) -> Result<(), Error> {
        if self.version != 1
            || self.provider != "netease-cloud-music"
            || self.music_u.is_empty()
            || self.music_u.len() > 4096
            || self.csrf.len() > 256
            || !self
                .music_u
                .bytes()
                .chain(self.csrf.bytes())
                .all(|b| b.is_ascii_graphic() && !matches!(b, b';' | b',' | b'"' | b'\\'))
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(())
    }
    /// Opaque secure-storage bytes, never a presentation or logging value.
    /// # Errors
    /// Rejects invalid internal session invariants.
    pub fn export(&self) -> Result<Vec<u8>, Error> {
        self.validate()?;
        serde_json::to_vec(&json!({"version":self.version,"provider":self.provider,"music_u":self.music_u,"csrf":self.csrf})).map_err(|_|Error::ResponseShapeMismatch)
    }
    /// Imports only a candidate; the Provider must verify it before authentication.
    /// # Errors
    /// Rejects oversized, foreign, future-version, malformed or invalid credentials.
    pub fn import(bytes: &[u8]) -> Result<Self, Error> {
        if bytes.len() > 8192 {
            return Err(Error::ResponseBound);
        }
        let stored: StoredCredential =
            serde_json::from_slice(bytes).map_err(|_| Error::ResponseShapeMismatch)?;
        let value = Self {
            version: stored.version,
            provider: stored.provider,
            music_u: stored.music_u,
            csrf: stored.csrf,
        };
        value.validate()?;
        Ok(value)
    }
    pub(crate) fn cookie(&self) -> String {
        format!("MUSIC_U={}; __csrf={}", self.music_u, self.csrf)
    }
    fn from_headers(headers: &[String]) -> Result<Self, Error> {
        if headers.len() > 32 {
            return Err(Error::ResponseBound);
        }
        let mut music_u = None;
        let mut csrf = None;
        for header in headers {
            if header.len() > 8192 {
                return Err(Error::ResponseBound);
            }
            let pair = header
                .split(';')
                .next()
                .ok_or(Error::ResponseShapeMismatch)?;
            if let Some((name, value)) = pair.split_once('=') {
                let target = match name {
                    "MUSIC_U" => &mut music_u,
                    "__csrf" => &mut csrf,
                    _ => continue,
                };
                if target.replace(value.to_owned()).is_some() {
                    return Err(Error::ResponseShapeMismatch);
                }
            }
        }
        let value = Self {
            version: 1,
            provider: "netease-cloud-music".into(),
            music_u: music_u.ok_or(Error::ResponseShapeMismatch)?,
            csrf: csrf.unwrap_or_default(),
        };
        value.validate()?;
        Ok(value)
    }
}
/// Raw key stays inside Rust; only its locally encoded image is presented.
pub struct QrKey {
    key: String,
}
impl std::fmt::Debug for QrKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("NetEaseQrKey([REDACTED])")
    }
}
impl QrKey {
    /// # Errors
    /// Returns a coarse encoding error; the QR key never appears in diagnostics.
    pub fn image_png(&self) -> Result<Vec<u8>, Error> {
        let mut url = url::Url::parse("https://music.163.com/login")
            .map_err(|_| Error::ProtocolUnavailable)?;
        url.query_pairs_mut().append_pair("codekey", &self.key);
        let code = qrcode::QrCode::new(url.as_str()).map_err(|_| Error::ProtocolUnavailable)?;
        let width = code.width();
        let pixels = (width + 8) * 4;
        let mut image = vec![255; pixels * pixels];
        for y in 0..width {
            for x in 0..width {
                if code[(x, y)] == qrcode::Color::Dark {
                    for dy in 0..4 {
                        for dx in 0..4 {
                            image[((y + 4) * 4 + dy) * pixels + (x + 4) * 4 + dx] = 0;
                        }
                    }
                }
            }
        }
        let mut output = Vec::new();
        let size = u32::try_from(pixels).map_err(|_| Error::ResponseBound)?;
        {
            let mut encoder = png::Encoder::new(&mut output, size, size);
            encoder.set_color(png::ColorType::Grayscale);
            encoder.set_depth(png::BitDepth::Eight);
            let mut writer = encoder
                .write_header()
                .map_err(|_| Error::ProtocolUnavailable)?;
            writer
                .write_image_data(&image)
                .map_err(|_| Error::ProtocolUnavailable)?;
        }
        Ok(output)
    }
}
pub enum QrPoll {
    Waiting,
    Scanned,
    Expired,
    Confirmed(Credential),
}
impl std::fmt::Debug for QrPoll {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Waiting => "Waiting",
            Self::Scanned => "Scanned",
            Self::Expired => "Expired",
            Self::Confirmed(_) => "Confirmed([REDACTED])",
        })
    }
}
pub struct Account {
    pub id: u64,
    pub name: String,
    pub avatar: Option<String>,
}
#[derive(Deserialize)]
pub struct UserPlaylist {
    #[serde(flatten)]
    pub playlist: Playlist,
    pub creator: Creator,
    #[serde(rename = "specialType", default)]
    pub special_type: u32,
}
#[derive(Deserialize)]
pub struct Creator {
    #[serde(rename = "userId")]
    pub id: u64,
}
pub struct UserPlaylistPage {
    pub items: Vec<UserPlaylist>,
    pub more: bool,
}
impl<T: Transport> NeteaseClient<T> {
    /// Creates one QR challenge only after an explicit caller action.
    /// # Errors
    /// Invalid/missing keys and all upstream failures stop.
    pub async fn qr_key(&self) -> Result<QrKey, Error> {
        let (v, _) = self
            .request("/api/login/qrcode/unikey", json!({"type":3}), false, None)
            .await?;
        let key = v
            .get("unikey")
            .and_then(Value::as_str)
            .ok_or(Error::ResponseShapeMismatch)?;
        if key.is_empty()
            || key.len() > 256
            || !key
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
        {
            return Err(Error::ResponseShapeMismatch);
        }
        Ok(QrKey { key: key.into() })
    }
    /// Exactly one explicit poll; no background loop or automatic approval.
    /// # Errors
    /// Unknown states or confirmed responses without a valid cookie stop.
    pub async fn qr_poll(&self, key: &QrKey) -> Result<QrPoll, Error> {
        let (v, cookies) = self
            .raw_request(
                "/api/login/qrcode/client/login",
                json!({"type":3,"key":key.key}),
                false,
                None,
            )
            .await?;
        match v
            .get("code")
            .and_then(Value::as_i64)
            .ok_or(Error::ResponseShapeMismatch)?
        {
            800 => Ok(QrPoll::Expired),
            801 => Ok(QrPoll::Waiting),
            802 => Ok(QrPoll::Scanned),
            803 => Ok(QrPoll::Confirmed(Credential::from_headers(&cookies)?)),
            _ => Err(Error::UpstreamUnknown),
        }
    }
    /// # Errors
    /// Null account/profile or explicit unauthenticated responses reject the candidate; unknown failures retain it.
    pub async fn account(&self, credential: &Credential) -> Result<Account, Error> {
        let (v, _) = self
            .request(
                "/api/w/nuser/account/get",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        if v.get("account") == Some(&Value::Null) || v.get("profile") == Some(&Value::Null) {
            return Err(Error::CredentialRejected);
        }
        let aid = v
            .pointer("/account/id")
            .and_then(Value::as_u64)
            .ok_or(Error::ResponseShapeMismatch)?;
        if v.pointer("/profile/userId").and_then(Value::as_u64) != Some(aid) {
            return Err(Error::ResponseShapeMismatch);
        }
        id(aid)?;
        let name = v
            .pointer("/profile/nickname")
            .and_then(Value::as_str)
            .ok_or(Error::ResponseShapeMismatch)?;
        text(name)?;
        let avatar = v
            .pointer("/profile/avatarUrl")
            .filter(|v| !v.is_null())
            .map(|v| {
                v.as_str()
                    .map(str::to_owned)
                    .ok_or(Error::ResponseShapeMismatch)
            })
            .transpose()?;
        Ok(Account {
            id: aid,
            name: name.into(),
            avatar: crate::artwork(avatar)?,
        })
    }
    /// # Errors
    /// One authenticated page; invalid identity, page bounds or response shape stop.
    pub async fn user_playlists(
        &self,
        credential: &Credential,
        user: u64,
        offset: u32,
        size: u32,
    ) -> Result<UserPlaylistPage, Error> {
        id(user)?;
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/user/playlist",
                json!({"uid":user,"offset":offset,"limit":size,"includeVideo":false}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<UserPlaylist> = decode(
            v.get("playlist")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(v.get("more").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if items.len() > size as usize || (more && items.is_empty()) {
            return Err(Error::ResponseShapeMismatch);
        }
        for p in &items {
            p.playlist.validate()?;
            id(p.creator.id)?;
        }
        Ok(UserPlaylistPage { items, more })
    }
    /// Unordered liked identities; never pretend to be recent-play order.
    /// # Errors
    /// Rejects lists over 1,000 IDs, duplicates and invalid identities.
    pub async fn liked_ids(&self, credential: &Credential, user: u64) -> Result<Vec<u64>, Error> {
        id(user)?;
        let (v, _) = self
            .request(
                "/api/song/like/get",
                json!({"uid":user}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let ids: Vec<u64> = decode(v.get("ids").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if ids.len() > 1000 {
            return Err(Error::ResponseBound);
        }
        let mut unique = std::collections::HashSet::new();
        for value in &ids {
            id(*value)?;
            if !unique.insert(*value) {
                return Err(Error::ResponseShapeMismatch);
            }
        }
        Ok(ids)
    }
    /// # Errors
    /// Identical standard source rules with the explicit authenticated context.
    pub async fn authenticated_media(
        &self,
        credential: &Credential,
        id: u64,
    ) -> Result<crate::Media, Error> {
        crate::catalog::id(id)?;
        let (v, _) = self
            .request(
                "/api/song/enhance/player/url/v1",
                json!({"ids":format!("[{id}]"),"level":"standard","encodeType":"aac","e_r":false}),
                true,
                Some(&credential.cookie()),
            )
            .await?;
        crate::media::decode_media(&v, id)
    }
    /// # Errors
    /// Bounded authenticated daily songs; there is no invented playlist identity.
    pub async fn daily_tracks(&self, credential: &Credential) -> Result<Vec<Song>, Error> {
        let (v, _) = self
            .request(
                "/api/v3/discovery/recommend/songs",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let songs: Vec<Song> = decode(
            v.pointer("/data/dailySongs")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if songs.len() > 100 {
            return Err(Error::ResponseBound);
        }
        for s in &songs {
            s.validate()?;
        }
        Ok(songs)
    }
    /// # Errors
    /// One Personal FM batch only; no autoplay/feedback or hidden continuation.
    pub async fn personal_fm(&self, credential: &Credential) -> Result<Vec<Song>, Error> {
        let (v, _) = self
            .request(
                "/api/v1/radio/get",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let songs: Vec<Song> = decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        if songs.len() > 10 {
            return Err(Error::ResponseBound);
        }
        for s in &songs {
            s.validate()?;
        }
        Ok(songs)
    }
}

impl<T: Transport> NeteaseClient<T> {
    /// # Errors
    /// Bounded authenticated resource recommendations, with no invented pagination.
    pub async fn personalized_playlists(
        &self,
        credential: &Credential,
    ) -> Result<Vec<Playlist>, Error> {
        let (v, _) = self
            .request(
                "/api/v1/discovery/recommend/resource",
                json!({}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<Playlist> = decode(
            v.get("recommend")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        if items.len() > 100 {
            return Err(Error::ResponseBound);
        }
        for p in &items {
            p.validate()?;
        }
        Ok(items)
    }
    /// # Errors
    /// One bounded favorite-Album page; missing totals and contradictory continuation stop.
    pub async fn favorite_albums(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<crate::Page<crate::Album>, Error> {
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/album/sublist",
                json!({"offset":offset,"limit":size,"total":true}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<crate::Album> =
            decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        let total: u32 = decode(
            v.get("count")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(
            v.get("hasMore")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        crate::catalog::check_page(items.len(), offset, size, total, more)?;
        for a in &items {
            a.validate()?;
        }
        Ok(crate::Page {
            items,
            offset,
            total,
            more,
        })
    }
    /// # Errors
    /// One bounded favorite-Artist page; missing totals and contradictory continuation stop.
    pub async fn favorite_artists(
        &self,
        credential: &Credential,
        offset: u32,
        size: u32,
    ) -> Result<crate::Page<crate::Artist>, Error> {
        bounds(offset, size)?;
        let (v, _) = self
            .request(
                "/api/artist/sublist",
                json!({"offset":offset,"limit":size,"total":true}),
                false,
                Some(&credential.cookie()),
            )
            .await?;
        let items: Vec<crate::Artist> =
            decode(v.get("data").cloned().ok_or(Error::ResponseShapeMismatch)?)?;
        let total: u32 = decode(
            v.get("count")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        let more: bool = decode(
            v.get("hasMore")
                .cloned()
                .ok_or(Error::ResponseShapeMismatch)?,
        )?;
        crate::catalog::check_page(items.len(), offset, size, total, more)?;
        for a in &items {
            a.validate()?;
        }
        Ok(crate::Page {
            items,
            offset,
            total,
            more,
        })
    }
}
