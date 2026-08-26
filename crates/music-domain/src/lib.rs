//! Provider-independent music domain types.

use std::fmt;

mod lyrics;
mod playback_queue;

pub use lyrics::{
    InvalidLyricTiming, InvalidSynchronizedLyrics, LyricTimingField, SynchronizedLyricLine,
    SynchronizedLyrics, TimedLyricSegment,
};
pub use playback_queue::{InvalidPlaybackQueue, PlaybackQueue, PlaybackQueueRemoval};

/// Stable provider identity used by core domain objects.
///
/// This is intentionally not an enum: domain identity must not require a
/// central source edit if a future, approved provider is introduced.
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct ProviderId(String);

impl ProviderId {
    /// Builds an identity from a stable, non-empty lowercase ASCII key.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidProviderId`] when the key is empty or contains anything
    /// other than lowercase ASCII letters, digits, or `-`.
    pub fn new(value: impl Into<String>) -> Result<Self, InvalidProviderId> {
        let value = value.into();
        let valid = !value.is_empty()
            && value
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-');

        if valid {
            Ok(Self(value))
        } else {
            Err(InvalidProviderId)
        }
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for ProviderId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidProviderId;

impl fmt::Display for InvalidProviderId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("provider id must be a non-empty lowercase ASCII key")
    }
}

impl std::error::Error for InvalidProviderId {}

/// Provider-scoped playlist identity. The opaque value is interpreted only by
/// the owning provider and must not be parsed by presentation code.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct PlaylistId {
    provider: ProviderId,
    opaque: String,
}

impl PlaylistId {
    /// # Errors
    ///
    /// Returns [`InvalidPlaylistId`] when the provider-owned value is empty or
    /// whitespace-only.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidPlaylistId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidPlaylistId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    /// Returns the provider-owned identity for routing back to that provider.
    /// Other layers must treat it as opaque.
    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for PlaylistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidPlaylistId;

impl fmt::Display for InvalidPlaylistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("playlist identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidPlaylistId {}

/// Minimum provider-independent data required to present a playlist row.
#[derive(Clone, Eq, PartialEq)]
pub struct PlaylistSummary {
    id: PlaylistId,
    title: String,
    artwork_uri: Option<String>,
    track_count: Option<u32>,
}

impl PlaylistSummary {
    /// # Errors
    ///
    /// Returns [`InvalidPlaylistSummary`] when the title is empty or
    /// whitespace-only.
    pub fn new(id: PlaylistId, title: impl Into<String>) -> Result<Self, InvalidPlaylistSummary> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(InvalidPlaylistSummary);
        }
        Ok(Self {
            id,
            title,
            artwork_uri: None,
            track_count: None,
        })
    }

    #[must_use]
    pub fn with_artwork_uri(mut self, artwork_uri: Option<String>) -> Self {
        self.artwork_uri = artwork_uri.filter(|value| !value.trim().is_empty());
        self
    }

    #[must_use]
    pub const fn with_track_count(mut self, track_count: Option<u32>) -> Self {
        self.track_count = track_count;
        self
    }

    #[must_use]
    pub const fn id(&self) -> &PlaylistId {
        &self.id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn track_count(&self) -> Option<u32> {
        self.track_count
    }
}

impl fmt::Debug for PlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistSummary")
            .field("id", &self.id)
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidPlaylistSummary;

impl fmt::Display for InvalidPlaylistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("playlist summary title must not be empty")
    }
}

impl std::error::Error for InvalidPlaylistSummary {}

/// Provider-scoped ranking identity. The opaque value is interpreted only by
/// the owning Provider and must not be decoded by presentation code.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct RankingId {
    provider: ProviderId,
    opaque: String,
}

impl RankingId {
    /// # Errors
    ///
    /// Returns [`InvalidRankingId`] when the provider-owned value is blank.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidRankingId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidRankingId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for RankingId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RankingId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidRankingId;

impl fmt::Display for InvalidRankingId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("ranking identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidRankingId {}

/// Minimum provider-neutral current-ranking metadata needed by discovery and
/// the ranking Track route. Historical-period selection is deliberately not
/// part of this value.
#[derive(Clone, Eq, PartialEq)]
pub struct RankingSummary {
    id: RankingId,
    title: String,
    period: Option<String>,
    artwork_uri: Option<String>,
    track_count: Option<u32>,
}

impl RankingSummary {
    /// # Errors
    ///
    /// Returns [`InvalidRankingSummary`] when the title is blank.
    pub fn new(id: RankingId, title: impl Into<String>) -> Result<Self, InvalidRankingSummary> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(InvalidRankingSummary);
        }
        Ok(Self {
            id,
            title,
            period: None,
            artwork_uri: None,
            track_count: None,
        })
    }

    #[must_use]
    pub fn with_period(mut self, period: Option<String>) -> Self {
        self.period = nonblank(period);
        self
    }

    #[must_use]
    pub fn with_artwork_uri(mut self, artwork_uri: Option<String>) -> Self {
        self.artwork_uri = nonblank(artwork_uri);
        self
    }

    #[must_use]
    pub const fn with_track_count(mut self, track_count: Option<u32>) -> Self {
        self.track_count = track_count;
        self
    }

    #[must_use]
    pub const fn id(&self) -> &RankingId {
        &self.id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn period(&self) -> Option<&str> {
        self.period.as_deref()
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn track_count(&self) -> Option<u32> {
        self.track_count
    }
}

impl fmt::Debug for RankingSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RankingSummary")
            .field("id", &self.id)
            .field("title", &"[REDACTED]")
            .field("has_period", &self.period.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("track_count", &self.track_count)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidRankingSummary;

impl fmt::Display for InvalidRankingSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("ranking summary title must not be empty")
    }
}

impl std::error::Error for InvalidRankingSummary {}

/// One provider-neutral editorial grouping of current rankings.
#[derive(Clone, Eq, PartialEq)]
pub struct RankingGroup {
    title: String,
    rankings: Vec<RankingSummary>,
}

impl RankingGroup {
    /// # Errors
    ///
    /// Returns [`InvalidRankingGroup`] for a blank title or empty group.
    pub fn new(
        title: impl Into<String>,
        rankings: Vec<RankingSummary>,
    ) -> Result<Self, InvalidRankingGroup> {
        let title = title.into();
        if title.trim().is_empty() || rankings.is_empty() {
            return Err(InvalidRankingGroup);
        }
        Ok(Self { title, rankings })
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn rankings(&self) -> &[RankingSummary] {
        &self.rankings
    }
}

impl fmt::Debug for RankingGroup {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RankingGroup")
            .field("title", &"[REDACTED]")
            .field("ranking_count", &self.rankings.len())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidRankingGroup;

impl fmt::Display for InvalidRankingGroup {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("ranking group must have a title and at least one ranking")
    }
}

impl std::error::Error for InvalidRankingGroup {}

/// Provider-scoped track identity. Presentation and generic domain code must
/// not infer media-resolution fields from the opaque value.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct TrackId {
    provider: ProviderId,
    opaque: String,
}

impl TrackId {
    /// # Errors
    ///
    /// Returns [`InvalidTrackId`] when the provider-owned value is empty or
    /// whitespace-only.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidTrackId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidTrackId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    /// Returns the provider-owned identity for routing back to that provider.
    /// Other layers must treat it as opaque.
    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for TrackId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidTrackId;

impl fmt::Display for InvalidTrackId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("track identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidTrackId {}

/// Provider-scoped Album identity. The opaque value is interpreted only by
/// the owning Provider.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct AlbumId {
    provider: ProviderId,
    opaque: String,
}

impl AlbumId {
    /// # Errors
    ///
    /// Returns [`InvalidAlbumId`] when the provider-owned value is blank.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidAlbumId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidAlbumId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for AlbumId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidAlbumId;

impl fmt::Display for InvalidAlbumId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("album identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidAlbumId {}

/// Minimum provider-neutral Album data needed for a catalog transition.
#[derive(Clone, Eq, PartialEq)]
pub struct AlbumSummary {
    id: AlbumId,
    title: String,
    artwork_uri: Option<String>,
}

impl AlbumSummary {
    /// # Errors
    ///
    /// Returns [`InvalidAlbumSummary`] when the title is blank.
    pub fn new(id: AlbumId, title: impl Into<String>) -> Result<Self, InvalidAlbumSummary> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(InvalidAlbumSummary);
        }
        Ok(Self {
            id,
            title,
            artwork_uri: None,
        })
    }

    #[must_use]
    pub fn with_artwork_uri(mut self, artwork_uri: Option<String>) -> Self {
        self.artwork_uri = nonblank(artwork_uri);
        self
    }

    #[must_use]
    pub const fn id(&self) -> &AlbumId {
        &self.id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }
}

impl fmt::Debug for AlbumSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumSummary")
            .field("id", &self.id)
            .field("title", &"[REDACTED]")
            .field("has_artwork", &self.artwork_uri.is_some())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidAlbumSummary;

impl fmt::Display for InvalidAlbumSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("album summary title must not be empty")
    }
}

impl std::error::Error for InvalidAlbumSummary {}

/// Provider-scoped Artist identity. The opaque value is interpreted only by
/// the owning Provider.
#[derive(Clone, Eq, Hash, PartialEq)]
pub struct ArtistId {
    provider: ProviderId,
    opaque: String,
}

impl ArtistId {
    /// # Errors
    ///
    /// Returns [`InvalidArtistId`] when the provider-owned value is blank.
    pub fn new(provider: ProviderId, opaque: impl Into<String>) -> Result<Self, InvalidArtistId> {
        let opaque = opaque.into();
        if opaque.trim().is_empty() {
            return Err(InvalidArtistId);
        }
        Ok(Self { provider, opaque })
    }

    #[must_use]
    pub const fn provider(&self) -> &ProviderId {
        &self.provider
    }

    #[must_use]
    pub fn opaque(&self) -> &str {
        &self.opaque
    }
}

impl fmt::Debug for ArtistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ArtistId")
            .field("provider", &self.provider)
            .field("opaque", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidArtistId;

impl fmt::Display for InvalidArtistId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("artist identity must have a non-empty provider value")
    }
}

impl std::error::Error for InvalidArtistId {}

/// Minimum provider-neutral Artist data needed for a catalog transition.
#[derive(Clone, Eq, PartialEq)]
pub struct ArtistSummary {
    id: ArtistId,
    name: String,
}

impl ArtistSummary {
    /// # Errors
    ///
    /// Returns [`InvalidArtistSummary`] when the name is blank.
    pub fn new(id: ArtistId, name: impl Into<String>) -> Result<Self, InvalidArtistSummary> {
        let name = name.into();
        if name.trim().is_empty() {
            return Err(InvalidArtistSummary);
        }
        Ok(Self { id, name })
    }

    #[must_use]
    pub const fn id(&self) -> &ArtistId {
        &self.id
    }

    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }
}

impl fmt::Debug for ArtistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ArtistSummary")
            .field("id", &self.id)
            .field("name", &"[REDACTED]")
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidArtistSummary;

impl fmt::Display for InvalidArtistSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("artist summary name must not be empty")
    }
}

impl std::error::Error for InvalidArtistSummary {}

/// Provider-neutral canonical metadata for an existing Album transition.
/// Provider rights, tracking, booklet, video, and mutation data are absent.
#[derive(Clone, Eq, PartialEq)]
pub struct AlbumDetails {
    album: AlbumSummary,
    artists: Vec<ArtistSummary>,
    subtitle: Option<String>,
    release_date: Option<String>,
    description: Option<String>,
    language: Option<String>,
    album_type: Option<String>,
    genre: Option<String>,
    company: Option<String>,
}

impl AlbumDetails {
    #[must_use]
    pub fn new(album: AlbumSummary, artists: Vec<ArtistSummary>) -> Self {
        Self {
            album,
            artists,
            subtitle: None,
            release_date: None,
            description: None,
            language: None,
            album_type: None,
            genre: None,
            company: None,
        }
    }

    #[must_use]
    pub fn with_subtitle(mut self, value: Option<String>) -> Self {
        self.subtitle = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_release_date(mut self, value: Option<String>) -> Self {
        self.release_date = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_description(mut self, value: Option<String>) -> Self {
        self.description = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_language(mut self, value: Option<String>) -> Self {
        self.language = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_album_type(mut self, value: Option<String>) -> Self {
        self.album_type = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_genre(mut self, value: Option<String>) -> Self {
        self.genre = nonblank(value);
        self
    }

    #[must_use]
    pub fn with_company(mut self, value: Option<String>) -> Self {
        self.company = nonblank(value);
        self
    }

    #[must_use]
    pub const fn album(&self) -> &AlbumSummary {
        &self.album
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub fn subtitle(&self) -> Option<&str> {
        self.subtitle.as_deref()
    }

    #[must_use]
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }

    #[must_use]
    pub fn description(&self) -> Option<&str> {
        self.description.as_deref()
    }

    #[must_use]
    pub fn language(&self) -> Option<&str> {
        self.language.as_deref()
    }

    #[must_use]
    pub fn album_type(&self) -> Option<&str> {
        self.album_type.as_deref()
    }

    #[must_use]
    pub fn genre(&self) -> Option<&str> {
        self.genre.as_deref()
    }

    #[must_use]
    pub fn company(&self) -> Option<&str> {
        self.company.as_deref()
    }
}

impl fmt::Debug for AlbumDetails {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumDetails")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_subtitle", &self.subtitle.is_some())
            .field("has_release_date", &self.release_date.is_some())
            .field("has_description", &self.description.is_some())
            .field("has_language", &self.language.is_some())
            .field("has_album_type", &self.album_type.is_some())
            .field("has_genre", &self.genre.is_some())
            .field("has_company", &self.company.is_some())
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AudioFormat {
    Mp3,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AudioQuality {
    Standard,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ResolvedMediaSourceField {
    Uri,
    Validity,
}

/// Provider-neutral short-lived source for immediate playback. Provider
/// authorization material may be embedded in the URI and is always redacted
/// from diagnostics.
#[derive(Clone, Eq, PartialEq)]
pub struct ResolvedMediaSource {
    track_id: TrackId,
    uri: String,
    format: AudioFormat,
    quality: AudioQuality,
    valid_for_seconds: u32,
}

impl ResolvedMediaSource {
    /// # Errors
    ///
    /// Rejects an empty/whitespace-padded URI or zero validity. URI scheme and
    /// authority rules remain provider-specific and must be checked before
    /// constructing this generic value.
    pub fn new(
        track_id: TrackId,
        uri: impl Into<String>,
        format: AudioFormat,
        quality: AudioQuality,
        valid_for_seconds: u32,
    ) -> Result<Self, InvalidResolvedMediaSource> {
        let uri = uri.into();
        if uri.is_empty() || uri.trim() != uri {
            return Err(InvalidResolvedMediaSource {
                field: ResolvedMediaSourceField::Uri,
            });
        }
        if valid_for_seconds == 0 {
            return Err(InvalidResolvedMediaSource {
                field: ResolvedMediaSourceField::Validity,
            });
        }
        Ok(Self {
            track_id,
            uri,
            format,
            quality,
            valid_for_seconds,
        })
    }

    #[must_use]
    pub const fn track_id(&self) -> &TrackId {
        &self.track_id
    }

    /// Returns secret-bearing source data for immediate playback only.
    #[must_use]
    pub fn uri(&self) -> &str {
        &self.uri
    }

    #[must_use]
    pub const fn format(&self) -> AudioFormat {
        self.format
    }

    #[must_use]
    pub const fn quality(&self) -> AudioQuality {
        self.quality
    }

    #[must_use]
    pub const fn valid_for_seconds(&self) -> u32 {
        self.valid_for_seconds
    }
}

impl fmt::Debug for ResolvedMediaSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ResolvedMediaSource")
            .field("track_id", &self.track_id)
            .field("uri", &"[REDACTED]")
            .field("format", &self.format)
            .field("quality", &self.quality)
            .field("valid_for_seconds", &self.valid_for_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidResolvedMediaSource {
    field: ResolvedMediaSourceField,
}

impl InvalidResolvedMediaSource {
    #[must_use]
    pub const fn field(self) -> ResolvedMediaSourceField {
        self.field
    }
}

impl fmt::Display for InvalidResolvedMediaSource {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "resolved media source has an invalid {:?}",
            self.field
        )
    }
}

impl std::error::Error for InvalidResolvedMediaSource {}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TrackSummaryField {
    Title,
    ArtistName,
}

/// Minimum provider-independent track data required by a playlist-detail row.
/// Playback rights and provider protocol fields are deliberately absent.
#[derive(Clone, Eq, PartialEq)]
pub struct TrackSummary {
    id: TrackId,
    title: String,
    subtitle: Option<String>,
    artist_names: Vec<String>,
    artists: Vec<ArtistSummary>,
    album_title: Option<String>,
    album: Option<AlbumSummary>,
    artwork_uri: Option<String>,
    duration_seconds: Option<u32>,
}

impl TrackSummary {
    /// # Errors
    ///
    /// Rejects a blank title or any blank artist credit. An empty artist list
    /// remains valid so unavailable-track behavior can be modeled later from
    /// evidence instead of being guessed here.
    pub fn new(
        id: TrackId,
        title: impl Into<String>,
        artist_names: Vec<String>,
    ) -> Result<Self, InvalidTrackSummary> {
        let title = title.into();
        if title.trim().is_empty() {
            return Err(InvalidTrackSummary {
                field: TrackSummaryField::Title,
            });
        }
        if artist_names.iter().any(|name| name.trim().is_empty()) {
            return Err(InvalidTrackSummary {
                field: TrackSummaryField::ArtistName,
            });
        }
        Ok(Self {
            id,
            title,
            subtitle: None,
            artist_names,
            artists: Vec::new(),
            album_title: None,
            album: None,
            artwork_uri: None,
            duration_seconds: None,
        })
    }

    #[must_use]
    pub fn with_subtitle(mut self, subtitle: Option<String>) -> Self {
        self.subtitle = nonblank(subtitle);
        self
    }

    #[must_use]
    pub fn with_album_title(mut self, album_title: Option<String>) -> Self {
        self.album_title = nonblank(album_title);
        self
    }

    #[must_use]
    pub fn with_artists(mut self, artists: Vec<ArtistSummary>) -> Self {
        self.artists = artists;
        self
    }

    #[must_use]
    pub fn with_album(mut self, album: Option<AlbumSummary>) -> Self {
        self.album = album;
        self
    }

    #[must_use]
    pub fn with_artwork_uri(mut self, artwork_uri: Option<String>) -> Self {
        self.artwork_uri = nonblank(artwork_uri);
        self
    }

    #[must_use]
    pub const fn with_duration_seconds(mut self, duration_seconds: Option<u32>) -> Self {
        self.duration_seconds = duration_seconds;
        self
    }

    #[must_use]
    pub const fn id(&self) -> &TrackId {
        &self.id
    }

    #[must_use]
    pub fn title(&self) -> &str {
        &self.title
    }

    #[must_use]
    pub fn subtitle(&self) -> Option<&str> {
        self.subtitle.as_deref()
    }

    #[must_use]
    pub fn artist_names(&self) -> &[String] {
        &self.artist_names
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub fn album_title(&self) -> Option<&str> {
        self.album_title.as_deref()
    }

    #[must_use]
    pub const fn album(&self) -> Option<&AlbumSummary> {
        self.album.as_ref()
    }

    #[must_use]
    pub fn artwork_uri(&self) -> Option<&str> {
        self.artwork_uri.as_deref()
    }

    #[must_use]
    pub const fn duration_seconds(&self) -> Option<u32> {
        self.duration_seconds
    }
}

impl fmt::Debug for TrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackSummary")
            .field("id", &self.id)
            .field("title", &"[REDACTED]")
            .field("has_subtitle", &self.subtitle.is_some())
            .field("artist_count", &self.artist_names.len())
            .field("artist_identity_count", &self.artists.len())
            .field("has_album_title", &self.album_title.is_some())
            .field("has_album", &self.album.is_some())
            .field("has_artwork", &self.artwork_uri.is_some())
            .field("duration_seconds", &self.duration_seconds)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InvalidTrackSummary {
    field: TrackSummaryField,
}

impl InvalidTrackSummary {
    #[must_use]
    pub const fn field(self) -> TrackSummaryField {
        self.field
    }
}

impl fmt::Display for InvalidTrackSummary {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "track summary has an invalid {:?}", self.field)
    }
}

impl std::error::Error for InvalidTrackSummary {}

/// One bounded page of playlist tracks. Source-specific route and pagination
/// rules remain in the provider implementation.
#[derive(Clone, Eq, PartialEq)]
pub struct PlaylistTracksPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

/// One bounded page of provider-neutral playlist recommendations. The owning
/// Provider decides recommendation ranking and source-specific continuation.
#[derive(Clone, Eq, PartialEq)]
pub struct RecommendedPlaylistsPage {
    offset: u32,
    has_more: bool,
    playlists: Vec<PlaylistSummary>,
}

/// One provider-neutral page of QQ-native Radar Track recommendations.
/// Provider-specific personalization and continuation remain behind the
/// Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct RadarTrackPage {
    page: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

/// One bounded page of Albums favorited by the current account. The owning
/// Provider keeps account identity and source-specific continuation private.
#[derive(Clone, Eq, PartialEq)]
pub struct FavoriteAlbumsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    albums: Vec<AlbumSummary>,
}

/// One bounded page of Artists followed by the current account. The owning
/// Provider keeps account identity and source-specific continuation private.
#[derive(Clone, Eq, PartialEq)]
pub struct FavoriteArtistsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    artists: Vec<ArtistSummary>,
}

impl FavoriteArtistsPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, artists: Vec<ArtistSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            artists,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }
}

impl fmt::Debug for FavoriteArtistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("FavoriteArtistsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .finish()
    }
}

impl FavoriteAlbumsPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, albums: Vec<AlbumSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            albums,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn albums(&self) -> &[AlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for FavoriteAlbumsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("FavoriteAlbumsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .finish()
    }
}

impl RadarTrackPage {
    #[must_use]
    pub const fn new(page: u32, has_more: bool, tracks: Vec<TrackSummary>) -> Self {
        Self {
            page,
            has_more,
            tracks,
        }
    }

    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for RadarTrackPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RadarTrackPage")
            .field("page", &self.page)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

/// One bounded page of the current Track list for a ranking. The owning
/// Provider decides what "current" means and how the opaque ranking routes.
#[derive(Clone, Eq, PartialEq)]
pub struct RankingTracksPage {
    ranking: RankingSummary,
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

impl RankingTracksPage {
    #[must_use]
    pub const fn new(
        ranking: RankingSummary,
        offset: u32,
        total: u32,
        has_more: bool,
        tracks: Vec<TrackSummary>,
    ) -> Self {
        Self {
            ranking,
            offset,
            total,
            has_more,
            tracks,
        }
    }

    #[must_use]
    pub const fn ranking(&self) -> &RankingSummary {
        &self.ranking
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for RankingTracksPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RankingTracksPage")
            .field("ranking", &self.ranking)
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

impl RecommendedPlaylistsPage {
    #[must_use]
    pub const fn new(offset: u32, has_more: bool, playlists: Vec<PlaylistSummary>) -> Self {
        Self {
            offset,
            has_more,
            playlists,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn playlists(&self) -> &[PlaylistSummary] {
        &self.playlists
    }
}

impl fmt::Debug for RecommendedPlaylistsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RecommendedPlaylistsPage")
            .field("offset", &self.offset)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

/// One provider-neutral page of Track search results. Source-specific query,
/// ranking, and continuation rules remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct TrackSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    items: Vec<TrackSearchItem>,
}

/// One Track result plus optional catalog transitions evidenced by that
/// result. Catalog identities remain absent when QQ omits their validated
/// minimum fields.
#[derive(Clone, Eq, PartialEq)]
pub struct TrackSearchItem {
    track: TrackSummary,
    album: Option<AlbumSummary>,
    artists: Vec<ArtistSummary>,
}

impl TrackSearchItem {
    #[must_use]
    pub const fn new(
        track: TrackSummary,
        album: Option<AlbumSummary>,
        artists: Vec<ArtistSummary>,
    ) -> Self {
        Self {
            track,
            album,
            artists,
        }
    }

    #[must_use]
    pub const fn track(&self) -> &TrackSummary {
        &self.track
    }

    #[must_use]
    pub const fn album(&self) -> Option<&AlbumSummary> {
        self.album.as_ref()
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }
}

impl fmt::Debug for TrackSearchItem {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackSearchItem")
            .field("track", &self.track)
            .field("album", &self.album)
            .field("artists", &self.artists)
            .finish()
    }
}

impl TrackSearchPage {
    #[must_use]
    pub const fn new(page: u32, total: u32, has_more: bool, items: Vec<TrackSearchItem>) -> Self {
        Self {
            page,
            total,
            has_more,
            items,
        }
    }

    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn items(&self) -> &[TrackSearchItem] {
        &self.items
    }
}

impl fmt::Debug for TrackSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("item_count", &self.items.len())
            .finish()
    }
}

/// One provider-neutral page of Artist search results. Source-specific query,
/// ranking, and continuation rules remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct ArtistSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    artists: Vec<ArtistSummary>,
}

impl ArtistSearchPage {
    #[must_use]
    pub const fn new(page: u32, total: u32, has_more: bool, artists: Vec<ArtistSummary>) -> Self {
        Self {
            page,
            total,
            has_more,
            artists,
        }
    }

    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }
}

impl fmt::Debug for ArtistSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ArtistSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("artist_count", &self.artists.len())
            .finish()
    }
}

/// One provider-neutral page of Album search results. Source-specific query,
/// ranking, and continuation rules remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct AlbumSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    albums: Vec<AlbumSummary>,
}

impl AlbumSearchPage {
    #[must_use]
    pub const fn new(page: u32, total: u32, has_more: bool, albums: Vec<AlbumSummary>) -> Self {
        Self {
            page,
            total,
            has_more,
            albums,
        }
    }

    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn albums(&self) -> &[AlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for AlbumSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .finish()
    }
}

/// One provider-neutral page of Playlist search results. Source-specific
/// query ranking and page continuation remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct PlaylistSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    playlists: Vec<PlaylistSummary>,
}

impl PlaylistSearchPage {
    #[must_use]
    pub const fn new(
        page: u32,
        total: u32,
        has_more: bool,
        playlists: Vec<PlaylistSummary>,
    ) -> Self {
        Self {
            page,
            total,
            has_more,
            playlists,
        }
    }

    #[must_use]
    pub const fn page(&self) -> u32 {
        self.page
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn playlists(&self) -> &[PlaylistSummary] {
        &self.playlists
    }
}

impl fmt::Debug for PlaylistSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("playlist_count", &self.playlists.len())
            .finish()
    }
}

/// One bounded page of Album Tracks. QQ-specific pagination and Album route
/// rules remain in the owning Provider.
#[derive(Clone, Eq, PartialEq)]
pub struct AlbumTracksPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

impl AlbumTracksPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, tracks: Vec<TrackSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            tracks,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for AlbumTracksPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AlbumTracksPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

/// One bounded page of Artist Tracks. QQ-specific pagination and Artist route
/// rules remain in the owning Provider.
#[derive(Clone, Eq, PartialEq)]
pub struct ArtistTracksPage {
    offset: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

impl ArtistTracksPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, tracks: Vec<TrackSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            tracks,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for ArtistTracksPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ArtistTracksPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

/// One bounded page of an Artist's Albums. QQ-specific pagination and Artist
/// route rules remain in the owning Provider.
#[derive(Clone, Eq, PartialEq)]
pub struct ArtistAlbumsPage {
    offset: u32,
    total: u32,
    has_more: bool,
    albums: Vec<AlbumSummary>,
}

impl ArtistAlbumsPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, albums: Vec<AlbumSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            albums,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn albums(&self) -> &[AlbumSummary] {
        &self.albums
    }
}

impl fmt::Debug for ArtistAlbumsPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ArtistAlbumsPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("album_count", &self.albums.len())
            .finish()
    }
}

/// Provider-neutral regions currently exposed by QQ Music's new-release
/// catalog. Providers that cannot map these regions do not implement the
/// corresponding capability.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum NewAlbumRegion {
    MainlandChina,
    HongKongTaiwan,
    Western,
    Korea,
    Japan,
    Other,
}

/// Provider-neutral categories exposed by QQ Music's bounded new-song
/// collection. Providers that cannot map these categories do not implement
/// the corresponding capability.
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum NewSongCategory {
    MainlandChina,
    Western,
    Japan,
    Korea,
    Latest,
    HongKongTaiwan,
}

/// One bounded whole-response new-song collection. The external operation has
/// no pagination input, so Domain deliberately exposes no invented cursor.
#[derive(Clone, Eq, PartialEq)]
pub struct NewSongCollection {
    category: NewSongCategory,
    tracks: Vec<TrackSummary>,
}

impl NewSongCollection {
    #[must_use]
    pub const fn new(category: NewSongCategory, tracks: Vec<TrackSummary>) -> Self {
        Self { category, tracks }
    }

    #[must_use]
    pub const fn category(&self) -> NewSongCategory {
        self.category
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for NewSongCollection {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NewSongCollection")
            .field("category", &self.category)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

/// Minimum provider-neutral data for one newly released Album. Release dates
/// remain display metadata rather than parsed calendar policy.
#[derive(Clone, Eq, PartialEq)]
pub struct NewAlbumRelease {
    album: AlbumSummary,
    artists: Vec<ArtistSummary>,
    release_date: Option<String>,
}

impl NewAlbumRelease {
    #[must_use]
    pub fn new(
        album: AlbumSummary,
        artists: Vec<ArtistSummary>,
        release_date: Option<String>,
    ) -> Self {
        Self {
            album,
            artists,
            release_date: nonblank(release_date),
        }
    }

    #[must_use]
    pub const fn album(&self) -> &AlbumSummary {
        &self.album
    }

    #[must_use]
    pub fn artists(&self) -> &[ArtistSummary] {
        &self.artists
    }

    #[must_use]
    pub fn release_date(&self) -> Option<&str> {
        self.release_date.as_deref()
    }
}

impl fmt::Debug for NewAlbumRelease {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NewAlbumRelease")
            .field("album", &self.album)
            .field("artist_count", &self.artists.len())
            .field("has_release_date", &self.release_date.is_some())
            .finish()
    }
}

/// One bounded offset page of regional new Album releases. Provider-specific
/// area values and request pagination remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct NewAlbumReleasesPage {
    region: NewAlbumRegion,
    offset: u32,
    total: u32,
    has_more: bool,
    releases: Vec<NewAlbumRelease>,
}

impl NewAlbumReleasesPage {
    #[must_use]
    pub const fn new(
        region: NewAlbumRegion,
        offset: u32,
        total: u32,
        has_more: bool,
        releases: Vec<NewAlbumRelease>,
    ) -> Self {
        Self {
            region,
            offset,
            total,
            has_more,
            releases,
        }
    }

    #[must_use]
    pub const fn region(&self) -> NewAlbumRegion {
        self.region
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn releases(&self) -> &[NewAlbumRelease] {
        &self.releases
    }
}

impl fmt::Debug for NewAlbumReleasesPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("NewAlbumReleasesPage")
            .field("region", &self.region)
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("release_count", &self.releases.len())
            .finish()
    }
}

impl PlaylistTracksPage {
    #[must_use]
    pub const fn new(offset: u32, total: u32, has_more: bool, tracks: Vec<TrackSummary>) -> Self {
        Self {
            offset,
            total,
            has_more,
            tracks,
        }
    }

    #[must_use]
    pub const fn offset(&self) -> u32 {
        self.offset
    }

    #[must_use]
    pub const fn total(&self) -> u32 {
        self.total
    }

    #[must_use]
    pub const fn has_more(&self) -> bool {
        self.has_more
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for PlaylistTracksPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaylistTracksPage")
            .field("offset", &self.offset)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
            .finish()
    }
}

fn nonblank(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::{
        AlbumDetails, AlbumId, AlbumSearchPage, AlbumSummary, AlbumTracksPage, ArtistId,
        ArtistSearchPage, ArtistSummary, AudioFormat, AudioQuality, NewAlbumRegion,
        NewAlbumRelease, NewAlbumReleasesPage, NewSongCategory, NewSongCollection, PlaylistId,
        PlaylistSearchPage, PlaylistSummary, PlaylistTracksPage, ProviderId, RadarTrackPage,
        RankingGroup, RankingId, RankingSummary, RankingTracksPage, ResolvedMediaSource,
        ResolvedMediaSourceField, TrackId, TrackSearchItem, TrackSearchPage, TrackSummary,
        TrackSummaryField,
    };

    #[test]
    fn provider_id_accepts_stable_keys() {
        let id = ProviderId::new("qq-music").expect("valid provider id");
        assert_eq!(id.as_str(), "qq-music");
    }

    #[test]
    fn provider_id_rejects_display_names_and_empty_values() {
        for value in ["", "QQMusic", "qq music", "qq_music"] {
            assert!(ProviderId::new(value).is_err(), "accepted {value:?}");
        }
    }

    #[test]
    fn playlist_identity_is_provider_scoped_and_opaque() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");

        assert_eq!(id.provider().as_str(), "qq-music");
        assert_eq!(id.opaque(), "owned:7001:201");
        assert!(!format!("{id:?}").contains("7001"));
        assert!(PlaylistId::new(ProviderId::new("qq-music").expect("provider"), "   ").is_err());
    }

    #[test]
    fn playlist_summary_keeps_optional_display_metadata_honest() {
        let id = PlaylistId::new(
            ProviderId::new("qq-music").expect("provider"),
            "owned:7001:201",
        )
        .expect("playlist ID");
        let summary = PlaylistSummary::new(id, "Synthetic favorites")
            .expect("summary")
            .with_artwork_uri(Some("https://example.invalid/cover.jpg".into()))
            .with_track_count(Some(42));

        assert_eq!(summary.title(), "Synthetic favorites");
        assert_eq!(summary.track_count(), Some(42));
        assert_eq!(
            summary.artwork_uri(),
            Some("https://example.invalid/cover.jpg")
        );
        assert!(!format!("{summary:?}").contains("Synthetic favorites"));
    }

    #[test]
    fn track_summary_is_provider_scoped_minimum_display_data() {
        let id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:fixture-mid",
        )
        .expect("track ID");
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:fixture-album-mid",
            )
            .expect("album ID"),
            "Synthetic album",
        )
        .expect("album");
        let artist = ArtistSummary::new(
            ArtistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "artist:42001:fixture-artist-mid",
            )
            .expect("artist ID"),
            "Artist one",
        )
        .expect("artist");
        let summary = TrackSummary::new(id, "Synthetic track", vec!["Artist one".into()])
            .expect("track summary")
            .with_subtitle(Some("Synthetic subtitle".into()))
            .with_artists(vec![artist])
            .with_album_title(Some("Synthetic album".into()))
            .with_album(Some(album))
            .with_artwork_uri(Some("https://example.invalid/album.jpg".into()))
            .with_duration_seconds(Some(245));

        assert_eq!(summary.id().provider().as_str(), "qq-music");
        assert_eq!(summary.id().opaque(), "track:41001:0:1:fixture-mid");
        assert_eq!(summary.title(), "Synthetic track");
        assert_eq!(summary.artist_names(), ["Artist one"]);
        assert_eq!(
            summary.artists()[0].id().opaque(),
            "artist:42001:fixture-artist-mid"
        );
        assert_eq!(summary.album_title(), Some("Synthetic album"));
        assert_eq!(
            summary.album().expect("Album context").id().opaque(),
            "album:43001:fixture-album-mid"
        );
        assert_eq!(summary.duration_seconds(), Some(245));
        let debug = format!("{summary:?}");
        assert!(!debug.contains("Synthetic track"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("42001"));
        assert!(!debug.contains("43001"));
    }

    #[test]
    fn track_search_page_keeps_query_and_content_out_of_diagnostics() {
        let id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:fixture-mid:-",
        )
        .expect("track ID");
        let track = TrackSummary::new(id, "must-not-leak", vec!["private-artist".into()])
            .expect("track summary");
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:fixture-album-mid",
            )
            .expect("album ID"),
            "private-album",
        )
        .expect("album summary");
        let artist = ArtistSummary::new(
            ArtistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "artist:42001:fixture-artist-mid",
            )
            .expect("artist ID"),
            "private-artist",
        )
        .expect("artist summary");
        let page = TrackSearchPage::new(
            2,
            45,
            true,
            vec![TrackSearchItem::new(track, Some(album), vec![artist])],
        );

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 45);
        assert!(page.has_more());
        assert_eq!(page.items().len(), 1);
        assert!(page.items()[0].album().is_some());
        assert_eq!(page.items()[0].artists().len(), 1);
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("private-artist"));
        assert!(!debug.contains("private-album"));
        assert!(!debug.contains("43001"));
    }

    #[test]
    fn artist_search_page_keeps_query_and_content_out_of_diagnostics() {
        let artist = ArtistSummary::new(
            ArtistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "artist:42001:fixture-artist-mid",
            )
            .expect("artist ID"),
            "must-not-leak",
        )
        .expect("artist summary");
        let page = ArtistSearchPage::new(2, 8, false, vec![artist]);

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 8);
        assert!(!page.has_more());
        assert_eq!(page.artists()[0].name(), "must-not-leak");
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("42001"));
    }

    #[test]
    fn album_search_page_keeps_query_and_content_out_of_diagnostics() {
        let album = AlbumSummary::new(
            AlbumId::new(
                ProviderId::new("qq-music").expect("provider"),
                "album:43001:fixture-album-mid",
            )
            .expect("album ID"),
            "must-not-leak",
        )
        .expect("album summary");
        let page = AlbumSearchPage::new(2, 25, true, vec![album]);

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 25);
        assert!(page.has_more());
        assert_eq!(page.albums()[0].title(), "must-not-leak");
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("43001"));
    }

    #[test]
    fn album_details_keep_optional_metadata_and_content_out_of_diagnostics() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let album = AlbumSummary::new(
            AlbumId::new(provider.clone(), "album:43001:private-album-mid").expect("Album ID"),
            "must-not-leak-album",
        )
        .expect("Album");
        let artist = ArtistSummary::new(
            ArtistId::new(provider, "artist:42001:private-artist-mid").expect("Artist ID"),
            "must-not-leak-artist",
        )
        .expect("Artist");
        let details = AlbumDetails::new(album, vec![artist])
            .with_subtitle(Some("private-subtitle".into()))
            .with_release_date(Some("2026-08-26".into()))
            .with_description(Some("private-description".into()))
            .with_language(Some("private-language".into()))
            .with_album_type(Some("private-type".into()))
            .with_genre(Some("private-genre".into()))
            .with_company(Some("private-company".into()));

        assert_eq!(details.artists().len(), 1);
        assert_eq!(details.subtitle(), Some("private-subtitle"));
        assert_eq!(details.release_date(), Some("2026-08-26"));
        assert_eq!(details.description(), Some("private-description"));
        assert_eq!(details.language(), Some("private-language"));
        assert_eq!(details.album_type(), Some("private-type"));
        assert_eq!(details.genre(), Some("private-genre"));
        assert_eq!(details.company(), Some("private-company"));
        let debug = format!("{details:?}");
        for private in ["must-not-leak", "private-", "2026-08-26", "43001", "42001"] {
            assert!(!debug.contains(private));
        }
    }

    #[test]
    fn new_album_page_keeps_region_and_continuation_without_content_diagnostics() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let album = AlbumSummary::new(
            AlbumId::new(provider.clone(), "album:43001:fixture-album-mid").expect("album ID"),
            "must-not-leak-album",
        )
        .expect("Album");
        let artist = ArtistSummary::new(
            ArtistId::new(provider, "artist:42001:fixture-artist-mid").expect("artist ID"),
            "must-not-leak-artist",
        )
        .expect("Artist");
        let page = NewAlbumReleasesPage::new(
            NewAlbumRegion::Japan,
            5,
            11,
            true,
            vec![NewAlbumRelease::new(
                album,
                vec![artist],
                Some("2026-08-26".into()),
            )],
        );

        assert_eq!(page.region(), NewAlbumRegion::Japan);
        assert_eq!(page.offset(), 5);
        assert_eq!(page.total(), 11);
        assert!(page.has_more());
        assert_eq!(page.releases().len(), 1);
        assert_eq!(page.releases()[0].artists().len(), 1);
        assert_eq!(page.releases()[0].release_date(), Some("2026-08-26"));
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("43001"));
        assert!(!debug.contains("2026-08-26"));
    }

    #[test]
    fn new_song_collection_has_no_invented_pagination_or_content_diagnostics() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:41001:0:fixture-mid:-",
            )
            .expect("Track ID"),
            "must-not-leak",
            vec!["private-artist".into()],
        )
        .expect("Track");
        let collection = NewSongCollection::new(NewSongCategory::Latest, vec![track]);

        assert_eq!(collection.category(), NewSongCategory::Latest);
        assert_eq!(collection.tracks().len(), 1);
        let debug = format!("{collection:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("41001"));
        assert!(!debug.contains("private-artist"));
    }

    #[test]
    fn playlist_search_page_keeps_query_and_content_out_of_diagnostics() {
        let playlist = PlaylistSummary::new(
            PlaylistId::new(
                ProviderId::new("qq-music").expect("provider"),
                "catalog:44001",
            )
            .expect("playlist ID"),
            "must-not-leak",
        )
        .expect("playlist summary")
        .with_track_count(Some(42));
        let page = PlaylistSearchPage::new(2, 25, true, vec![playlist]);

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 25);
        assert!(page.has_more());
        assert_eq!(page.playlists()[0].title(), "must-not-leak");
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("44001"));
    }

    #[test]
    fn ranking_values_preserve_current_metadata_and_redact_content() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let ranking = RankingSummary::new(
            RankingId::new(provider.clone(), "ranking:62001").expect("ranking ID"),
            "must-not-leak-ranking",
        )
        .expect("ranking")
        .with_period(Some("private-period".into()))
        .with_artwork_uri(Some("https://example.invalid/private.jpg".into()))
        .with_track_count(Some(100));
        let group =
            RankingGroup::new("must-not-leak-group", vec![ranking.clone()]).expect("ranking group");
        let track = TrackSummary::new(
            TrackId::new(provider, "track:41001:0:fixture-mid:-").expect("track ID"),
            "must-not-leak-track",
            vec!["private-artist".into()],
        )
        .expect("track");
        let page = RankingTracksPage::new(ranking, 0, 100, true, vec![track]);

        assert_eq!(group.title(), "must-not-leak-group");
        assert_eq!(group.rankings().len(), 1);
        assert_eq!(group.rankings()[0].period(), Some("private-period"));
        assert_eq!(group.rankings()[0].track_count(), Some(100));
        assert_eq!(page.offset(), 0);
        assert_eq!(page.total(), 100);
        assert!(page.has_more());
        assert_eq!(page.tracks().len(), 1);
        let debug = format!("{group:?} {page:?}");
        for private in [
            "must-not-leak-group",
            "must-not-leak-ranking",
            "must-not-leak-track",
            "private-period",
            "private-artist",
            "62001",
            "41001",
        ] {
            assert!(!debug.contains(private));
        }
        assert!(RankingGroup::new("group", Vec::new()).is_err());
        assert!(
            RankingSummary::new(
                RankingId::new(ProviderId::new("qq-music").expect("provider"), "ranking:1")
                    .expect("ranking ID"),
                "   "
            )
            .is_err()
        );
    }

    #[test]
    fn radar_page_preserves_continuation_and_redacts_track_content() {
        let track = TrackSummary::new(
            TrackId::new(
                ProviderId::new("qq-music").expect("provider"),
                "track:radar-private",
            )
            .expect("track ID"),
            "must-not-leak",
            vec!["private-artist".into()],
        )
        .expect("track");
        let page = RadarTrackPage::new(2, true, vec![track]);

        assert_eq!(page.page(), 2);
        assert!(page.has_more());
        assert_eq!(page.tracks()[0].title(), "must-not-leak");
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("radar:private"));
    }

    #[test]
    fn track_summary_rejects_blank_display_fields_and_page_hides_content() {
        let provider = ProviderId::new("qq-music").expect("provider");
        let blank_title = TrackSummary::new(
            TrackId::new(provider.clone(), "track:1").expect("track ID"),
            " ",
            Vec::new(),
        )
        .expect_err("blank title");
        assert_eq!(blank_title.field(), TrackSummaryField::Title);
        let blank_artist = TrackSummary::new(
            TrackId::new(provider, "track:2").expect("track ID"),
            "Synthetic title",
            vec![String::new()],
        )
        .expect_err("blank artist");
        assert_eq!(blank_artist.field(), TrackSummaryField::ArtistName);

        let page = PlaylistTracksPage::new(100, 100, false, Vec::new());
        assert_eq!(page.offset(), 100);
        assert_eq!(page.total(), 100);
        assert!(!page.has_more());
        assert!(page.tracks().is_empty());

        let album_page = AlbumTracksPage::new(30, 30, false, Vec::new());
        assert_eq!(album_page.offset(), 30);
        assert_eq!(album_page.total(), 30);
        assert!(!album_page.has_more());
        assert!(album_page.tracks().is_empty());
    }

    #[test]
    fn resolved_media_source_redacts_short_lived_authorization() {
        let track_id = TrackId::new(
            ProviderId::new("qq-music").expect("provider"),
            "track:41001:0:1:fixture-mid",
        )
        .expect("track ID");
        let source = ResolvedMediaSource::new(
            track_id,
            "http://audio.example.test/fixture.mp3?vkey=private",
            AudioFormat::Mp3,
            AudioQuality::Standard,
            7_200,
        )
        .expect("media source");

        assert_eq!(source.track_id().provider().as_str(), "qq-music");
        assert_eq!(source.format(), AudioFormat::Mp3);
        assert_eq!(source.quality(), AudioQuality::Standard);
        assert_eq!(source.valid_for_seconds(), 7_200);
        assert!(source.uri().contains("vkey=private"));
        let debug = format!("{source:?}");
        assert!(!debug.contains("vkey"));
        assert!(!debug.contains("41001"));
    }

    #[test]
    fn resolved_media_source_rejects_invalid_uri_and_validity() {
        let track_id = || {
            TrackId::new(ProviderId::new("local").expect("provider"), "track:fixture")
                .expect("track ID")
        };
        let invalid_uri = ResolvedMediaSource::new(
            track_id(),
            " source ",
            AudioFormat::Mp3,
            AudioQuality::Standard,
            1,
        )
        .expect_err("whitespace-padded URI");
        assert_eq!(invalid_uri.field(), ResolvedMediaSourceField::Uri);
        let invalid_validity = ResolvedMediaSource::new(
            track_id(),
            "file:///fixture.mp3",
            AudioFormat::Mp3,
            AudioQuality::Standard,
            0,
        )
        .expect_err("zero validity");
        assert_eq!(invalid_validity.field(), ResolvedMediaSourceField::Validity);
    }
}
