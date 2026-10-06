//! Small memory-only source cache. Providers own session generations and locks;
//! this value does not own credentials, perform IO or serialize signed URLs.
use music_domain::{AudioQuality, ResolvedMediaSource, TrackId};
use std::{collections::VecDeque, fmt, time::Instant};

const CAPACITY: usize = 16;

struct Entry {
    preferred: AudioQuality,
    generation: u64,
    source: ResolvedMediaSource,
    expires: Instant,
}

#[derive(Default)]
pub struct MediaResolutionCache {
    entries: VecDeque<Entry>,
}

impl fmt::Debug for MediaResolutionCache {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("MediaResolutionCache")
            .field("entry_count", &self.entries.len())
            .finish()
    }
}

impl MediaResolutionCache {
    pub fn get(
        &mut self,
        track: &TrackId,
        preferred: AudioQuality,
        generation: u64,
        now: Instant,
    ) -> Option<ResolvedMediaSource> {
        self.entries
            .retain(|e| e.generation == generation && e.expires > now);
        let index = self.entries.iter().position(|e| {
            e.source.track_id() == track && e.preferred == preferred && e.generation == generation
        })?;
        let entry = self.entries.remove(index)?;
        let remaining = u32::try_from(entry.expires.duration_since(now).as_secs()).ok()?;
        if remaining == 0 {
            return None;
        }
        let source = ResolvedMediaSource::new(
            track.clone(),
            entry.source.uri().to_owned(),
            entry.source.format(),
            entry.source.quality(),
            remaining,
        )
        .ok()?;
        self.entries.push_back(entry);
        Some(source)
    }

    /// TTL starts before the request, conservatively accounting for transport
    /// latency. Never invent validity when the server did not supply it.
    pub fn insert(
        &mut self,
        source: ResolvedMediaSource,
        preferred: AudioQuality,
        generation: u64,
        request_started: Instant,
    ) {
        let Some(expires) = request_started.checked_add(std::time::Duration::from_secs(u64::from(
            source.valid_for_seconds(),
        ))) else {
            return;
        };
        self.entries.retain(|e| {
            e.generation == generation
                && !(e.preferred == preferred && e.source.track_id() == source.track_id())
        });
        while self.entries.len() >= CAPACITY {
            self.entries.pop_front();
        }
        self.entries.push_back(Entry {
            preferred,
            generation,
            source,
            expires,
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use music_domain::{AudioFormat, ProviderId};
    use std::time::Duration;
    fn source(provider: &str, opaque: &str) -> ResolvedMediaSource {
        ResolvedMediaSource::new(
            TrackId::new(ProviderId::new(provider).unwrap(), opaque).unwrap(),
            "https://audio.example.test/media?vkey=synthetic-secret",
            AudioFormat::Mp3,
            AudioQuality::Standard,
            10,
        )
        .unwrap()
    }
    #[test]
    fn ttl_generation_provider_and_preference_are_exact_and_debug_is_redacted() {
        let mut cache = MediaResolutionCache::default();
        let now = Instant::now();
        let qq = source("qq-music", "collision");
        let netease = source("netease-cloud-music", "collision");
        cache.insert(qq.clone(), AudioQuality::High, 10, now);
        assert!(
            cache
                .get(netease.track_id(), AudioQuality::High, 10, now)
                .is_none()
        );
        assert!(
            cache
                .get(qq.track_id(), AudioQuality::Standard, 10, now)
                .is_none()
        );
        let hit = cache
            .get(
                qq.track_id(),
                AudioQuality::High,
                10,
                now + Duration::from_secs(3),
            )
            .unwrap();
        assert_eq!(hit.valid_for_seconds(), 7);
        assert_eq!(hit.quality(), AudioQuality::Standard);
        assert!(!format!("{cache:?}").contains("synthetic-secret"));
        assert!(
            cache
                .get(qq.track_id(), AudioQuality::High, 11, now)
                .is_none()
        );
        cache.insert(qq.clone(), AudioQuality::High, 11, now);
        assert!(
            cache
                .get(
                    qq.track_id(),
                    AudioQuality::High,
                    11,
                    now + Duration::from_secs(10)
                )
                .is_none()
        );
    }
    #[test]
    fn capacity_and_lru_are_bounded() {
        let now = Instant::now();
        let mut cache = MediaResolutionCache::default();
        for id in 0..CAPACITY {
            cache.insert(
                source("qq-music", &id.to_string()),
                AudioQuality::Standard,
                1,
                now,
            );
        }
        let first = source("qq-music", "0");
        assert!(
            cache
                .get(first.track_id(), AudioQuality::Standard, 1, now)
                .is_some()
        );
        cache.insert(source("qq-music", "extra"), AudioQuality::Standard, 1, now);
        assert_eq!(cache.entries.len(), CAPACITY);
        assert!(
            cache
                .get(
                    source("qq-music", "1").track_id(),
                    AudioQuality::Standard,
                    1,
                    now
                )
                .is_none()
        );
        assert!(
            cache
                .get(first.track_id(), AudioQuality::Standard, 1, now)
                .is_some()
        );
    }
}
