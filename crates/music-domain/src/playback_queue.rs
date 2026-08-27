use std::fmt;

use crate::TrackSummary;

/// Provider-neutral ordered playback intent.
///
/// Queue entries are position-based and deliberately retain duplicate track
/// identities: the same track may be intentionally queued more than once.
/// Provider fetching, media resolution, plugin lifecycle, and presentation
/// state are outside this model. Playback order and repeat behavior live here
/// because they decide the authoritative next queue position.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlaybackQueue {
    tracks: Vec<TrackSummary>,
    current_index: Option<usize>,
    order: PlaybackOrder,
    repeat_mode: PlaybackRepeatMode,
    shuffle_order: Vec<usize>,
    shuffle_cursor: Option<usize>,
    shuffle_state: u64,
}

impl PlaybackQueue {
    #[must_use]
    pub fn new() -> Self {
        Self::with_shuffle_seed(DEFAULT_SHUFFLE_SEED)
    }

    /// Builds an empty queue with deterministic non-cryptographic shuffle
    /// entropy. Runtime adapters should supply process-local entropy; tests can
    /// supply a fixed seed.
    #[must_use]
    pub const fn with_shuffle_seed(shuffle_seed: u64) -> Self {
        Self {
            tracks: Vec::new(),
            current_index: None,
            order: PlaybackOrder::Sequential,
            repeat_mode: PlaybackRepeatMode::Off,
            shuffle_order: Vec::new(),
            shuffle_cursor: None,
            shuffle_state: normalize_shuffle_seed(shuffle_seed),
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
        let mut queue = Self::new();
        queue.tracks = tracks;
        queue.current_index = current_index;
        Ok(queue)
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
        self.rebuild_shuffle_cycle();
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
    pub const fn order(&self) -> PlaybackOrder {
        self.order
    }

    #[must_use]
    pub const fn repeat_mode(&self) -> PlaybackRepeatMode {
        self.repeat_mode
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
        let has_position = match self.order {
            PlaybackOrder::Sequential => self.current_index.is_some_and(|index| index > 0),
            PlaybackOrder::Shuffle => self.shuffle_cursor.is_some_and(|cursor| cursor > 0),
        };
        has_position || (self.repeat_mode == PlaybackRepeatMode::All && !self.is_empty())
    }

    #[must_use]
    pub fn has_next(&self) -> bool {
        let has_position = match self.order {
            PlaybackOrder::Sequential => self
                .current_index
                .is_some_and(|index| index + 1 < self.tracks.len()),
            PlaybackOrder::Shuffle => self
                .shuffle_cursor
                .is_some_and(|cursor| cursor + 1 < self.shuffle_order.len()),
        };
        has_position || (self.repeat_mode == PlaybackRepeatMode::All && !self.is_empty())
    }

    /// Changes traversal order without restarting or changing the current
    /// Track. Enabling shuffle starts a new cycle anchored at the current
    /// position; disabling it restores positional traversal.
    pub fn set_order(&mut self, order: PlaybackOrder) -> bool {
        if self.order == order {
            return false;
        }
        self.order = order;
        self.rebuild_shuffle_cycle();
        true
    }

    /// Changes completion/wrapping behavior without restarting or changing the
    /// current Track.
    pub fn set_repeat_mode(&mut self, repeat_mode: PlaybackRepeatMode) -> bool {
        if self.repeat_mode == repeat_mode {
            return false;
        }
        self.repeat_mode = repeat_mode;
        true
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
        if changed {
            self.rebuild_shuffle_cycle();
        }
        Ok(changed)
    }

    /// Moves to the next position in the active order. Repeat-all wraps; other
    /// repeat modes leave a terminal current item selected. The result says
    /// whether the playback owner should start the selected position, which is
    /// also true for a one-entry repeat-all wrap.
    pub fn advance(&mut self) -> bool {
        if self.is_empty() {
            return false;
        }
        match self.order {
            PlaybackOrder::Sequential => {
                let Some(current) = self.current_index else {
                    return false;
                };
                if current + 1 < self.tracks.len() {
                    self.current_index = Some(current + 1);
                    true
                } else if self.repeat_mode == PlaybackRepeatMode::All {
                    self.current_index = Some(0);
                    true
                } else {
                    false
                }
            }
            PlaybackOrder::Shuffle => self.advance_shuffle(),
        }
    }

    /// Moves to the previous position in the active order. Repeat-all wraps;
    /// other repeat modes leave the first active position selected.
    pub fn rewind(&mut self) -> bool {
        if self.is_empty() {
            return false;
        }
        match self.order {
            PlaybackOrder::Sequential => {
                let Some(current) = self.current_index else {
                    return false;
                };
                if current > 0 {
                    self.current_index = Some(current - 1);
                    true
                } else if self.repeat_mode == PlaybackRepeatMode::All {
                    self.current_index = Some(self.tracks.len() - 1);
                    true
                } else {
                    false
                }
            }
            PlaybackOrder::Shuffle => self.rewind_shuffle(),
        }
    }

    /// Applies automatic completion. Repeat-one requests replay of the same
    /// position; otherwise completion follows the active order and repeat-all
    /// wrapping rules.
    pub fn complete_current(&mut self) -> bool {
        if self.current_index.is_some() && self.repeat_mode == PlaybackRepeatMode::One {
            return true;
        }
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
        self.rebuild_shuffle_cycle();
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
        self.rebuild_shuffle_cycle();

        Some(PlaybackQueueRemoval {
            track,
            removed_current,
        })
    }

    pub fn clear(&mut self) {
        self.tracks.clear();
        self.current_index = None;
        self.shuffle_order.clear();
        self.shuffle_cursor = None;
    }

    fn advance_shuffle(&mut self) -> bool {
        let cursor = self
            .shuffle_cursor
            .expect("non-empty shuffled queue has a cursor");
        if cursor + 1 < self.shuffle_order.len() {
            let next = cursor + 1;
            self.shuffle_cursor = Some(next);
            self.current_index = Some(self.shuffle_order[next]);
            return true;
        }
        if self.repeat_mode != PlaybackRepeatMode::All {
            return false;
        }
        self.start_next_shuffle_cycle();
        true
    }

    fn rewind_shuffle(&mut self) -> bool {
        let cursor = self
            .shuffle_cursor
            .expect("non-empty shuffled queue has a cursor");
        if cursor > 0 {
            let previous = cursor - 1;
            self.shuffle_cursor = Some(previous);
            self.current_index = Some(self.shuffle_order[previous]);
            return true;
        }
        if self.repeat_mode != PlaybackRepeatMode::All {
            return false;
        }
        let previous = self.shuffle_order.len() - 1;
        self.shuffle_cursor = Some(previous);
        self.current_index = Some(self.shuffle_order[previous]);
        true
    }

    fn rebuild_shuffle_cycle(&mut self) {
        self.shuffle_order.clear();
        self.shuffle_cursor = None;
        if self.order != PlaybackOrder::Shuffle {
            return;
        }
        let Some(current) = self.current_index else {
            return;
        };
        self.shuffle_order = (0..self.tracks.len())
            .filter(|index| *index != current)
            .collect();
        self.shuffle_positions();
        self.shuffle_order.insert(0, current);
        self.shuffle_cursor = Some(0);
    }

    fn start_next_shuffle_cycle(&mut self) {
        let current = self.current_index.expect("non-empty queue has current");
        self.shuffle_order = (0..self.tracks.len()).collect();
        self.shuffle_positions();
        if self.shuffle_order.len() > 1 && self.shuffle_order[0] == current {
            self.shuffle_order.swap(0, 1);
        }
        self.shuffle_cursor = Some(0);
        self.current_index = self.shuffle_order.first().copied();
    }

    fn shuffle_positions(&mut self) {
        for upper in (2..=self.shuffle_order.len()).rev() {
            let upper_u64 = u64::try_from(upper).expect("queue length fits u64");
            let swap = usize::try_from(self.next_shuffle_u64() % upper_u64)
                .expect("shuffle remainder fits usize");
            self.shuffle_order.swap(upper - 1, swap);
        }
    }

    fn next_shuffle_u64(&mut self) -> u64 {
        self.shuffle_state = self.shuffle_state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut value = self.shuffle_state;
        value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        value ^ (value >> 31)
    }
}

impl Default for PlaybackQueue {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum PlaybackOrder {
    #[default]
    Sequential,
    Shuffle,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum PlaybackRepeatMode {
    #[default]
    Off,
    All,
    One,
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

const DEFAULT_SHUFFLE_SEED: u64 = 0x6a09_e667_f3bc_c909;

const fn normalize_shuffle_seed(seed: u64) -> u64 {
    if seed == 0 {
        DEFAULT_SHUFFLE_SEED
    } else {
        seed
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::{InvalidPlaybackQueue, PlaybackOrder, PlaybackQueue, PlaybackRepeatMode};
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

    #[test]
    fn repeat_modes_separate_completion_from_manual_navigation() {
        let mut queue =
            PlaybackQueue::try_new(vec![track("one"), track("two"), track("three")], Some(2))
                .expect("queue");

        assert!(queue.set_repeat_mode(PlaybackRepeatMode::One));
        assert!(queue.complete_current());
        assert_eq!(queue.current_index(), Some(2));
        assert!(!queue.advance());
        assert!(queue.rewind());
        assert_eq!(queue.current_index(), Some(1));

        assert!(queue.set_repeat_mode(PlaybackRepeatMode::All));
        assert!(queue.advance());
        assert_eq!(queue.current_index(), Some(2));
        assert!(queue.advance());
        assert_eq!(queue.current_index(), Some(0));
        assert!(queue.rewind());
        assert_eq!(queue.current_index(), Some(2));
        assert!(!queue.set_repeat_mode(PlaybackRepeatMode::All));
    }

    #[test]
    fn shuffle_visits_each_position_without_reordering_public_queue() {
        let mut queue = PlaybackQueue::with_shuffle_seed(7);
        queue
            .replace(
                vec![track("one"), track("two"), track("three"), track("four")],
                Some(1),
            )
            .expect("queue");
        let public_order = queue
            .tracks()
            .iter()
            .map(|track| track.title().to_owned())
            .collect::<Vec<_>>();

        assert!(queue.set_order(PlaybackOrder::Shuffle));
        assert_eq!(queue.current_index(), Some(1));
        assert_eq!(queue.order(), PlaybackOrder::Shuffle);
        assert!(!queue.has_previous());
        let mut visited = BTreeSet::from([queue.current_index().expect("current")]);
        while queue.advance() {
            assert!(visited.insert(queue.current_index().expect("current")));
        }

        assert_eq!(visited, BTreeSet::from([0, 1, 2, 3]));
        assert_eq!(
            queue
                .tracks()
                .iter()
                .map(|track| track.title().to_owned())
                .collect::<Vec<_>>(),
            public_order
        );
        assert!(!queue.has_next());
        assert!(queue.has_previous());
    }

    #[test]
    fn shuffled_repeat_all_starts_a_new_cycle_without_immediate_replay() {
        let mut queue = PlaybackQueue::with_shuffle_seed(11);
        queue
            .replace(vec![track("one"), track("two"), track("three")], Some(0))
            .expect("queue");
        queue.set_order(PlaybackOrder::Shuffle);
        queue.set_repeat_mode(PlaybackRepeatMode::All);

        assert!(queue.has_previous());
        assert!(queue.has_next());
        assert!(queue.advance());
        assert!(queue.advance());
        let last_cycle_position = queue.current_index();
        assert!(queue.advance());
        assert_ne!(queue.current_index(), last_cycle_position);
        assert!(queue.has_previous());
        assert!(queue.has_next());
    }

    #[test]
    fn shuffle_cycle_repairs_around_selection_and_membership_mutation() {
        let mut queue = PlaybackQueue::with_shuffle_seed(13);
        queue
            .replace(vec![track("one"), track("two"), track("three")], Some(0))
            .expect("queue");
        queue.set_order(PlaybackOrder::Shuffle);
        assert!(queue.advance());

        assert!(queue.select(2).expect("select"));
        assert_eq!(queue.current_index(), Some(2));
        assert!(!queue.has_previous());

        queue.push(track("four"));
        assert_eq!(queue.current_index(), Some(2));
        assert!(!queue.has_previous());
        assert_eq!(queue.tracks().len(), 4);

        let removed = queue.remove(2).expect("remove current");
        assert!(removed.removed_current());
        assert_eq!(queue.current_index(), Some(2));
        assert_eq!(queue.current().expect("replacement").title(), "four");
        assert!(!queue.has_previous());
    }

    #[test]
    fn mode_state_survives_clear_and_replacement_without_forcing_playback() {
        let mut queue = PlaybackQueue::with_shuffle_seed(17);
        assert!(queue.set_order(PlaybackOrder::Shuffle));
        assert!(queue.set_repeat_mode(PlaybackRepeatMode::All));
        queue.push(track("one"));
        assert!(queue.has_previous());
        assert!(queue.has_next());

        queue.clear();
        assert_eq!(queue.order(), PlaybackOrder::Shuffle);
        assert_eq!(queue.repeat_mode(), PlaybackRepeatMode::All);
        assert!(!queue.has_previous());
        assert!(!queue.has_next());

        queue
            .replace(vec![track("two")], Some(0))
            .expect("replacement");
        assert_eq!(queue.order(), PlaybackOrder::Shuffle);
        assert_eq!(queue.repeat_mode(), PlaybackRepeatMode::All);
        assert!(queue.has_previous());
        assert!(queue.has_next());
        assert!(queue.complete_current());
        assert_eq!(queue.current_index(), Some(0));
    }

    fn track(value: &str) -> TrackSummary {
        let provider = ProviderId::new("qq-music").expect("provider");
        let id = TrackId::new(provider, format!("track:{value}")).expect("track ID");
        TrackSummary::new(id, value, vec!["Fixture artist".into()]).expect("track")
    }
}
