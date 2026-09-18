# Lyric auxiliary-track alignment (HD-034)

- **Date:** 2026-09-18
- **Scope:** QQ Music and NetEase original lyrics plus independent translation
  and romanization tracks; provider mapping and Flutter presentation only.
- **Evidence boundary:** no live provider request, stored credential, lyric body,
  Track identity, or copyrighted fixture was used in this pass.

## Evidence and field ownership

QQ's existing production request already asks for `trans` and `roma`, and its
bounded client already decodes original, translation, and romanization as
independent timed documents. The prior pinned-source audit is recorded in
[QQ Music lyric and QRC evidence](qqmusic-lyrics-evidence.md). It establishes
the track separation and line-timed auxiliary shape, but deliberately did not
authorize fuzzy alignment.

The Human report for HD-034 adds two content-free observations: a QQ
translation row may contain the exact trimmed placeholder `//`, and one
original/translation pair differed by 10 ms (72,780 ms versus 72,770 ms).
Those observations establish the placeholder category and the `1-20 ms`
delta category without retaining lyric text. They do not prove that every
unmatched line is upstream-present or that a wider window is safe.

For NetEase, the existing request already sends `tv=-1` and `rv=-1`. The
pinned [LDDC NetEase lyric implementation at `84631e8`](https://github.com/chenmozhijin/LDDC/blob/84631e8cd011fcc3f71ca0ae017e2c9758958ffc/LDDC/core/api/lyrics/ne.py)
independently maps `lrc` to original, `tlyric` to translation, and `romalrc`
to romanization while requesting both `tv` and `rv`. This corroborates the
field identity only; Fura retains its independently written request, parser,
bounds, errors, and Provider mapping. Track type is never inferred from script
or language.

## Normalization

QQ normalization is track-scoped:

- translation: trim surrounding whitespace, omit blank rows, and omit only an
  exact trimmed `//`;
- romanization: trim surrounding whitespace and omit blank rows, but preserve
  `//` because no evidence establishes it as a romanization placeholder;
- original: unchanged, including a literal original `//`;
- `/`, `///`, and embedded text such as `I // you`: preserved.

NetEase independently parses `lrc`, `tlyric`, and `romalrc`. Missing, null,
empty, locally malformed, or oversized auxiliary documents degrade only that
auxiliary track. Valid rows in a partly malformed optional document remain;
the required original document keeps the existing strict availability and
integrity boundary. QQ retains the same `TOLERANT_TEXT_DOCUMENT` behavior.

## Alignment policy

Both Providers call one small provider-neutral timed-track helper after their
own parsing and normalization. It never receives Provider identity and never
changes original line or word timing.

The current window is **10 ms**. This is intentionally the smallest window
that accepts the reported 10 ms category and is consistent with reconciling
one centisecond-sized auxiliary timestamp step against millisecond QRC timing.
It is not a general nearest-neighbor window and is not evidence for 20, 100,
250, 500, or 1,000 ms matching. A wider policy requires new sanitized
evidence and review.

The algorithm is deterministic:

1. Group auxiliary rows by timestamp. Identical normalized text at the same
   timestamp collapses to one row; conflicting text remains ambiguous.
2. Assign unique exact timestamp matches first.
3. Treat those exact matches as non-crossable segment boundaries.
4. Inside each remaining segment, consider only rows within 10 ms.
5. Accept a near pair only when original and auxiliary are each other's unique
   nearest candidate.
6. Reject equal-distance ties, competing rows, conflicting duplicates,
   non-monotonic/crossing candidates, and all out-of-window rows.
7. Assign an auxiliary row at most once and leave the original line intact
   whenever no safe assignment exists.

Translation and romanization are aligned independently. There is no array
position join, language detection, machine translation, or QQ/NetEase
cross-provider fallback. Original start/duration, segments, segment timing,
source ordering, seek targets, and active-line selection are unchanged.

## Diagnostics

`FURA_LYRIC_ALIGNMENT_DEBUG` is opt-in and initiates no request. For each
Provider and auxiliary kind it emits only:

- raw and normalized row counts;
- QQ translation placeholder omissions;
- exact, near, ambiguous, unmatched, and identical-deduplicated counts;
- nearest-original delta buckets: `0`, `1-20`, `21-100`, `101-250`,
  `251-500`, and `>500` ms.

It never emits lyric/translation/romanization text, title, Track identity,
account, credential, URL, Cookie, or raw response. Current test summaries are
synthetic; no real-song count is claimed by this checkpoint.

## Presentation contract

Flutter persists one provider-neutral global `LyricAuxiliaryMode` in Settings
schema 6. Existing schema 5 documents migrate to `auto` without changing
theme, color source, playback quality, Provider, or locale.

- **Auto:** translation for a line, otherwise romanization, otherwise original
  only.
- **Translation:** translation if present; never substitutes romanization.
- **Pronunciation:** romanization if present; never substitutes translation.
- **Off:** original only.

At most one auxiliary `Text` and semantics node is built per original line.
The preference remains stable when the current Track lacks that track; menu
choices may be disabled but Settings are not rewritten. Switching is local
presentation state and makes no lyric or media request. While following, the
active original line is re-centered after the height change; manual-scroll
state remains manual and is never pulled back automatically.

The playback bar is the primary selector. Desktop/wide layouts keep separate
quality and lyric controls. Compact layouts retain separate controls where
they fit and use one combined secondary menu at 360 dp and below. The 320 dp
expanded control strip keeps 40 dp secondary and 48 dp primary targets without
removing previous, play/pause, or next. The mini-player's expanded-page action
is scoped to artwork and Track identity so it cannot conflict with nested
transport/menu actions.

## Validation and remaining evidence

Synthetic regressions cover exact, 10 ms early/late, out-of-window,
one-to-one competition, equal-distance ambiguity, identical/conflicting
duplicates, unsafe ordering, empty and overflow edges, QQ placeholder scope,
NetEase optional-track resilience, all four UI modes, missing/both tracks,
persistence, accessibility, active/follow/manual-scroll behavior, seek, word
timing, and 320/mobile/desktop/wide layout.

Machine validation cannot prove that the 10 ms policy recovers every intended
real QQ or NetEase row. Human review remains required for one QQ Japanese
Track, one QQ English Track with a known small delta, and one NetEase Track
with translation/romanization presence. Review records only counts, presence,
and delta buckets, never lyric content.
