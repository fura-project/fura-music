use std::collections::HashMap;
use std::fmt;

/// One already provider-normalized auxiliary lyric row.
///
/// Parsers and provider-specific placeholders remain outside this shared
/// helper. The helper sees only the upstream track identity (translation or
/// romanization is chosen by the caller), timing, and normalized text needed
/// to identify safe duplicate rows.
#[derive(Clone, Copy)]
pub struct AuxiliaryLyricLine<'a> {
    start_ms: u32,
    text: &'a str,
}

impl<'a> AuxiliaryLyricLine<'a> {
    #[must_use]
    pub const fn new(start_ms: u32, text: &'a str) -> Self {
        Self { start_ms, text }
    }

    #[must_use]
    pub const fn start_ms(self) -> u32 {
        self.start_ms
    }
}

impl fmt::Debug for AuxiliaryLyricLine<'_> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("AuxiliaryLyricLine")
            .field("start_ms", &self.start_ms)
            .field("text", &"[REDACTED]")
            .finish()
    }
}

/// Content-free alignment counters suitable for opt-in diagnostics.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct LyricAuxiliaryAlignmentStats {
    pub exact_matches: u32,
    pub near_matches: u32,
    pub ambiguous_rows: u32,
    pub unmatched_rows: u32,
    pub deduplicated_rows: u32,
    /// Nearest-original delta buckets: 0, 1-20, 21-100, 101-250, 251-500,
    /// and greater than 500 milliseconds.
    pub nearest_delta_buckets: [u32; 6],
}

/// One-to-one assignments from original-row indexes to indexes in the caller's
/// normalized auxiliary slice.
#[derive(Clone, Eq, PartialEq)]
pub struct LyricAuxiliaryAlignment {
    assignments: Vec<Option<usize>>,
    stats: LyricAuxiliaryAlignmentStats,
}

impl LyricAuxiliaryAlignment {
    #[must_use]
    pub fn auxiliary_index_for_original(&self, original_index: usize) -> Option<usize> {
        self.assignments.get(original_index).copied().flatten()
    }

    #[must_use]
    pub const fn stats(&self) -> LyricAuxiliaryAlignmentStats {
        self.stats
    }
}

impl fmt::Debug for LyricAuxiliaryAlignment {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LyricAuxiliaryAlignment")
            .field("original_line_count", &self.assignments.len())
            .field(
                "assigned_line_count",
                &self
                    .assignments
                    .iter()
                    .filter(|value| value.is_some())
                    .count(),
            )
            .field("stats", &self.stats)
            .finish()
    }
}

#[derive(Clone)]
struct AuxiliaryGroup {
    start_ms: u32,
    source_index: usize,
    source_row_count: u32,
    conflicting: bool,
    matched: bool,
    ambiguous: bool,
}

/// Aligns a provider-normalized auxiliary lyric track to original line starts.
///
/// Exact timestamps are assigned first. Remaining rows are considered only
/// inside the caller-provided tolerance and inside the exact-match boundaries
/// on both sides. A near pair is accepted only when the original and auxiliary
/// row are each other's unique nearest candidate. This makes the result
/// bounded, monotonic, one-to-one, and ambiguity-safe without moving original
/// timing.
#[must_use]
pub fn align_auxiliary_lyric_track(
    original_starts: &[u32],
    auxiliary: &[AuxiliaryLyricLine<'_>],
    tolerance_ms: u32,
) -> LyricAuxiliaryAlignment {
    let mut assignments = vec![None; original_starts.len()];
    let mut stats = LyricAuxiliaryAlignmentStats::default();
    let mut groups = group_auxiliary_rows(auxiliary, &mut stats);
    populate_delta_buckets(original_starts, &groups, &mut stats);

    let mut originals_by_start = HashMap::<u32, Vec<usize>>::new();
    for (index, start_ms) in original_starts.iter().copied().enumerate() {
        originals_by_start.entry(start_ms).or_default().push(index);
    }

    let mut exact_anchors = Vec::new();
    for (group_index, group) in groups.iter_mut().enumerate() {
        if group.conflicting {
            group.ambiguous = true;
            continue;
        }
        let Some(original_indexes) = originals_by_start.get(&group.start_ms) else {
            continue;
        };
        if let [original_index] = original_indexes.as_slice() {
            assignments[*original_index] = Some(group.source_index);
            group.matched = true;
            stats.exact_matches = stats.exact_matches.saturating_add(1);
            exact_anchors.push((*original_index, group_index));
        } else {
            group.ambiguous = true;
        }
    }
    exact_anchors.sort_unstable_by_key(|(original_index, _)| *original_index);

    let anchors_are_monotonic = exact_anchors.windows(2).all(|pair| pair[0].1 < pair[1].1);
    if anchors_are_monotonic {
        align_near_segments(
            original_starts,
            &mut groups,
            &mut assignments,
            &exact_anchors,
            tolerance_ms,
            &mut stats,
        );
    } else {
        // Exact identity remains trustworthy, but a non-monotonic original
        // document provides no safe boundary for approximate attachment.
        for group in &mut groups {
            if !group.matched && !group.conflicting {
                group.ambiguous = true;
            }
        }
    }

    for group in groups {
        if group.ambiguous {
            stats.ambiguous_rows = stats.ambiguous_rows.saturating_add(group.source_row_count);
        } else if !group.matched {
            stats.unmatched_rows = stats.unmatched_rows.saturating_add(group.source_row_count);
        }
    }

    LyricAuxiliaryAlignment { assignments, stats }
}

fn group_auxiliary_rows(
    auxiliary: &[AuxiliaryLyricLine<'_>],
    stats: &mut LyricAuxiliaryAlignmentStats,
) -> Vec<AuxiliaryGroup> {
    let mut indexes = (0..auxiliary.len()).collect::<Vec<_>>();
    indexes.sort_unstable_by_key(|index| (auxiliary[*index].start_ms, *index));
    let mut groups = Vec::new();
    let mut cursor = 0;
    while cursor < indexes.len() {
        let source_index = indexes[cursor];
        let start_ms = auxiliary[source_index].start_ms;
        let text = auxiliary[source_index].text;
        let mut end = cursor + 1;
        let mut conflicting = false;
        while end < indexes.len() && auxiliary[indexes[end]].start_ms == start_ms {
            conflicting |= auxiliary[indexes[end]].text != text;
            end += 1;
        }
        let source_row_count = u32::try_from(end - cursor).unwrap_or(u32::MAX);
        if !conflicting {
            stats.deduplicated_rows = stats
                .deduplicated_rows
                .saturating_add(source_row_count.saturating_sub(1));
        }
        groups.push(AuxiliaryGroup {
            start_ms,
            source_index,
            source_row_count,
            conflicting,
            matched: false,
            ambiguous: false,
        });
        cursor = end;
    }
    groups
}

fn populate_delta_buckets(
    original_starts: &[u32],
    groups: &[AuxiliaryGroup],
    stats: &mut LyricAuxiliaryAlignmentStats,
) {
    if original_starts.is_empty() {
        return;
    }
    let mut sorted_originals = original_starts.to_vec();
    sorted_originals.sort_unstable();
    for group in groups {
        let insertion = sorted_originals.partition_point(|start| *start < group.start_ms);
        let before = insertion
            .checked_sub(1)
            .map(|index| sorted_originals[index].abs_diff(group.start_ms));
        let after = sorted_originals
            .get(insertion)
            .map(|start| start.abs_diff(group.start_ms));
        let delta = match (before, after) {
            (Some(before), Some(after)) => before.min(after),
            (Some(delta), None) | (None, Some(delta)) => delta,
            (None, None) => continue,
        };
        let bucket = match delta {
            0 => 0,
            1..=20 => 1,
            21..=100 => 2,
            101..=250 => 3,
            251..=500 => 4,
            _ => 5,
        };
        stats.nearest_delta_buckets[bucket] = stats.nearest_delta_buckets[bucket].saturating_add(1);
    }
}

fn align_near_segments(
    original_starts: &[u32],
    groups: &mut [AuxiliaryGroup],
    assignments: &mut [Option<usize>],
    exact_anchors: &[(usize, usize)],
    tolerance_ms: u32,
    stats: &mut LyricAuxiliaryAlignmentStats,
) {
    let mut previous_original = None;
    let mut previous_group = None;
    for next_anchor in exact_anchors
        .iter()
        .copied()
        .map(Some)
        .chain(std::iter::once(None))
    {
        let original_start = previous_original.map_or(0, |index| index + 1);
        let original_end = next_anchor.map_or(original_starts.len(), |(index, _)| index);
        let group_start = previous_group.map_or(0, |index| index + 1);
        let group_end = next_anchor.map_or(groups.len(), |(_, index)| index);
        align_near_segment(
            original_starts,
            groups,
            assignments,
            original_start..original_end,
            group_start..group_end,
            tolerance_ms,
            stats,
        );
        if let Some((original_index, group_index)) = next_anchor {
            previous_original = Some(original_index);
            previous_group = Some(group_index);
        }
    }
}

fn align_near_segment(
    original_starts: &[u32],
    groups: &mut [AuxiliaryGroup],
    assignments: &mut [Option<usize>],
    original_range: std::ops::Range<usize>,
    group_range: std::ops::Range<usize>,
    tolerance_ms: u32,
    stats: &mut LyricAuxiliaryAlignmentStats,
) {
    if original_range.is_empty() || group_range.is_empty() {
        return;
    }
    if original_starts[original_range.clone()]
        .windows(2)
        .any(|pair| pair[0] > pair[1])
    {
        for group in &mut groups[group_range] {
            if !group.matched && !group.conflicting {
                group.ambiguous = true;
            }
        }
        return;
    }

    let mut original_choice = vec![None; original_range.len()];
    let mut original_tied = vec![false; original_range.len()];
    let mut auxiliary_choice = vec![None; group_range.len()];
    let mut auxiliary_tied = vec![false; group_range.len()];
    let mut auxiliary_has_candidate = vec![false; group_range.len()];

    for original_index in original_range.clone() {
        let start_ms = original_starts[original_index];
        let low = start_ms.saturating_sub(tolerance_ms);
        let high = start_ms.saturating_add(tolerance_ms);
        let candidate_start = groups[group_range.clone()]
            .partition_point(|group| group.start_ms < low)
            + group_range.start;
        let candidate_end = groups[group_range.clone()]
            .partition_point(|group| group.start_ms <= high)
            + group_range.start;
        let local_original = original_index - original_range.start;
        let mut best_original_delta = None;
        for group_index in candidate_start..candidate_end {
            let group = &groups[group_index];
            if group.matched || group.conflicting || group.ambiguous {
                continue;
            }
            let delta = start_ms.abs_diff(group.start_ms);
            auxiliary_has_candidate[group_index - group_range.start] = true;
            match best_original_delta {
                None => {
                    best_original_delta = Some(delta);
                    original_choice[local_original] = Some(group_index);
                }
                Some(best) if delta < best => {
                    best_original_delta = Some(delta);
                    original_choice[local_original] = Some(group_index);
                    original_tied[local_original] = false;
                }
                Some(best) if delta == best => {
                    original_choice[local_original] = None;
                    original_tied[local_original] = true;
                }
                Some(_) => {}
            }

            let local_group = group_index - group_range.start;
            match auxiliary_choice[local_group] {
                None if !auxiliary_tied[local_group] => {
                    auxiliary_choice[local_group] = Some((original_index, delta));
                }
                Some((_, best)) if delta < best => {
                    auxiliary_choice[local_group] = Some((original_index, delta));
                    auxiliary_tied[local_group] = false;
                }
                Some((_, best)) if delta == best => {
                    auxiliary_choice[local_group] = None;
                    auxiliary_tied[local_group] = true;
                }
                Some(_) | None => {}
            }
        }
    }

    let mut accepted = Vec::new();
    for original_index in original_range.clone() {
        let local_original = original_index - original_range.start;
        let Some(group_index) = original_choice[local_original] else {
            continue;
        };
        if original_tied[local_original] {
            continue;
        }
        let local_group = group_index - group_range.start;
        if auxiliary_tied[local_group]
            || auxiliary_choice[local_group].map(|(index, _)| index) != Some(original_index)
        {
            continue;
        }
        accepted.push((original_index, group_index));
    }
    finalize_near_candidates(
        groups,
        assignments,
        group_range.start,
        &auxiliary_has_candidate,
        accepted,
        stats,
    );
}

fn finalize_near_candidates(
    groups: &mut [AuxiliaryGroup],
    assignments: &mut [Option<usize>],
    group_start: usize,
    auxiliary_has_candidate: &[bool],
    accepted: Vec<(usize, usize)>,
    stats: &mut LyricAuxiliaryAlignmentStats,
) {
    if accepted.windows(2).all(|pair| pair[0].1 < pair[1].1) {
        for (original_index, group_index) in accepted {
            assignments[original_index] = Some(groups[group_index].source_index);
            groups[group_index].matched = true;
            stats.near_matches = stats.near_matches.saturating_add(1);
        }
    }
    for (local_group, has_candidate) in auxiliary_has_candidate.iter().copied().enumerate() {
        let group_index = group_start + local_group;
        if !groups[group_index].matched && has_candidate {
            groups[group_index].ambiguous = true;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{AuxiliaryLyricLine, align_auxiliary_lyric_track};

    fn line(start_ms: u32, text: &'static str) -> AuxiliaryLyricLine<'static> {
        AuxiliaryLyricLine::new(start_ms, text)
    }

    #[test]
    fn exact_and_small_delta_matches_are_one_to_one_and_monotonic() {
        let auxiliary = [
            line(1_000, "Translation A"),
            line(1_990, "Translation B"),
            line(3_010, "Translation C"),
        ];
        let alignment = align_auxiliary_lyric_track(&[1_000, 2_000, 3_000], &auxiliary, 10);

        assert_eq!(alignment.auxiliary_index_for_original(0), Some(0));
        assert_eq!(alignment.auxiliary_index_for_original(1), Some(1));
        assert_eq!(alignment.auxiliary_index_for_original(2), Some(2));
        assert_eq!(alignment.stats().exact_matches, 1);
        assert_eq!(alignment.stats().near_matches, 2);
        assert_eq!(alignment.stats().nearest_delta_buckets, [1, 2, 0, 0, 0, 0]);
    }

    #[test]
    fn equal_distance_and_conflicting_duplicates_are_not_guessed() {
        let tied = [line(990, "Translation A"), line(1_010, "Translation B")];
        let alignment = align_auxiliary_lyric_track(&[1_000], &tied, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), None);
        assert_eq!(alignment.stats().ambiguous_rows, 2);

        let conflicting = [line(1_000, "Translation A"), line(1_000, "Translation B")];
        let alignment = align_auxiliary_lyric_track(&[1_000], &conflicting, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), None);
        assert_eq!(alignment.stats().ambiguous_rows, 2);
    }

    #[test]
    fn identical_duplicates_collapse_but_near_competition_remains_ambiguous() {
        let duplicates = [line(1_000, "Translation A"), line(1_000, "Translation A")];
        let alignment = align_auxiliary_lyric_track(&[1_000], &duplicates, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), Some(0));
        assert_eq!(alignment.stats().deduplicated_rows, 1);

        let competing = [line(1_010, "Translation A")];
        let alignment = align_auxiliary_lyric_track(&[1_000, 1_020], &competing, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), None);
        assert_eq!(alignment.auxiliary_index_for_original(1), None);
        assert_eq!(alignment.stats().ambiguous_rows, 1);
    }

    #[test]
    fn exact_anchors_bound_near_matching_and_out_of_window_rows_stay_unmatched() {
        let auxiliary = [
            line(1_000, "Translation A"),
            line(1_995, "Translation B"),
            line(3_000, "Translation C"),
            line(4_011, "Translation D"),
        ];
        let alignment = align_auxiliary_lyric_track(&[1_000, 2_000, 3_000, 4_000], &auxiliary, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), Some(0));
        assert_eq!(alignment.auxiliary_index_for_original(1), Some(1));
        assert_eq!(alignment.auxiliary_index_for_original(2), Some(2));
        assert_eq!(alignment.auxiliary_index_for_original(3), None);
        assert_eq!(alignment.stats().unmatched_rows, 1);
    }

    #[test]
    fn non_monotonic_original_segment_refuses_approximate_crossing() {
        let auxiliary = [line(1_990, "Translation A"), line(3_010, "Translation B")];
        let alignment = align_auxiliary_lyric_track(&[3_000, 2_000], &auxiliary, 10);
        assert_eq!(alignment.auxiliary_index_for_original(0), None);
        assert_eq!(alignment.auxiliary_index_for_original(1), None);
        assert_eq!(alignment.stats().ambiguous_rows, 2);
    }

    #[test]
    fn empty_and_overflow_edge_inputs_do_not_panic() {
        let empty = align_auxiliary_lyric_track(&[1_000], &[], 10);
        assert_eq!(empty.auxiliary_index_for_original(0), None);
        assert_eq!(empty.stats().unmatched_rows, 0);

        let all_unmatched = align_auxiliary_lyric_track(&[1_000, 2_000], &[line(1_011, "A")], 10);
        assert_eq!(all_unmatched.auxiliary_index_for_original(0), None);
        assert_eq!(all_unmatched.auxiliary_index_for_original(1), None);
        assert_eq!(all_unmatched.stats().unmatched_rows, 1);

        let none = align_auxiliary_lyric_track(&[], &[line(u32::MAX, "A")], u32::MAX);
        assert_eq!(none.stats().unmatched_rows, 1);

        let edge =
            align_auxiliary_lyric_track(&[0, u32::MAX], &[line(0, "A"), line(u32::MAX, "B")], 10);
        assert_eq!(edge.stats().exact_matches, 2);
        assert!(!format!("{edge:?}").contains("Translation"));
    }
}
