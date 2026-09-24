use super::library::{LibraryTrackSummary, bridge_track_summary, domain_track_summary};
use music_domain::RecentListening;
use std::sync::Mutex;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// Owned by one signed-in/signed-out Shell lifetime, never global or persisted.
#[flutter_rust_bridge::frb(opaque)]
pub struct RecentListeningHandle {
    context: Mutex<RecentListening>,
    started: Instant,
}

#[flutter_rust_bridge::frb(sync)]
pub fn create_recent_listening() -> RecentListeningHandle {
    RecentListeningHandle {
        context: Mutex::new(RecentListening::default()),
        started: Instant::now(),
    }
}

impl RecentListeningHandle {
    #[flutter_rust_bridge::frb(sync)]
    pub fn observe(&self, track: Option<LibraryTrackSummary>, position_ms: u32, playing: bool) {
        let track = match track.map(domain_track_summary).transpose() {
            Ok(track) => track,
            Err(()) => return,
        };
        if let Ok(mut context) = self.context.lock() {
            context.observe(
                track,
                u64::from(position_ms),
                playing,
                u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX),
            );
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn choose(&self) -> Option<LibraryTrackSummary> {
        let entropy = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |time| u64::from(time.subsec_nanos()));
        self.context
            .lock()
            .ok()?
            .choose(entropy)
            .as_ref()
            .map(bridge_track_summary)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use music_domain::{ProviderId, TrackId, TrackSummary};

    #[test]
    fn handles_are_isolated_and_chosen_summaries_preserve_safe_metadata() {
        let handle = create_recent_listening();
        let track = TrackSummary::new(
            TrackId::new(ProviderId::new("qq-music").unwrap(), "private-id").unwrap(),
            "Private title",
            vec!["Private artist".to_owned()],
        )
        .unwrap();
        for second in 0..=31 {
            handle.context.lock().unwrap().observe(
                Some(track.clone()),
                second * 1_000,
                true,
                second * 1_000,
            );
        }
        let chosen = handle.choose().unwrap();
        assert_eq!(chosen.opaque_id, "private-id");
        assert_eq!(chosen.title, "Private title");
        assert_eq!(chosen.artist_names, vec!["Private artist"]);
        assert!(!format!("{chosen:?}").contains("Private"));
        handle.observe(None, 0, false);
        assert!(handle.choose().is_some());
        assert!(create_recent_listening().choose().is_none());
    }

    #[test]
    fn invalid_or_merely_selected_tracks_do_not_create_history() {
        let handle = create_recent_listening();
        let track = LibraryTrackSummary {
            provider_id: "qq-music".to_owned(),
            opaque_id: String::new(),
            membership_opaque_id: None,
            title: "Private title".to_owned(),
            subtitle: None,
            artist_names: vec![],
            artists: vec![],
            album_title: None,
            album: None,
            artwork_uri: None,
            duration_seconds: None,
        };
        handle.observe(Some(track), 40_000, true);
        assert!(handle.choose().is_none());
    }
}
