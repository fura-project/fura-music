use std::fmt;
use std::sync::Mutex;

use music_domain::{InvalidPlaybackQueue, PlaybackQueue};

use super::library::{LibraryTrackSummary, bridge_track_summary, domain_track_summary};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PlaybackQueueFailure {
    InvalidTrack,
    InvalidPosition,
    CoreUnavailable,
}

#[derive(Clone, Eq, PartialEq)]
pub struct PlaybackQueueSnapshot {
    pub tracks: Vec<LibraryTrackSummary>,
    pub current_index: Option<u32>,
    pub has_previous: bool,
    pub has_next: bool,
}

impl fmt::Debug for PlaybackQueueSnapshot {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaybackQueueSnapshot")
            .field("track_count", &self.tracks.len())
            .field("current_index", &self.current_index)
            .field("has_previous", &self.has_previous)
            .field("has_next", &self.has_next)
            .finish()
    }
}

#[derive(Clone, Eq, PartialEq)]
pub struct PlaybackQueueUpdate {
    pub snapshot: Option<PlaybackQueueSnapshot>,
    pub current_changed: bool,
    pub failure: Option<PlaybackQueueFailure>,
}

impl fmt::Debug for PlaybackQueueUpdate {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaybackQueueUpdate")
            .field("has_snapshot", &self.snapshot.is_some())
            .field("current_changed", &self.current_changed)
            .field("failure", &self.failure)
            .finish()
    }
}

/// Dart-owned access to one in-process Domain queue. This handle only adapts
/// commands and snapshots; it contains no Provider, media, or UI lifecycle.
#[flutter_rust_bridge::frb(opaque)]
pub struct PlaybackQueueHandle {
    queue: Mutex<PlaybackQueue>,
}

impl fmt::Debug for PlaybackQueueHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("PlaybackQueueHandle")
            .finish_non_exhaustive()
    }
}

impl PlaybackQueueHandle {
    #[flutter_rust_bridge::frb(sync)]
    pub fn snapshot(&self) -> PlaybackQueueUpdate {
        self.with_queue(|_| Ok(false))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn replace(
        &self,
        tracks: Vec<LibraryTrackSummary>,
        current_index: Option<u32>,
    ) -> PlaybackQueueUpdate {
        let tracks = match tracks
            .into_iter()
            .map(domain_track_summary)
            .collect::<Result<Vec<_>, _>>()
        {
            Ok(tracks) => tracks,
            Err(()) => return failed(PlaybackQueueFailure::InvalidTrack),
        };
        let current_index = current_index.map(|index| index as usize);
        self.with_queue(move |queue| {
            let current_changed = !queue.is_empty() || !tracks.is_empty();
            queue
                .replace(tracks, current_index)
                .map_err(map_position_error)?;
            Ok(current_changed)
        })
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn push(&self, track: LibraryTrackSummary) -> PlaybackQueueUpdate {
        let track = match domain_track_summary(track) {
            Ok(track) => track,
            Err(()) => return failed(PlaybackQueueFailure::InvalidTrack),
        };
        self.with_queue(move |queue| Ok(queue.push(track)))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn select(&self, index: u32) -> PlaybackQueueUpdate {
        self.with_queue(|queue| queue.select(index as usize).map_err(map_position_error))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn advance(&self) -> PlaybackQueueUpdate {
        self.with_queue(|queue| Ok(queue.advance()))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn rewind(&self) -> PlaybackQueueUpdate {
        self.with_queue(|queue| Ok(queue.rewind()))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn complete_current(&self) -> PlaybackQueueUpdate {
        self.with_queue(|queue| Ok(queue.complete_current()))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn remove(&self, index: u32) -> PlaybackQueueUpdate {
        self.with_queue(|queue| {
            queue
                .remove(index as usize)
                .map(|removal| removal.removed_current())
                .ok_or(PlaybackQueueFailure::InvalidPosition)
        })
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn clear(&self) -> PlaybackQueueUpdate {
        self.with_queue(|queue| {
            let current_changed = !queue.is_empty();
            queue.clear();
            Ok(current_changed)
        })
    }

    fn with_queue(
        &self,
        operation: impl FnOnce(&mut PlaybackQueue) -> Result<bool, PlaybackQueueFailure>,
    ) -> PlaybackQueueUpdate {
        let Ok(mut queue) = self.queue.lock() else {
            return failed(PlaybackQueueFailure::CoreUnavailable);
        };
        match operation(&mut queue) {
            Ok(current_changed) => map_snapshot(&queue, current_changed),
            Err(failure) => failed(failure),
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn create_playback_queue() -> PlaybackQueueHandle {
    PlaybackQueueHandle {
        queue: Mutex::new(PlaybackQueue::new()),
    }
}

fn map_snapshot(queue: &PlaybackQueue, current_changed: bool) -> PlaybackQueueUpdate {
    let current_index = match queue.current_index().map(u32::try_from).transpose() {
        Ok(current_index) => current_index,
        Err(_) => return failed(PlaybackQueueFailure::CoreUnavailable),
    };
    PlaybackQueueUpdate {
        snapshot: Some(PlaybackQueueSnapshot {
            tracks: queue.tracks().iter().map(bridge_track_summary).collect(),
            current_index,
            has_previous: queue.has_previous(),
            has_next: queue.has_next(),
        }),
        current_changed,
        failure: None,
    }
}

const fn failed(failure: PlaybackQueueFailure) -> PlaybackQueueUpdate {
    PlaybackQueueUpdate {
        snapshot: None,
        current_changed: false,
        failure: Some(failure),
    }
}

const fn map_position_error(_: InvalidPlaybackQueue) -> PlaybackQueueFailure {
    PlaybackQueueFailure::InvalidPosition
}

#[cfg(test)]
mod tests {
    use super::{PlaybackQueueFailure, PlaybackQueueHandle, create_playback_queue};
    use crate::api::album::CatalogAlbumSummary;
    use crate::api::artist::CatalogArtistSummary;
    use crate::api::library::LibraryTrackSummary;

    #[test]
    fn maps_positional_duplicates_without_exposing_content_in_diagnostics() {
        let queue = create_playback_queue();
        let update = queue.replace(vec![track("same"), track("middle"), track("same")], Some(2));

        let snapshot = update.snapshot.expect("snapshot");
        assert_eq!(snapshot.tracks.len(), 3);
        assert_eq!(snapshot.current_index, Some(2));
        assert_eq!(snapshot.tracks[0].opaque_id, snapshot.tracks[2].opaque_id);
        assert_eq!(
            snapshot.tracks[0].artists[0].opaque_id,
            "artist:42001:private-mid"
        );
        assert_eq!(
            snapshot.tracks[0]
                .album
                .as_ref()
                .expect("Album context")
                .opaque_id,
            "album:43001:private-mid"
        );
        assert!(!format!("{snapshot:?}").contains("private-title"));
        assert!(!format!("{queue:?}").contains("same"));
    }

    #[test]
    fn forwards_navigation_selection_and_completion_to_domain() {
        let queue = queue_with_three();

        let selected = queue.select(1);
        assert!(selected.current_changed);
        assert!(selected.snapshot.expect("selected").has_previous);
        let advanced = queue.advance();
        assert!(advanced.current_changed);
        assert!(!advanced.snapshot.expect("advanced").has_next);
        let terminal = queue.complete_current();
        assert!(!terminal.current_changed);
        assert_eq!(terminal.snapshot.expect("terminal").current_index, Some(2));
        let rewound = queue.rewind();
        assert!(rewound.current_changed);
        assert_eq!(rewound.snapshot.expect("rewound").current_index, Some(1));
    }

    #[test]
    fn reports_current_removal_and_retains_exact_domain_semantics() {
        let queue = queue_with_three();
        queue.select(1);

        let removed = queue.remove(1);
        assert!(removed.current_changed);
        let snapshot = removed.snapshot.expect("removed");
        assert_eq!(snapshot.tracks.len(), 2);
        assert_eq!(snapshot.current_index, Some(1));
        assert_eq!(snapshot.tracks[1].opaque_id, "three");
    }

    #[test]
    fn invalid_track_or_position_is_typed_and_leaves_queue_unchanged() {
        let queue = queue_with_three();
        let invalid_track = LibraryTrackSummary {
            provider_id: "QQ Music".into(),
            ..track("invalid")
        };
        let invalid_album = LibraryTrackSummary {
            album: Some(CatalogAlbumSummary {
                provider_id: "qq-music".into(),
                opaque_id: String::new(),
                title: "private-album".into(),
                artwork_uri: None,
            }),
            ..track("invalid-album")
        };
        let foreign_album = LibraryTrackSummary {
            album: Some(CatalogAlbumSummary {
                provider_id: "local".into(),
                opaque_id: "album:foreign".into(),
                title: "private-album".into(),
                artwork_uri: None,
            }),
            ..track("foreign-album")
        };
        let foreign_artist = LibraryTrackSummary {
            artists: vec![CatalogArtistSummary {
                provider_id: "local".into(),
                opaque_id: "artist:foreign".into(),
                name: "private-artist".into(),
            }],
            ..track("foreign-artist")
        };

        assert_eq!(
            queue.push(invalid_track).failure,
            Some(PlaybackQueueFailure::InvalidTrack)
        );
        assert_eq!(
            queue.push(invalid_album).failure,
            Some(PlaybackQueueFailure::InvalidTrack)
        );
        assert_eq!(
            queue.push(foreign_album).failure,
            Some(PlaybackQueueFailure::InvalidTrack)
        );
        assert_eq!(
            queue.push(foreign_artist).failure,
            Some(PlaybackQueueFailure::InvalidTrack)
        );
        assert_eq!(
            queue.select(9).failure,
            Some(PlaybackQueueFailure::InvalidPosition)
        );
        assert_eq!(
            queue.remove(9).failure,
            Some(PlaybackQueueFailure::InvalidPosition)
        );
        assert_eq!(
            queue.snapshot().snapshot.expect("unchanged").tracks.len(),
            3
        );
    }

    #[test]
    fn first_push_and_clear_report_current_transition() {
        let queue = create_playback_queue();
        assert!(queue.push(track("one")).current_changed);
        assert!(!queue.push(track("two")).current_changed);
        let cleared = queue.clear();
        assert!(cleared.current_changed);
        assert!(cleared.snapshot.expect("cleared").tracks.is_empty());
    }

    fn queue_with_three() -> PlaybackQueueHandle {
        let queue = create_playback_queue();
        let update = queue.replace(vec![track("one"), track("two"), track("three")], Some(0));
        assert_eq!(update.failure, None);
        queue
    }

    fn track(value: &str) -> LibraryTrackSummary {
        LibraryTrackSummary {
            provider_id: "qq-music".into(),
            opaque_id: value.into(),
            title: "private-title".into(),
            subtitle: Some("private-subtitle".into()),
            artist_names: vec!["private-artist".into()],
            artists: vec![CatalogArtistSummary {
                provider_id: "qq-music".into(),
                opaque_id: "artist:42001:private-mid".into(),
                name: "private-artist".into(),
            }],
            album_title: Some("private-album".into()),
            album: Some(CatalogAlbumSummary {
                provider_id: "qq-music".into(),
                opaque_id: "album:43001:private-mid".into(),
                title: "private-album".into(),
                artwork_uri: Some("https://images.example.test/album.jpg".into()),
            }),
            artwork_uri: Some("https://images.example.test/private.jpg".into()),
            duration_seconds: Some(120),
        }
    }
}
