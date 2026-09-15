# Search Design

**Status:** Human-review candidate

**Scope:** Dedicated Search and the Home top-search entry

## Product boundary

- Search is provider-neutral in presentation. The page heading is `Search`;
  the active provider remains visible through the field hint, result metadata
  and truthful error states rather than being repeated as the page title.
- Track, Artist, Album and Playlist are independent retained result sections.
  Switching type does not relabel one response as another, and revisiting a
  type preserves its existing controller state.
- Track results use the same `MusicTrackRowSurface`, desktop table header,
  compact More menu, Queue actions, selected surface and current-Track locator
  as Liked and collection details.

## Provider-backed suggestions

Suggestions reuse the active provider's existing Track-search boundary. Fura
does not depend on an undocumented autocomplete endpoint and does not present
locally invented catalog names as provider results.

- Every non-empty edit immediately exposes a first action that submits the raw
  normalized query. It remains available while the provider request is
  debouncing, loading, empty or failed.
- After 320 ms without another edit, the controller requests only page 1 with
  a bound of eight Track results, derives title candidates, removes the raw
  query and case-insensitive duplicates, and displays at most six derived
  entries.
- Replacing text cancels the previous operation, clears its entries and
  selection synchronously, and generation-checks late completion. A stale
  response cannot reappear under new text.
- The dedicated Search page displays suggestions inline at exactly the field
  width. Home displays the same panel in an anchored popup at exactly the top
  field width; closing it does not navigate or activate content behind it.
- Focus loss, outside click/tap, Escape, search-type change and submission
  dismiss the panel. Returning focus may request suggestions again for the
  current text.

## Input and accessibility

- Arrow Down and Arrow Up wrap through the raw action and derived entries.
  Enter submits the highlighted entry; the keyboard Search action submits the
  current raw field text when nothing is selected.
- Mouse hover updates the same highlighted state used by the keyboard. Touch
  selects a full 48 dp row.
- The text field keeps focus while keyboard selection changes or Escape closes
  the panel. Focus is not transferred into transient popup rows.
- Each row is exposed as one semantic button with one localized label and a
  selected state. Decorative icons and duplicated visible text do not create
  additional semantic actions.
- Long titles and Artist detail stay on one line with ellipsis; the panel
  scrolls within a bounded height rather than expanding the Shell.

## Ownership and invalidation

The Shell recreates the Home suggestion controller when provider or account
ownership changes. Search controllers never carry candidates across that
boundary. Suggestions do not own navigation, result paging, playback, Queue or
authentication; selection hands one string back to the established Search
submission path.

## Verification boundary

Controller tests cover debounce, request bounds, de-duplication, cancellation,
late-result rejection, wrapping selection and dismissal. Widget tests cover
raw submission, derived submission, keyboard, mouse, outside tap, focus,
English/Chinese semantics and field-width alignment. Review renders cover
1440, 900, 390 and 320 px layouts plus Simplified Chinese. Provider usefulness,
IME-specific behavior and final visual acceptance remain Human review.
