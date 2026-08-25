use std::fmt;

use crate::TrackSummary;

/// Provider-neutral ordered playback intent.
///
/// Queue entries are position-based and deliberately retain duplicate track
/// identities: the same track may be intentionally queued more than once.
/// Provider fetching, media resolution, plugin lifecycle, repeat/shuffle, and
/// presentation state are outside this model.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlaybackQueue {
    tracks: Vec<TrackSummary>,
    current_index: Option<usize>,
}

impl PlaybackQueue {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            tracks: Vec::new(),
            current_index: None,
        }
    }

    /// Builds a queue whose current position is explicit.
    ///
    /// # Errors
    ///
    /// A non-empty queue requires an in-range current index. An empty queue
    /// requires `None`.
    pub fn try_new(
        tracks: Vec<TrackSummary>,
        current_index: Option<usize>,
    ) -> Result<Self, InvalidPlaybackQueue> {
        validate_position(tracks.len(), current_index)?;
        Ok(Self {
            tracks,
            current_index,
        })
    }

    /// Replaces the complete ordered queue atomically.
    ///
    /// Validation happens before mutation, so an invalid replacement leaves
    /// the existing queue unchanged.
    ///
    /// # Errors
    ///
    /// A non-empty queue requires an in-range current index. An empty queue
    /// requires `None`.
    pub fn replace(
        &mut self,
        tracks: Vec<TrackSummary>,
        current_index: Option<usize>,
    ) -> Result<(), InvalidPlaybackQueue> {
        validate_position(tracks.len(), current_index)?;
        self.tracks = tracks;
        self.current_index = current_index;
        Ok(())
    }

    #[must_use]
    pub fn tracks(&self) -> &[TrackSummary] {
        &self.tracks
    }

    #[must_use]
    pub const fn current_index(&self) -> Option<usize> {
        self.current_index
    }

    #[must_use]
    pub fn current(&self) -> Option<&TrackSummary> {
        self.current_index.map(|index| &self.tracks[index])
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.tracks.is_empty()
    }

    #[must_use]
    pub const fn len(&self) -> usize {
        self.tracks.len()
    }

    #[must_use]
    pub fn has_previous(&self) -> bool {
        self.current_index.is_some_and(|index| index > 0)
    }

    #[must_use]
    pub fn has_next(&self) -> bool {
        self.current_index
            .is_some_and(|index| index + 1 < self.tracks.len())
    }

    /// Selects an exact queue position and returns whether it changed.
    ///
    /// # Errors
    ///
    /// Returns [`InvalidPlaybackQueue::CurrentOutOfBounds`] when `index` is
    /// outside the current queue.
    pub fn select(&mut self, index: usize) -> Result<bool, InvalidPlaybackQueue> {
        if index >= self.tracks.len() {
            return Err(InvalidPlaybackQueue::CurrentOutOfBounds {
                index,
                len: self.tracks.len(),
            });
        }
        let changed = self.current_index != Some(index);
        self.current_index = Some(index);
        Ok(changed)
    }

    /// Moves to the next position. The terminal current item stays selected
    /// when no next item exists.
    pub fn advance(&mut self) -> bool {
        if !self.has_next() {
            return false;
        }
        self.current_index = self.current_index.map(|index| index + 1);
        true
    }

    /// Moves to the previous position. The first current item stays selected
    /// when no previous item exists.
    pub fn rewind(&mut self) -> bool {
        if !self.has_previous() {
            return false;
        }
        self.current_index = self.current_index.map(|index| index - 1);
        true
    }

    /// Applies the M1 terminal behavior: advance once when possible, otherwise
    /// leave the finished item selected.
    pub fn complete_current(&mut self) -> bool {
        self.advance()
    }

    /// Appends one positional entry. The first appended entry becomes current.
    /// Returns whether this operation established the current item.
    pub fn push(&mut self, track: TrackSummary) -> bool {
        let became_current = self.current_index.is_none();
        self.tracks.push(track);
        if became_current {
            self.current_index = Some(0);
        }
        became_current
    }

    /// Removes one exact position.
    ///
    /// Removing the current item selects its successor when present, otherwise
    /// its predecessor. Removing the final entry empties the queue. Removing a
    /// preceding item shifts the current index while retaining the same track.
    pub fn remove(&mut self, index: usize) -> Option<PlaybackQueueRemoval> {
        if index >= self.tracks.len() {
            return None;
        }

        let removed_current = self.current_index == Some(index);
        let track = self.tracks.remove(index);
        self.current_index = if self.tracks.is_empty() {
            None
        } else {
            // The public constructors and mutators maintain this invariant.
            // The fallback keeps this operation total even if a future
            // internal change violates it.
            let current = self.current_index.unwrap_or_default();
            Some(if index < current {
                current - 1
            } else if index > current {
                current
            } else if index < self.tracks.len() {
                index
            } else {
                self.tracks.len() - 1
            })
        };

        Some(PlaybackQueueRemoval {
            track,
            removed_current,
        })
    }

    pub fn clear(&mut self) {
        self.tracks.clear();
        self.current_index = None;
    }
}

impl Default for PlaybackQueue {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlaybackQueueRemoval {
    track: TrackSummary,
    removed_current: bool,
}

impl PlaybackQueueRemoval {
    #[must_use]
    pub const fn track(&self) -> &TrackSummary {
        &self.track
    }

    #[must_use]
    pub const fn removed_current(&self) -> bool {
        self.removed_current
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InvalidPlaybackQueue {
    MissingCurrent,
    UnexpectedCurrent { index: usize },
    CurrentOutOfBounds { index: usize, len: usize },
}

impl fmt::Display for InvalidPlaybackQueue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingCurrent => {
                formatter.write_str("a non-empty playback queue requires a current position")
            }
            Self::UnexpectedCurrent { index } => write!(
                formatter,
                "an empty playback queue cannot select position {index}"
            ),
            Self::CurrentOutOfBounds { index, len } => write!(
                formatter,
                "playback queue position {index} is outside {len} entries"
            ),
        }
    }
}

impl std::error::Error for InvalidPlaybackQueue {}

fn validate_position(len: usize, current_index: Option<usize>) -> Result<(), InvalidPlaybackQueue> {
    match (len, current_index) {
        (0, None) => Ok(()),
        (0, Some(index)) => Err(InvalidPlaybackQueue::UnexpectedCurrent { index }),
        (_, None) => Err(InvalidPlaybackQueue::MissingCurrent),
        (_, Some(index)) if index >= len => {
            Err(InvalidPlaybackQueue::CurrentOutOfBounds { index, len })
        }
        (_, Some(_)) => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::{InvalidPlaybackQueue, PlaybackQueue};
    use crate::{ProviderId, TrackId, TrackSummary};

    #[test]
    fn replacement_requires_one_valid_current_position_and_is_atomic() {
        let mut queue = PlaybackQueue::try_new(vec![track("one")], Some(0)).expect("queue");

        assert_eq!(
            PlaybackQueue::try_new(vec![track("one")], None),
            Err(InvalidPlaybackQueue::MissingCurrent)
        );
        assert_eq!(
            PlaybackQueue::try_new(Vec::new(), Some(0)),
            Err(InvalidPlaybackQueue::UnexpectedCurrent { index: 0 })
        );
        assert_eq!(
            queue.replace(vec![track("two")], Some(1)),
            Err(InvalidPlaybackQueue::CurrentOutOfBounds { index: 1, len: 1 })
        );
        assert_eq!(queue.current().expect("current").title(), "one");
    }

    #[test]
    fn replacement_preserves_order_and_duplicate_track_entries() {
        let duplicate = track("same");
        let queue =
            PlaybackQueue::try_new(vec![duplicate.clone(), track("middle"), duplicate], Some(2))
                .expect("queue");

        assert_eq!(queue.len(), 3);
        assert_eq!(queue.current_index(), Some(2));
        assert_eq!(queue.tracks()[0].id(), queue.tracks()[2].id());
    }

    #[test]
    fn navigation_and_completion_are_bounded_and_deterministic() {
        let mut queue =
            PlaybackQueue::try_new(vec![track("one"), track("two"), track("three")], Some(1))
                .expect("queue");

        assert!(queue.rewind());
        assert!(!queue.rewind());
        assert_eq!(queue.current().expect("current").title(), "one");
        assert!(queue.advance());
        assert!(queue.complete_current());
        assert!(!queue.complete_current());
        assert_eq!(queue.current().expect("current").title(), "three");
    }

    #[test]
    fn exact_selection_reports_changes_and_rejects_invalid_positions() {
        let mut queue =
            PlaybackQueue::try_new(vec![track("one"), track("two")], Some(0)).expect("queue");

        assert!(!queue.select(0).expect("same position"));
        assert!(queue.select(1).expect("changed position"));
        assert_eq!(
            queue.select(2),
            Err(InvalidPlaybackQueue::CurrentOutOfBounds { index: 2, len: 2 })
        );
        assert_eq!(queue.current_index(), Some(1));
    }

    #[test]
    fn removal_retains_or_replaces_current_by_position() {
        let mut queue = PlaybackQueue::try_new(
            vec![track("one"), track("two"), track("three"), track("four")],
            Some(2),
        )
        .expect("queue");

        let before = queue.remove(0).expect("remove before");
        assert!(!before.removed_current());
        assert_eq!(queue.current_index(), Some(1));
        assert_eq!(queue.current().expect("current").title(), "three");

        let after = queue.remove(2).expect("remove after");
        assert!(!after.removed_current());
        assert_eq!(queue.current().expect("current").title(), "three");

        let current = queue.remove(1).expect("remove current");
        assert!(current.removed_current());
        assert_eq!(current.track().title(), "three");
        assert_eq!(queue.current().expect("current").title(), "two");
    }

    #[test]
    fn current_removal_prefers_successor_then_predecessor_and_can_empty() {
        let mut queue =
            PlaybackQueue::try_new(vec![track("one"), track("two"), track("three")], Some(1))
                .expect("queue");

        assert!(queue.remove(1).expect("middle").removed_current());
        assert_eq!(queue.current().expect("successor").title(), "three");
        assert!(queue.remove(1).expect("last").removed_current());
        assert_eq!(queue.current().expect("predecessor").title(), "one");
        assert!(queue.remove(0).expect("only").removed_current());
        assert!(queue.is_empty());
        assert_eq!(queue.current(), None);
        assert_eq!(queue.remove(0), None);
    }

    #[test]
    fn pushing_into_empty_establishes_current_and_clear_resets_everything() {
        let mut queue = PlaybackQueue::new();

        assert!(queue.push(track("one")));
        assert!(!queue.push(track("one")));
        assert_eq!(queue.len(), 2);
        assert_eq!(queue.current_index(), Some(0));
        queue.clear();
        assert!(queue.is_empty());
        assert_eq!(queue.current_index(), None);
    }

    fn track(value: &str) -> TrackSummary {
        let provider = ProviderId::new("qq-music").expect("provider");
        let id = TrackId::new(provider, format!("track:{value}")).expect("track ID");
        TrackSummary::new(id, value, vec!["Fixture artist".into()]).expect("track")
    }
}
