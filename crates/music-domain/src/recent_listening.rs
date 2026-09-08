use crate::{TrackId, TrackSummary};

/// Session-local recommendation context, separate from queue intent. Only
/// observed playback counts; seek jumps, buffering and merely selecting a row
/// cannot qualify a track. Nothing here persists or reports listening upstream.
#[derive(Default)]
pub struct RecentListening {
    tracks: Vec<TrackSummary>,
    sample: Option<(TrackId, u64, u64, bool)>,
    listened_ms: u64,
    qualified: bool,
    previous_seed: Option<TrackId>,
}

impl RecentListening {
    pub fn observe(
        &mut self,
        track: Option<TrackSummary>,
        position_ms: u64,
        playing: bool,
        now_ms: u64,
    ) {
        let Some(track) = track else {
            self.sample = None;
            self.listened_ms = 0;
            self.qualified = false;
            return;
        };
        let same = self
            .sample
            .as_ref()
            .is_some_and(|sample| sample.0 == *track.id());
        if !same {
            self.listened_ms = 0;
            self.qualified = false;
        } else if let Some((_, previous_position, previous_time, was_playing)) = &self.sample {
            let elapsed = now_ms.saturating_sub(*previous_time);
            let advanced = position_ms.saturating_sub(*previous_position);
            if playing && *was_playing && elapsed <= 5_000 && advanced <= elapsed + 1_000 {
                self.listened_ms += advanced.min(elapsed);
            }
        }
        self.sample = Some((track.id().clone(), position_ms, now_ms, playing));
        let threshold = track.duration_seconds().map_or(30_000, |seconds| {
            (u64::from(seconds) * 500).clamp(1_000, 30_000)
        });
        if !self.qualified && self.listened_ms >= threshold {
            self.qualified = true;
            self.tracks.retain(|item| item.id() != track.id());
            self.tracks.insert(0, track);
            self.tracks.truncate(30);
        }
    }

    /// Recency-weighted choice, avoiding the previous seed and active track
    /// when alternatives exist. Entropy is supplied by the platform adapter.
    pub fn choose(&mut self, entropy: u64) -> Option<TrackSummary> {
        let current = self.sample.as_ref().map(|sample| &sample.0);
        let mut candidates: Vec<_> = self
            .tracks
            .iter()
            .enumerate()
            .filter(|(_, track)| {
                Some(track.id()) != self.previous_seed.as_ref() && Some(track.id()) != current
            })
            .collect();
        if candidates.is_empty() {
            candidates = self
                .tracks
                .iter()
                .enumerate()
                .filter(|(_, track)| Some(track.id()) != self.previous_seed.as_ref())
                .collect();
        }
        if candidates.is_empty() {
            candidates = self.tracks.iter().enumerate().collect();
        }
        let total: usize = candidates
            .iter()
            .map(|(index, _)| self.tracks.len() - index)
            .sum();
        if total == 0 {
            return None;
        }
        let mut draw = usize::try_from(entropy % total as u64).ok()?;
        for (index, track) in candidates {
            let weight = self.tracks.len() - index;
            if draw < weight {
                self.previous_seed = Some(track.id().clone());
                return Some(track.clone());
            }
            draw -= weight;
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ProviderId;

    fn track(id: &str) -> TrackSummary {
        TrackSummary::new(
            TrackId::new(ProviderId::new("fixture").unwrap(), id).unwrap(),
            "Private title",
            vec![],
        )
        .unwrap()
    }
    fn listen(context: &mut RecentListening, id: &str, start: u64) {
        for second in 0..=31 {
            context.observe(Some(track(id)), second * 1000, true, start + second * 1000);
        }
    }
    #[test]
    fn selection_pause_seek_and_buffering_do_not_qualify() {
        let mut context = RecentListening::default();
        context.observe(Some(track("a")), 0, true, 0);
        context.observe(Some(track("a")), 180_000, true, 1000);
        for second in 2..40 {
            context.observe(Some(track("a")), 180_000, false, second * 1000);
        }
        assert!(context.choose(0).is_none());
        for second in 40..80 {
            context.observe(Some(track("a")), 180_000, true, second * 1000);
        }
        assert!(context.choose(0).is_none());
    }
    #[test]
    fn history_survives_queue_clear_and_avoids_current_and_previous() {
        let mut context = RecentListening::default();
        listen(&mut context, "a", 0);
        listen(&mut context, "b", 40_000);
        listen(&mut context, "c", 80_000);
        assert_ne!(context.choose(0).unwrap().id(), track("c").id());
        let first = context.previous_seed.clone();
        assert_ne!(Some(context.choose(0).unwrap().id()), first.as_ref());
        context.observe(None, 0, false, 120_000);
        assert!(context.choose(4).is_some());
        assert!(RecentListening::default().choose(4).is_none());
    }
    #[test]
    fn history_is_bounded_and_deduplicated() {
        let mut context = RecentListening::default();
        for index in 0..40 {
            listen(&mut context, &index.to_string(), index * 40_000);
        }
        assert_eq!(context.tracks.len(), 30);
        listen(&mut context, "20", 2_000_000);
        assert_eq!(context.tracks.len(), 30);
        assert_eq!(context.tracks[0].id(), track("20").id());
    }
    #[test]
    fn short_tracks_qualify_after_half_and_partial_tracks_do_not_combine() {
        let mut context = RecentListening::default();
        for second in 0..=5 {
            context.observe(
                Some(track("short").with_duration_seconds(Some(10))),
                second * 1000,
                true,
                second * 1000,
            );
        }
        assert!(context.choose(0).is_some());
        let mut context = RecentListening::default();
        for second in 0..20 {
            context.observe(Some(track("a")), second * 1000, true, second * 1000);
        }
        for second in 0..20 {
            context.observe(
                Some(track("b")),
                second * 1000,
                true,
                20_000 + second * 1000,
            );
        }
        assert!(context.choose(0).is_none());
    }
}
