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
    album_title: Option<String>,
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
            album_title: None,
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
    pub fn album_title(&self) -> Option<&str> {
        self.album_title.as_deref()
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
            .field("has_album_title", &self.album_title.is_some())
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

/// One provider-neutral page of Track search results. Source-specific query,
/// ranking, and continuation rules remain behind the Provider boundary.
#[derive(Clone, Eq, PartialEq)]
pub struct TrackSearchPage {
    page: u32,
    total: u32,
    has_more: bool,
    tracks: Vec<TrackSummary>,
}

impl TrackSearchPage {
    #[must_use]
    pub const fn new(page: u32, total: u32, has_more: bool, tracks: Vec<TrackSummary>) -> Self {
        Self {
            page,
            total,
            has_more,
            tracks,
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
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }
}

impl fmt::Debug for TrackSearchPage {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TrackSearchPage")
            .field("page", &self.page)
            .field("total", &self.total)
            .field("has_more", &self.has_more)
            .field("track_count", &self.tracks.len())
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
        AudioFormat, AudioQuality, PlaylistId, PlaylistSummary, PlaylistTracksPage, ProviderId,
        ResolvedMediaSource, ResolvedMediaSourceField, TrackId, TrackSearchPage, TrackSummary,
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
        let summary = TrackSummary::new(id, "Synthetic track", vec!["Artist one".into()])
            .expect("track summary")
            .with_subtitle(Some("Synthetic subtitle".into()))
            .with_album_title(Some("Synthetic album".into()))
            .with_artwork_uri(Some("https://example.invalid/album.jpg".into()))
            .with_duration_seconds(Some(245));

        assert_eq!(summary.id().provider().as_str(), "qq-music");
        assert_eq!(summary.id().opaque(), "track:41001:0:1:fixture-mid");
        assert_eq!(summary.title(), "Synthetic track");
        assert_eq!(summary.artist_names(), ["Artist one"]);
        assert_eq!(summary.album_title(), Some("Synthetic album"));
        assert_eq!(summary.duration_seconds(), Some(245));
        let debug = format!("{summary:?}");
        assert!(!debug.contains("Synthetic track"));
        assert!(!debug.contains("41001"));
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
        let page = TrackSearchPage::new(2, 45, true, vec![track]);

        assert_eq!(page.page(), 2);
        assert_eq!(page.total(), 45);
        assert!(page.has_more());
        assert_eq!(page.tracks().len(), 1);
        let debug = format!("{page:?}");
        assert!(!debug.contains("must-not-leak"));
        assert!(!debug.contains("private-artist"));
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
