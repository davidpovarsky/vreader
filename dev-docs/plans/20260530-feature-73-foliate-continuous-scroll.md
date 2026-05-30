# Feature #73 — Foliate scrolled-mode continuous rendering surface

**Gate-1 plan** (rule 47). Status target: `TODO` → `PLANNED` (after Gate-2 audit).
Branch: `feat/feature-73-foliate-continuous-scroll`.
Routed from **Bug #283 / GH #1260** (visible chapter-boundary jump in AZW3/MOBI scroll mode).
Source of truth for the row: `docs/features.md` Feature #73; symptom stays on `docs/bugs.md` Bug #283.

> **PLAN-ONLY artifact.** No code, no version bump, no PR. The Gate-2 independent
> (Codex/cc-suite) audit verifies the model assumptions in this doc before any
> implementation begins.

---

## 1. Problem

In **AZW3 / MOBI / KF8 / PRC** (the Foliate-rendered formats) **scroll** mode,
crossing a chapter/section boundary shows a **visible jump** — reading flow
breaks at every chapter edge. The user wants continuous, smooth scrolling across
chapter boundaries: bottom of chapter N flows seamlessly into top of chapter N+1,
no jump, no flash, no relayout hitch.

**Root cause (assessed + independent-Codex-concurred, GH #1260).** Foliate's
vendored paginator (`vreader/Services/Foliate/JS/paginator.js`) renders **exactly
one section at a time**: the `Paginator` web component holds a single `#view`
(one iframe-backed `View`) in `#container`. Crossing a boundary is a discrete
view swap that stacks **three** discontinuities:

- **D1 — content swap / scroll-offset reset** (dominant). `#turnPage` →
  `#goTo` → `#display` → `scrollToAnchor(anchor)` with `anchor = () => 0`
  (forward) or `() => 1` (back). "Bottom of section N" is replaced by "top of
  section N+1" and the scroll offset is reset. **Architecturally inherent to the
  single-section substrate** — no scroll continuity exists across the boundary.
- **D2 — blank flash.** `#createView` (`:681-692`) calls
  `this.#view.destroy()` + `this.#container.removeChild(...)`, then
  `await view.load(src, …)` loads the new iframe **asynchronously** (`View.load`
  resolves on the iframe `load` event, `:253-283`). Between teardown and
  first paint there is no content.
- **D3 — async post-swap reflow.** After load, `fonts.ready → expand()` and a
  `ResizeObserver(() => this.expand())` (`View.#observer`, `:211`) fire
  `onExpand → #scrollToAnchor`, re-landing the anchor once metrics settle —
  direction-asymmetric (forward lands at top = cheap; back lands at bottom =
  needs the full expanded size first).

Bug **#235** (FIXED) made scroll mode *auto-advance* across sections by
detecting the section edge during the live native scroll
(`#maybeCrossSectionBoundary`, `:1126-1137`) and feeding it through the same
`#turnPage` pipeline — so the advance *happens*, but it rides the same
swap substrate and therefore isn't smooth. **This feature replaces the
substrate**, it does not re-tune #235's edge detection.

A bounded patch (e.g. a D2-only "hold old pixels as overlay until the new view
lays out") cannot clear the "no visible jump" bar because **D1 remains**, and it
breaks Foliate's load-bearing "exactly one view in `#container`" invariant
inside vendored async code. The real fix is a **continuous multi-section
rendering surface** — the AZW3 analog of Bug #180's TXT continuous-surface
redesign.

### 1.1 The single-`#view` invariant is pervasive (Gate-2 C2/H4 correction)
The earlier framing ("generalize the renderer to a list of views" — small change)
under-stated the coupling. `Paginator` dereferences its **single `#view`** (field
declared `:436`) across nearly every method, each of which would need a
window-aware branch or a per-mounted-view rewrite:

- **Geometry getters** — `viewSize` (`:793-794`, reads `this.#view.element`
  bounding rect — the continuous-scroll height becomes the *sum* over mounted
  views, not one element), `start`/`end`/`size` over `#container` (`:790-801`).
- **Visible-range / rect mapping** — `#getVisibleRange` (`:960-966`,
  `this.#view.document`), `#getRectMapper` (`:881-897`, uses `this.viewSize`).
- **Anchor / scroll landing** — `#scrollToAnchor` (`:936-959`), `#scrollToRect`
  (`:898-905`) — both map a rect *inside the one current view's document*; they
  add **no mounted-section offset** (H5, §5.2).
- **Styling / background** — `setStyles` (`:1166-1183`, only `this.#view`),
  `#mediaQueryListener` (`:637-641`, `this.#view.document` background), the
  `#beforeRender` background read.
- **Lifecycle** — `#createView` (`:681-692`, destroys the old `#view` then
  appends one new element), `#display` (`:986-1015`), `focusView` (`:1184-1186`),
  `destroy` (`:1187-1193`), `getContents` (`:1158-1165`, returns one doc).
- **Media-overlay** — `view.js`'s media-overlay highlight handler
  (`view.js:276-277`) does `getContents().find(...)` to locate the active doc.

Therefore the change is **not** a "small generalization." It is a **scoped fork
of the scrolled-renderer path**: an explicit `this.scrolled`-gated branch through
every `#view` consumer, with paged mode keeping the *exact* single-`#view` code
byte-for-byte. WI-1a (new) inventories and branches every consumer before any
behavior WI runs. Feasibility of even mounting >1 view is **gated on WI-0**
(§7).

---

## 2. Goal / non-goals

### Goal
- **Scrolled mode only**, for the Foliate formats: **AZW3 / MOBI / AZW / KF8 /
  PRC** (`BookFormat.azw3` collapses all of these). When `flow="scrolled"`,
  scrolling crosses chapter/section boundaries continuously and smoothly — no
  scroll-offset reset (D1), no blank flash (D2), no post-swap relayout hitch
  visible to the user (D3).
- Preserve everything that works today over the new surface: **relocate /
  fraction reporting** (Bug #260 bottom chrome), **position save/restore via
  `goToFraction`** (Bug #265), **TOC / CFI / fraction navigation** (#1136),
  **theming** (`setStyles`), **bilingual** (`FoliateBilingualContainerView`,
  Feature #56 WI-11), **highlights/overlays**, **TTS scroll-to-anchor**,
  **selection / tap-zone** routing (#988), and **Bug #235 auto-advance**
  semantics (auto-advance becomes *native scroll over a continuous surface*,
  which is strictly the goal state).

### Non-goals (OUT)
- **Paged mode** (`flow="paginated"`) — already smooth via CSS multi-column;
  untouched.
- **EPUB via Readium** (`EPUBNavigatorViewController`) — a separate engine; its
  continuous-scroll story is Bug #165 / Feature #71, not this feature.
- **EPUB via the legacy `EPUBWebViewBridge`** — separate engine
  (`EPUBContinuousScrollCoordinator`); not Foliate.
- **TXT / MD** — Bug #180 already delivered continuous scroll there (native
  TextKit / chunked `UITableView`), a different substrate.
- **Fixed-layout** books (`foliate-fxl` / `fixed-layout.js`) — paged by
  nature; out of scope (gate on `!isFixedLayout`).
- New scroll-mode **chrome / UI affordances** — none introduced. Reuses
  existing chrome only (so **rule 51 is not triggered**; if any new visible
  surface turns out to be required, STOP and file `Design needed:` per rule 51).

---

## 3. Recommended approach

Three approaches were evaluated (see §3.4). **Recommended: (a) Windowed
multi-section continuous scroller** — keep a small window of K adjacent
sections (default prev + current + next, K=3) mounted contiguously inside a
single scrolling `#container`, recycle/evict as the user scrolls.

> **Feasibility is GATED on WI-0 (Gate-2 C2/M13).** This approach is the
> recommended *direction*, not a confirmed-feasible design. It rests on two
> unproven assumptions: (1) that a single iOS scroller can hold K mounted
> iframes stably (which element actually scrolls on iOS — outer WKWebView
> scrollView or inner `#container` — is currently UNKNOWN and stated backwards
> in the old plan body; see §3.3 and §5.2), and (2) that the deep single-`#view`
> coupling (§1.1) can be forked per-mode without becoming a de-facto rewrite.
> **WI-0's deliverable is a *revised technical design* that either confirms (a)
> or escalates** (degenerate K=2, or no-go). WI-1 (pure math) does not start
> until WI-0 validates the model.

### 3.1 Why (a)
- It is the **only** approach that removes **D1** (the dominant jump). When the
  next section is already mounted contiguously below the current one, crossing
  the boundary is a *native scroll*, not a content swap — zero offset reset.
- It also removes **D2** (next section is pre-loaded before its edge is
  reached) and tames **D3** (each section's reflow happens off-screen, before
  it scrolls into view, and the offsets of *already-laid-out* sections above
  the viewport must be preserved across a below-viewport expand).
- It mirrors the **Bug #180 TXT precedent** exactly: a continuous windowed
  surface with a section/chapter-offset index, chapter awareness *derived* from
  scroll position rather than a render-mode switch, and windowing to bound
  memory (TXT used the chunked `UITableView`; Foliate uses K mounted iframes).

### 3.2 Shape of the change (paginator.js)
Today `Paginator` has a single `#view` dereferenced pervasively (§1.1). The
windowed design **forks the scrolled path only** into a list of mounted views:

- A new ordered structure (e.g. `#scrolledViews`: `Map<index, MountedSection>`
  where `MountedSection = { index, view, element, measuredSize }`) replaces the
  single `#view` *for the scrolled path*. **Paged mode keeps the single
  `#view`** — the branch is gated on `this.scrolled`.
- **Container layout (Gate-2 H6 correction).** The old plan claimed "a flex
  column already exists." That is wrong: `#container` is a CSS-grid cell
  (`grid-column`/`grid-row`, `overflow:auto` in scrolled mode, `:506-515`) — it
  is **NOT** `display:flex`. The `flex:0 0 auto` on `View.#element` (`:226-235`)
  only governs that element *if its parent is a flex container*, which
  `#container` is not. With one child (today) the grid cell stacks it fine; with
  K children the stacking order/sizing is **undefined by assumption**. WI-0 must
  define the explicit container layout that stacks K mounted section elements in
  document order **per writing mode**:
  - **horizontal LTR** (default Latin/most CJK-paginated-as-LTR-scrolled) — block
    column, top-to-bottom; the scroll axis is `scrollTop` (`scrollProp` resolves
    to `'scrollTop'` in scrolled non-vertical mode, `:780-784`).
  - **vertical-writing / RTL CJK** (`#vertical === true`) — scroll axis is
    `scrollLeft` (`:782`), `sideProp` is `'width'` (`:787`); sections must stack
    **horizontally**, and offsets accumulate along the inline axis. The block-flow
    assumption silently fails here. WI-0 covers a vertical-writing CJK fixture.
  Likely implementation: make `#container` (scrolled branch only) an explicit
  `display:flex` with `flex-direction` chosen by writing mode, OR an explicit
  block/inline stack; decided empirically in WI-0, not assumed here.
- New private methods (all `#`-private, scrolled-gated):
  - `#mountSection(index, position)` — create a `View`, `await view.load(src)`,
    insert its element into `#container` at the head or tail; record measured
    size after `expand()`. (Refactors the section-load half of `#display`.)
  - `#evictSection(index)` — `view.destroy()` + remove element; **adjust scroll
    offset by the evicted element's measured size if it was above the
    viewport** (so the viewport content does not shift — the load-bearing
    invariant).
  - `#ensureWindow()` — given the current top-visible section, mount missing
    neighbors within ±W and evict sections outside ±(W+hysteresis).
  - `#sectionAtScrollOffset()` / `#offsetOfSection(index)` — the section-offset
    bookkeeping (sum of measured sizes of mounted sections above) that powers
    relocate, fraction reporting, and TOC/restore landing.
  - `#scrolledTurnToBoundary()` — replaces #235's `#turnPage` call for the
    scrolled path: when the user nears a window edge, mount the next section
    ahead of the viewport (no `goTo`, no offset reset); `#turnPage` /
    `#maybeCrossSectionBoundary` keep owning *paged* mode unchanged.
- **Anchor coordinate translation across mounted iframes (Gate-2 H5 — new
  foundational concern).** `#scrollToAnchor` (`:936-959`) and `#scrollToRect`
  (`:898-905`) today take a rect from `getClientRects()` *inside the one current
  view's iframe document* and scroll `#container` to it. They add **no
  mounted-section offset**. With K mounted iframes, a rect from section N's doc
  is in section N's *iframe coordinate space*; to scroll the continuous
  container the renderer must translate it to **container coordinates** =
  `#offsetOfSection(N) + rectWithinSectionN`. Without this, TTS scroll-to-anchor
  and CFI/TOC anchor landing scroll to the wrong place across iframes. A
  dedicated foundational WI (WI-1b) owns this rect→container translation BEFORE
  any navigation-landing WI. `goToFraction` resolution
  (`view.js#sectionProgress.getSection` → `{index, anchor}`, `view.js:469-473`)
  reaches `renderer.goTo({index, anchor})`; in scrolled mode the renderer mounts
  the target window first, then translates `(index, intra-anchor)` to the
  container offset.
- **`relocate` / fraction over the window (Gate-2 C1 — corrected contract).**
  The old plan said the renderer should emit a **whole-book** fraction. **That is
  wrong and would double-apply.** The renderer's `#afterScroll` (`:967-985`)
  emits `detail.fraction = this.start / this.viewSize` — an **intra-section**
  fraction. `view.js#onRelocate` (`view.js:327-328`) feeds `(index, fraction,
  size)` into `SectionProgress.getProgress` (`progress.js:74-98`), which is the
  **canonical whole-book fraction source** (`sizeBefore + fraction *
  sizeInSection` over `sizeTotal`). `foliate-host.js` (`:26-40`) then forwards
  the *already-converted* whole-book `fraction` + `section.current/total` from
  `lastLocation`. So the windowed `#afterScroll` MUST preserve this contract: it
  derives the **current section index from the scroll offset** over mounted
  sections (`sectionAtOffset`), computes the **intra-section** fraction within
  that section, and emits `{ index, fraction(intra), size }` exactly as today —
  `SectionProgress` stays the single source of whole-book truth. Bug #260 chrome
  and Bug #265 fraction-restore inherit correct values unchanged. (Caveat:
  `SectionProgress.sizes` are per-section *estimated* sizes from the spine, not
  the live measured iframe sizes WI-1 uses for layout; the relocate `index` must
  come from the live scroll offset, but the `fraction` reported to chrome stays
  the SectionProgress whole-book value so it matches the restore round-trip.)

### 3.3 Bridge / Swift side
The Swift bridge surface is **mostly unchanged** — that is a design goal. The
change is contained in the vendored JS substrate; Swift continues to call
`readerAPI.setLayout({flow})`, `readerAPI.goToFraction(f)`,
`readerAPI.goTo(target)`, and consume `relocate`.

**Scroll contract — corrected (Gate-2 C2).** The old plan stated the contract
**backwards**. The live code (`FoliateSpikeView.swift:244`, mirrored at `:305`)
does `webView.scrollView.isScrollEnabled = (layoutFlow == "scrolled")` — i.e.
the **outer WKWebView scrollView is ENABLED in scrolled mode, disabled in paged
mode** (the comment at `:239-243` says "in scrolled mode the document is one
long page and the outer scrollView IS the scroller"). At the same time, foliate
`paginator.js`'s `start`/`end`/`#scrollTo` all read/write
`this.#container[scrollProp]` (the inner grid-cell `#container`, `:780-801`,
`:906-928`), and `#container` carries its own `scroll` listeners (`:559-580`).
**Which element actually receives touch scroll on iOS — the outer WKWebView
scrollView or the inner `#container` — is UNKNOWN and is central to feasibility:**
a windowed surface needs ONE continuous scroller whose offset both the user's
gesture and `start`/`#scrollTo` agree on. If touches scroll the outer scrollView
but `start` reads the inner `#container.scrollTop` (which may never change
because the body doesn't overflow), the windowing math reads a stale offset.

**WI-0 must measure this first** (on iOS Simulator, not just desktop Chrome):
(1) instrument both `webView.scrollView.contentOffset` and
`#container.scrollTop` during a live drag in scrolled mode and report which one
moves; (2) confirm whether nested `#container` scrolling stays stable with
**multiple** mounted iframes (vs. one today). All behavior WIs (WI-2..WI-7) are
**blocked on that measurement** — the entire mount/evict/offset model depends on
knowing the real scroller.

Swift edits are limited to:
- Possibly threading a **window-size / eager-mount config** through
  `setLayout` (`foliate-host.js#setLayout` `:319-328` already forwards an
  options bag onto renderer attributes) — only if a tunable is wanted; default
  K=3 can live entirely in JS.
- **No change** to `FoliatePositionRestoreController` (restore stays
  `goToFraction`-based — the device-confirmed reliable channel, Bug #265).
- `foliate-bundle.js` **must be rebuilt** from `paginator.js` via
  `./build-bundle.sh` (esbuild 0.28.0) every time the JS changes — enforced by
  the existing `FoliatePaginatorScrollBoundaryTests` parity check (extend it).

### 3.4 Rejected alternatives
- **(b) Pre-warm-next-section + scroll-offset preservation** (lighter: mount
  only current+next, hold old view's pixels, cross over). **Rejected as the
  primary** because it does not fully clear **D1** — the prior #283 assessment
  already rejected the D2-only variant of this; even with offset preservation
  it reintroduces a swap at the moment the old view is unmounted, and it
  fights the single-view invariant. *However* — a degenerate K=2 case of
  approach (a) (current + next only, evict-behind aggressively) IS effectively
  (b) done correctly inside the windowed model, so (a) subsumes (b)'s lighter
  footprint as a tuning knob without its correctness gap.
- **(c) Full rewrite of the scrolled path** (a bespoke continuous renderer not
  derived from `Paginator`). **Rejected** — throws away Foliate's section
  loading, CFI resolution, overlay/annotation drawing, TTS anchoring, and
  bilingual enumerate hooks, all of which the bridge depends on. Far higher
  risk and a permanent divergence from upstream. (a) is a *targeted* fork of
  one mode inside the existing component, preserving every other seam.

---

## 4. Prior art / project precedent / research

### 4.1 Bug #180 (TXT continuous surface) — the governing precedent
What transfers:
- **Abandon discrete chapter-swap; render one continuous windowed surface.**
- **Chapter/section awareness is *derived* from scroll position**, kept via a
  **chapter/section-offset index** (each unit's global start), not a render-mode
  switch. TOC tap → computed offset; per-chapter progress + scrubber computed
  from the continuous offset; highlight pipeline maps global↔unit-local.
- **Windowing to bound memory** — TXT lazy-renders rows in the chunked
  `UITableView`; Foliate mounts only K adjacent sections.
- **The boundary-detect-then-swap model is the wrong model** — #235 is exactly
  that model for Foliate, and this feature supersedes its substrate.

What does NOT transfer (constraint delta): TXT is **native TextKit** (one
attributed string / chunked table, cheap to lay out, synchronous metrics).
Foliate is **WKWebView + vendored JS**: each section is a **separate iframe
document** with **async** load + font/image reflow and its own ResizeObserver.
So "mount K sections" is K iframes, with async settle and offset-preservation
hazards TXT never had. This is the central risk (§7).

### 4.2 Upstream Foliate-js
Confirmed via source + web research: **upstream foliate-js has no continuous
cross-section scroll**. Even in `flow="scrolled"` the paginator renders **one
section at a time** (single-column continuous *within* a section, swap *across*
sections). Upstream issue *johnfactotum/foliate#1455* ("Scrolling is miserable
in continuous scroll mode") confirms this is a known, unsolved-upstream pain
point. **Implication:** there is no upstream mode to adopt; this is a genuine
**vendored fork** of the scrolled path (tracked-fork cost — §7, §9).

### 4.3 Bug #165 / Feature #71 (EPUB-via-EPUBWebViewBridge continuous scroll)
The legacy EPUB engine already solved this class with
`EPUBContinuousScrollCoordinator` + a windowed extend/evict driven by a
scroll-boundary signal, plus a `scroll-boundary?spine=N&near=…` DebugBridge
driver added precisely because the rAF-throttled scroll observer is
**unverifiable CU-free on the virtual display**. That coordinator's
**extend/evict + offset-preservation pattern + DebugBridge boundary driver** is
strong project precedent for the JS-side windowing AND for the verification
strategy here (§8) — though it runs in a different engine (vreader's own EPUB JS,
not Foliate), so it is a *pattern* to mirror, not code to share.

### 4.4 Other precedent
- #235's `#maybeCrossSectionBoundary` + the `FoliatePaginatorScrollBoundaryTests`
  source↔bundle parity check — the existing scroll-boundary test scaffolding to
  extend.
- Bug #265's `FoliatePositionRestoreController` — restore is `goToFraction`,
  NOT CFI (device-confirmed); the windowed surface must keep fraction-restore
  exact.

---

## 5. Surface area — file-by-file

### Modified — vendored JS (the core change)
- **`vreader/Services/Foliate/JS/paginator.js`** — generalize the **scrolled
  path** of `Paginator` to a windowed multi-section surface:
  - New private state: `#scrolledViews` (ordered `Map<index, MountedSection>`),
    `#windowRadius` (default 1 → prev/current/next), section-offset bookkeeping.
  - New private methods: `#mountSection`, `#evictSection`, `#ensureWindow`,
    `#offsetOfSection`, `#sectionAtScrollOffset`, `#preserveOffsetAcross(fn)`
    (run a mutation that may change above-viewport size, then restore the
    viewport's content position).
  - Modify `#display` (`:986-1015`) — factor out the per-section
    create+load+overlay steps so both single-view (paged) and windowed
    (scrolled) callers reuse them.
  - Modify `#createView` (`:681-692`) — paged keeps single-view; scrolled mounts
    into the window without destroying neighbors.
  - Modify `#maybeCrossSectionBoundary` / `#turnPage` (`:1075-1137`) — scrolled
    path drives `#ensureWindow` (mount-ahead) instead of a `goTo`-swap; paged
    path unchanged. **Split (Gate-2 M10):** the *prefetch-near-edge* trigger
    (mount the next section W sections **before** the exact edge) is separate
    from the *hard-edge fallback* (`viewSize - end <= 2` / `start <= 0`, `:1130`)
    that #235 uses today. The hard-edge fallback is retained as a graceful
    catch when the user out-scrolls the prefetch; the prefetch uses an *earlier*
    threshold. Both paths are tested (WI-3/WI-4).
  - Modify `#scrollToAnchor` / `#scrollToRect` (`:898-959`) — translate a rect
    from a mounted section's iframe doc to **container coordinates**
    (`#offsetOfSection(index) + rectWithinSection`) in scrolled mode (Gate-2 H5,
    WI-1b/WI-6). Single-view paged math unchanged.
  - Modify `#afterScroll` / relocate (`:967-985`) — derive **current section
    index from scroll offset** over mounted sections and emit the **intra-section**
    fraction (NOT whole-book), preserving the `SectionProgress` conversion
    contract (Gate-2 C1, §3.2).
  - Modify `getContents()` (`:1158-1165`) — return all mounted-section docs in
    scrolled mode. **(Gate-2 M11 + round-2 H1)** this is real implementation+test
    work, not a "confirm": overlay draw, TTS `scrollToAnchor`, the bilingual
    enumerate loop, **host-side selection** (`foliate-host.js:81-100`, the real
    highlight-creation / selection-popover consumer — see round-2 H1 below),
    `view.js#deselect` (`view.js:484-486`), and media-overlay highlight
    (`view.js:276-277`, which `.find(...)` over `getContents()` and has a latent
    `=`-vs-`==` bug in upstream that only "works" because there's one element
    today) all iterate `getContents()` and must target the right section when >1
    is mounted. **The host selection handler is the load-bearing one:** it
    currently destructures `const { doc, index } = contents[0]` (`:83`) and
    computes `view.getCFI(index, range)` (`:92`) against that first doc, so a
    selection in a non-first mounted section produces a CFI/index rooted in the
    wrong section. WI-7 rewrites it to find the selection-owning mounted entry
    (§5 view.js bullet + WI-7).
  - Modify `setStyles` (`:1166-1183`) — **(Gate-2 H8)** today it applies
    theme/font CSS to `this.#view` only; in scrolled mode it must apply to **all
    mounted views** (current + neighbors) AND to any view mounted *later* (define
    a style lifecycle: cache `#styles`, apply on every `#mountSection`, and the
    `fonts.ready → expand()` re-expand fires per mounted doc). Otherwise mounted
    non-current sections render with stale/no theme.
  - Modify `focusView` (`:1184-1186`), `#mediaQueryListener` (`:637-641`), and
    the `#beforeRender` background read — scrolled-gated to operate on the
    *current* mounted view (resolved from scroll offset), not a single `#view`.
  - Modify `destroy()` (`:1187-1193`) — tear down all mounted views.
  - Extract a **pure, testable helper module** for the windowing/offset math
    (see §6) so it can be unit-tested in Node and (mirrored) in Swift.
- **`vreader/Services/Foliate/JS/view.js`** — `resolveNavigation` /
  `goToFraction` / `#sectionProgress.getSection` (`:444-473`) interplay with the
  renderer's new scrolled offset resolution; `#onRelocate` (`:327-335`) consumes
  the renderer's **intra-section** `index`/`fraction`/`size` and converts to
  whole-book via `SectionProgress` — **this conversion contract must NOT change**
  (Gate-2 C1). Multi-doc consumers that DO interact with the windowed
  `getContents()` and are in-scope for WI-7: the media-overlay highlight
  `getContents().find(x => x.index = resolved.index)` (`:276-277`, note the
  latent `=`-vs-`==` that only "works" with one mounted doc) and `deselect`
  (`:484-486`, iterates all docs). The renderer otherwise owns the new math;
  `view.js`'s navigation resolution keeps delegating (confirmed minimal in
  Gate-2 round 2).
- **`vreader/Services/Foliate/JS/foliate-host.js`** (round-2 H1 — the missed
  selection consumer) — the selection handler (`:76-109`) is the real
  highlight-creation / selection-popover routing path, and it is **single-doc by
  assumption**: `:81` reads `view.renderer?.getContents?.()`, `:83` destructures
  `const { doc, index } = contents[0]` (always the FIRST mounted doc), `:84` reads
  that doc's selection, and `:92` builds `view.getCFI(index, range)` from
  `contents[0].index`. `view.getCFI` (`view.js:429-432`) roots the CFI in
  `this.book.sections[index].cfi`, so a wrong `index` yields a CFI in the wrong
  section. The `load` listener (`:105-108`) already attaches `selectionchange` to
  **every** loaded section's doc, so the handler fires for selections in any
  mounted section — but it then inspects only `contents[0]`. WI-7 rewrites the
  handler to identify the mounted entry that OWNS the active selection (iterate
  `getContents()`, pick the `{doc, index}` whose `doc.getSelection()` is
  non-collapsed with a range), emit that section's `index`, and build
  `view.getCFI(ownerIndex, range)` against the owning doc. Without this, selecting
  text in section N+1 serializes section 0's index/CFI (wrong highlight target /
  wrong popover anchor) or misses the selection entirely.
- **`vreader/Services/Foliate/JS/foliate-bundle.js`** — REBUILT artifact (do not
  hand-edit). Rebuild via `./build-bundle.sh`.

### Modified — Swift (small)
- **`vreader/Views/Reader/FoliateSpikeView.swift`** (Gate-2 H3 — correct path;
  this file is under **`vreader/Views/Reader/`**, NOT `vreader/Services/Foliate/`)
  — the `relocate` handler already consumes `fraction` / `sectionIndex` /
  `sectionTotal` / `cfi` from the bridge; verify these stay correct when sourced
  from the windowed surface (current section derived from offset, whole-book
  fraction from `SectionProgress` per §3.2 C1). **Scroll-enable toggle (Gate-2
  C2):** `webView.scrollView.isScrollEnabled = (layoutFlow == "scrolled")`
  (`:244`, `:305`) **ENABLES** the outer WKWebView scrollView in scrolled mode
  — the old plan said this backwards. Whether that outer scrollView or the inner
  `#container` is the true scroller is the WI-0 measurement (§3.3). If WI-0 finds
  the windowed surface needs a *different* scroller wiring than today (e.g. the
  outer scrollView must be the single continuous scroller and `#container` must
  stop being `overflow:auto`, or vice-versa), this toggle / the `#container` CSS
  changes accordingly — captured in WI-0's revised design, not assumed here.
- **`vreader/Services/Foliate/JS/build-bundle.sh`** — unchanged; just run it.

### Modified — tests
- `vreaderTests/Services/Foliate/FoliatePaginatorScrollBoundaryTests.swift` (or
  sibling) — extend the source↔bundle parity guard to cover the new windowing
  symbols; add the windowing-math pure-logic cases (§6).

### Files OUT of scope
- `epub.js`, `mobi.js`, `epubcfi.js`, `fixed-layout.js`, `overlayer.js`,
  `progress.js`, `search.js`, `text-walker.js`, `tts.js`, `footnotes.js` — section
  parsing, CFI, fixed-layout, overlay drawing, TTS, search remain as-is (the
  windowed surface *consumes* them, doesn't change them).
- All Readium files (`ReadiumEPUBHost*`, `ReadiumNavigator*`, …) — different engine.
- `EPUBContinuousScrollCoordinator` + EPUB bridge — pattern reference only, not edited.
- TXT/MD/PDF readers and bridges.
- `FoliatePositionRestoreController.swift` — restore contract (`goToFraction`)
  unchanged.
- Bilingual orchestrator/pipeline files — they enumerate over `getContents()`,
  which we keep working; no edits expected (confirm in §10).
- The dead `FoliateReaderHost` / `FoliateReaderViewModel` / `FoliateViewBridge`
  (not on the live load path).

---

## 6. Extractable pure logic (testable without WKWebView)

The windowing decisions are pure functions of section sizes + scroll offset.
Extract them so they are unit-testable in **both** Node (JS) and Swift:

- **`computeWindow(currentIndex, sectionCount, radius) -> {mount:[idx], evict:[idx]}`**
  given a previously-mounted set — the mount/evict decision with hysteresis.
- **`offsetOfSection(index, measuredSizes) -> Number`** — prefix-sum of mounted
  sizes above.
- **`sectionAtOffset(scrollOffset, measuredSizes) -> {index, intraOffset}`** —
  inverse mapping (for relocate / current-section).
- **`offsetAdjustmentOnEvict(evictedIndex, evictedSize, viewportTopIndex)`** —
  how much to add/subtract from `scrollTop` to keep the viewport stable when a
  section above the viewport is evicted (the offset-preservation invariant).
- **`intraSectionFraction(scrollOffset, mountedSizes) -> {index, intra}`**
  (Gate-2 C1 — replaces the old `wholeBookFraction`). The renderer emits the
  **intra-section** fraction; whole-book conversion stays owned by
  `SectionProgress.getProgress` (`progress.js:74-98`) downstream. A
  `wholeBookFraction` helper here would double-apply the conversion (the old
  plan's bug) and break Bug #260 / Bug #265.
- **`rectToContainerOffset(rectWithinSection, offsetOfSection)`** (Gate-2 H5) —
  the anchor-coordinate translation: maps a rect from a mounted section's iframe
  doc into continuous-container coordinates. Powers WI-1b (TTS / CFI / TOC anchor
  landing across iframes). Pure arithmetic; the rect extraction itself is
  DOM-bound (live-DOM test), but the offset addition is unit-testable.

These mirror Bug #180's chapter-offset index and Feature #71's extend/evict math.
The Swift side gets a **`FoliateScrolledWindowMath`** pure value type that
re-implements the same functions for unit testing + the parity assertion
(precedent: the boundary-epsilon parity already mirrored in
`FoliatePaginatorScrollBoundaryTests`). JS↔Swift parity is asserted by a fixture
table of (input → expected) cases checked on both sides.

---

## 7. Work-item sequencing

Risk is front-loaded. WI-0 is a **design gate**, not just a spike: its
deliverable is a *revised technical design* that the math + behavior WIs depend
on. Nothing past WI-0 starts until WI-0's verdict lands (Gate-2 M13). The WI list
grew from the round-1 audit: a `#view`-consumer inventory WI (WI-1a) and an
anchor-coordinate-translation WI (WI-1b) are now explicit foundational steps, and
WI-7 is reframed from "confirm" to "implement+test."

| WI | Title | Tier | JS / Swift | Est. PR size |
|----|-------|------|-----------|--------------|
| **WI-0** | **Feasibility DESIGN GATE** (Gate-2 C2/H6/H7/M13). On iOS Simulator (not just desktop Chrome), in a guarded `paginator.js` branch: **(a)** instrument and report **which element scrolls** in scrolled mode — outer `webView.scrollView.contentOffset` vs inner `#container.scrollTop` — during a live drag (§3.3 C2); **(b)** mount the *next* section contiguously and confirm two iframes coexist in `#container` without layout/expand thrash, for **horizontal LTR, horizontal CJK, AND vertical-writing/RTL CJK** (§3.2 H6) — define the explicit per-writing-mode container layout; **(c)** confirm `expand()` + ResizeObserver on a below-viewport section doesn't shift the viewport; **(d)** a **hard memory/perf gate** (H7): mount K=3 large CJK AZW3 sections from local `test-books/` (`被讨厌的勇气.azw3`, `道诡异仙`) and measure peak memory + scroll frame stability — decide adaptive K (2 vs 3 by measured section size) if K=3 is too heavy. **Deliverable: a revised technical design appended to this plan + go / degenerate-K=2 / no-go.** | behavioral (design gate) | JS | M (spike, may not ship) |
| **WI-1** | **Pure windowing math** — `FoliateScrolledWindowMath` (Swift) + JS helper (`computeWindow`, `offsetOfSection`, `sectionAtOffset`, `offsetAdjustmentOnEvict`) + parity fixture table. **No `wholeBookFraction` here** — whole-book fraction stays owned by `SectionProgress` (Gate-2 C1); the helper exposes only `intraSectionFraction(scrollOffset, mountedSizes) -> {index, intra}` so `#afterScroll` can emit the intra-section value the existing contract expects. Gated on WI-0's revised design. | foundational | both | S–M |
| **WI-1a** | **`#view`-consumer inventory + scrolled-branch scaffolding** (Gate-2 H4) — enumerate every `#view` dereference (§1.1) and introduce the `this.scrolled`-gated branch points (current-view resolver, `#scrolledViews` map) with **paged path byte-identical**, behind an internal flag, no behavior change yet. This is the explicit "fork the path" WI that the old plan folded into "small generalization." | foundational | JS | M |
| **WI-1b** | **Anchor coordinate translation across mounted iframes** (Gate-2 H5) — pure helper + `#scrollToRect`/`#scrollToAnchor` scrolled branch that maps a rect in section N's iframe doc to container coordinates (`#offsetOfSection(N) + rectWithinSection`). Unit-tested (pure mapping) + live-DOM (rect of an element in a non-current mounted section lands at the right container offset). BEFORE WI-6 navigation landing. | foundational | both | M |
| **WI-2** | **Mount/evict primitives** — `#mountSection` / `#evictSection` / `#ensureWindow` (scrolled-gated, driven by WI-1 math + WI-1a scaffolding). Includes the **style lifecycle (Gate-2 H8):** `#mountSection` applies cached `#styles` + `fonts.ready → expand()` to every newly-mounted view. Behind the WI-1a flag. | behavioral | JS | M |
| **WI-3** | **Continuous boundary crossing** — replace the scrolled-mode `#turnPage`-swap with **prefetch-near-edge** mount-ahead via `#ensureWindow` (earlier threshold), keeping the **hard-edge fallback** (`viewSize-end<=2`/`start<=0`) as a graceful catch when the user out-scrolls the prefetch (Gate-2 M10 — both paths tested). Native scroll crosses with zero offset reset (D1 gone). #235 auto-advance becomes native scroll over the window. | behavioral | JS | M |
| **WI-4** | **Offset-preservation on evict + reflow** — preserve viewport content position across below-viewport `expand()`/eviction (D3 tamed); pre-mount-ahead so no blank edge (D2 gone). Re-run WI-0's memory/perf gate (H7) on the real evict path. | behavioral | JS | M |
| **WI-5** | **Relocate + intra-section fraction over the window** (Gate-2 C1) — `#afterScroll` derives current section from scroll offset and emits the **intra-section** fraction (NOT whole-book); `view.js#onRelocate` → `SectionProgress.getProgress` stays the whole-book source; verify `foliate-host.js` relocate payload (Bug #260 chrome, Bug #265 restore) is correct via the SectionProgress round-trip. | behavioral | JS (+ verify Swift) | S–M |
| **WI-6** | **Navigation landing** — TOC / CFI / `goToFraction` mount the target window first, then use WI-1b's translation to land at `#offsetOfSection(index) + intra` exactly (restore + TOC tap). | behavioral | JS | M |
| **WI-7** | **Multi-doc consumers: getContents / overlays / TTS / bilingual / SELECTION (host + view) / media-overlay** (Gate-2 M11 + round-2 H1 — implementation+tests, not "confirm") — `getContents()` returns all mounted docs; **implement and test** overlay draw, TTS `scrollToAnchor` (via WI-1b translation), the bilingual enumerate/inject loop (`FoliateBilingualContainerView` keys on section id), and the media-overlay highlight `.find(...)` (`view.js:276`) each targeting the correct mounted section. **Host-side selection (round-2 H1):** `foliate-host.js`'s selection handler (`:81-100`) today reads `contents[0]` unconditionally and builds the CFI via `view.getCFI(contents[0].index, range)` — with K mounted sections, selecting in section N+1 serializes the **wrong section's index/CFI**. WI-7 rewrites the handler to **identify the mounted entry that actually OWNS the active selection** (iterate `getContents()`, pick the `{doc, index}` whose `doc.getSelection()` is non-collapsed with a range), emit **that** section's `index`/`href`, and build the CFI against the correct mounted doc (`view.getCFI(ownerIndex, range)`, `view.js:429`). `view.js#deselect` (`:484-486`, already iterates all docs) stays correct. Live-DOM tests for the multi-doc cases, including a highlight created from a selection in a **non-first** mounted section (assert correct section index/CFI + highlight renders on the right section). | behavioral | JS (+ Swift verify) | M |
| **WI-8** | **Bundle rebuild + parity guard + DebugBridge boundary driver + architecture.md** — rebuild `foliate-bundle.js`; extend `FoliatePaginatorScrollBoundaryTests`; add a `scroll-boundary`-style DebugBridge driver for the Foliate windowed surface (mirror Feature #71). The architecture.md Foliate-section update (Gate-2 M12) is a mandatory **early** doc step (see §5 / §13), not deferred to here. | behavioral (final WI) | Swift + JS | M |

**JS-only WIs (hard to Swift-unit-test):** WI-0, WI-1a, WI-2, WI-3, WI-4, WI-7
(the JS half). **Swift-testable / mixed:** WI-1 + WI-1b (pure math/mapping both
sides), WI-5/WI-6 (the math + the relocate payload), WI-8 (parity guard +
DebugBridge driver).

If WI-0 returns **no-go on K>1** (e.g. WKWebView can't keep two stable iframes in
one scroller without layout thrash, OR the outer/inner scroller contract can't be
reconciled into one continuous scroller), escalate to the user: fall back to the
degenerate K=2 "mount-next-then-cross" variant (approach (b) inside the windowed
model) and re-scope — do NOT silently ship a half-fix that leaves D1.

---

## 8. Test catalogue

JS-in-WKWebView is **not** unit-testable in Swift. The strategy is: maximize the
extractable pure logic, use live-DOM tests where a real WebView is needed, and
rely on device verification for the visual smoothness criterion.

| Test file | Covers | Kind |
|-----------|--------|------|
| `vreaderTests/Services/Foliate/FoliateScrolledWindowMathTests.swift` | `computeWindow` (mount/evict + hysteresis), `offsetOfSection`, `sectionAtOffset`, `offsetAdjustmentOnEvict`, `intraSectionFraction`, `rectToContainerOffset`; edges: 0 sections, 1 section, first/last boundary, single huge section, radius>count, evict above vs below viewport, CJK-sized sections, vertical-writing (inline-axis offsets). **No `wholeBookFraction` test** (Gate-2 C1 — that conversion is `SectionProgress`'s, not the helper's). | Swift unit (Swift Testing) |
| `paginator.window.test.js` (Node, run via build-bundle's node) | The JS helper module's `computeWindow` / `intraSectionFraction` / `rectToContainerOffset` etc. against the SAME fixture table as the Swift suite (parity). | JS unit |
| `vreaderTests/Services/Foliate/FoliatePaginatorScrollBoundaryTests.swift` (extend) | Source↔bundle parity: the new windowing symbols exist in `foliate-bundle.js`; the parity fixture table matches Swift↔JS. | Swift parity guard |
| `FoliateMessageParserTests` (extend) | relocate payload parses correctly when `fraction` is the **SectionProgress-converted whole-book value** (host forwards `lastLocation.fraction`, not the renderer's intra value — Gate-2 C1). | Swift unit |
| Live-WKWebView DOM test (precedent: `EPUBWebViewBridgeViewportLockDOMTests`) | Load `mini-azw3`, `flow="scrolled"`, assert (a) >1 mounted section element near a boundary, (b) the real scroller's offset (per WI-0's finding — outer or inner) is monotonic across a boundary cross (no reset), (c) eviction keeps the visible section's bounding rect stable. | Swift + real WebView |
| Live-WKWebView DOM test — **anchor translation** (Gate-2 H5/L14) | With ≥2 mounted sections, scroll-to-anchor of an element in the **non-current** mounted section lands at `#offsetOfSection(N)+rectWithin` (the container scroll offset matches within tolerance). | Swift + real WebView |
| Live-WKWebView DOM test — **style propagation** (Gate-2 H8/L14) | After `setStyles` with ≥2 mounted sections, every mounted iframe doc carries the injected `<style>` content (current AND neighbor), and a later `#mountSection` inherits cached `#styles`. | Swift + real WebView |
| Memory/perf measurement (Gate-2 H7) | WI-0 + WI-4: peak memory + scroll frame stability with K=3 large CJK AZW3 sections (`被讨厌的勇气.azw3`, `道诡异仙`); informs adaptive-K. | Device/Simulator instrument |
| Device verification (Gate-5) | The **visual smoothness** criterion (no perceptible jump) — not harness-assertable. See §9. | Device / CU |

**Honesty note:** the headline acceptance criterion ("no visible jump") is
*visual* and cannot be asserted by the CU-free harness (rAF/scroll observers are
paused on the virtual display — project memory). The DOM tests assert the
*mechanism* (multiple mounted sections, monotonic scrollTop, stable rects); the
*perception* is device-verified.

---

## 9. Risks + mitigations

| # | Risk | Mitigation |
|---|------|-----------|
| R1 | **Breaking the pervasive single-`#view` invariant** (Gate-2 H4 — `viewSize`, `#getVisibleRange`, `#getRectMapper`, `#scrollToAnchor`, `setStyles`, `focusView`, `#mediaQueryListener`, background, `destroy`, `getContents`, media-overlay ALL dereference one `#view`, §1.1) cascades into overlay/relocate/TTS/style bugs. | Reframe as a **scoped fork** (§1.1), not a small generalization. WI-1a explicitly inventories + branches every consumer before behavior work; **paged keeps the exact single-`#view` code byte-for-byte**, gated on `this.scrolled && !isFixedLayout`. WI-0 design-gate de-risks coexistence before any behavior flips; internal flag keeps default behavior until WI-3. |
| R2 | **Regressing Bug #235 auto-advance.** | #235's edge detection is *subsumed* — auto-advance becomes native scroll over the window. **Split (M10):** prefetch-near-edge (earlier threshold) + retained hard-edge fallback (`viewSize-end<=2`/`start<=0`). Assert the existing #235 boundary tests still pass; the DebugBridge driver (WI-8) re-verifies cross-boundary advance on device. |
| R3 | **Position restore / relocate fraction wrong** over the continuous surface (Bug #265 restores via `goToFraction`; Bug #260 chrome reads `fraction`). | **Corrected contract (Gate-2 C1):** the renderer emits the **intra-section** fraction (current section from scroll offset, WI-1 + WI-5); `SectionProgress.getProgress` (`progress.js:74`) stays the canonical whole-book converter; `foliate-host.js` forwards the converted value. Emitting whole-book from the renderer would double-apply — explicitly NOT done. Restore (`goToFraction`) unchanged Swift-side; device-verify reopen-at-saved-position lands exactly. |
| R4 | **Memory / performance** of K mounted iframes — each large CJK AZW3 section is a full iframe doc + layout + fonts + images + ResizeObserver + overlay SVG + injected styles + selection state. | **Hard gate (Gate-2 H7):** WI-0 AND WI-4 run a memory/perf measurement with K=3 large CJK sections (`被讨厌的勇气.azw3` / `道诡异仙` local test-books) — peak memory + scroll frame stability. **Adaptive K (2 vs 3 by measured section size)** if K=3 is too heavy. Aggressive evict + hysteresis; never mount the whole book (Bug #180's bound). |
| R5 | **Vendored fork** — `paginator.js` diverges from upstream foliate-js (which has no continuous scroll, #1455); future upstream pulls get harder. | Confine the change to the scrolled branch with clear `// vreader #73` markers; keep the helper math in a separate module; document the fork in `docs/architecture.md` Foliate section. Upstream has no fix to track, so divergence cost is bounded. |
| R6 | **Not eye-verifiable CU-free** — smoothness is visual; rAF/scroll observers paused on the virtual display. | Mirror Feature #71: add a DebugBridge `scroll-boundary` driver (WI-8) to drive extend/evict deterministically + assert the *mechanism*; reserve the *visual smoothness* judgment for device/CU verification (Gate-5). |
| R7 | **Async iframe load races** — user scrolls fast past a not-yet-mounted section. | Pre-mount ahead by W sections before the edge; if the user outruns the mount, fall back to the existing #235 `#turnPage` landing (graceful, not crash) and continue. Lock (`#locked`) discipline from #235 reused to serialize concurrent mounts. |
| R8 | **Bilingual coupling** (`FoliateBilingualContainerView` enumerates per-section via `getContents()`/section-load). | WI-7 keeps `getContents()` returning all mounted docs; the bilingual enumerate keys on section id, so multiple mounted sections enumerate independently. Verify the `.foliateSectionLoaded` → enumerate path fires per newly-mounted section. |

---

## 10. Open questions for the Gate-2 audit

The assumptions I am least sure of — the Codex/cc-suite auditor should verify
each against the actual source before this plan goes to `PLANNED`:

1. **Model-assumption verification (line ranges) — re-verified round 1.**
   Confirmed against current `paginator.js` (1197 lines): `#createView`
   (`:681-692`), `#display` (`:986-1015`), `#goTo` (`:1019-1036`), `#turnPage`
   (`:1075-1086`), `#maybeCrossSectionBoundary` (`:1126-1137`), `#scrollToAnchor`
   (`:936-959`), `#scrollToRect` (`:898-905`), `#afterScroll` (`:967-985`;
   `detail.fraction = this.start / this.viewSize` at `:977`), `#getVisibleRange`
   (`:960-966`), `#getRectMapper` (`:881-897`), `getContents` (`:1158-1165`),
   `setStyles` (`:1166-1183`), `focusView` (`:1184-1186`), `destroy`
   (`:1187-1193`), `viewSize` getter (`:793-794`), `start` getter (`:796-797`),
   `scrolled`/`scrollProp`/`sideProp` (`:777-789`), `#mediaQueryListener`
   (`:637-641`), and `:host([flow="scrolled"]) #container { overflow:auto }`
   (`:506-515`, a **grid cell**, not flex). The single `#view` field declaration
   (`:436`) — auditor: re-confirm the exact declaration line; the *consumers* are
   all confirmed above.
2. **Windowing feasibility / coupling depth — RESOLVED to a SCOPED FORK (Gate-2
   H4/C2).** The single-`#view` coupling is pervasive (§1.1), so this is **not** a
   "small generalization." Reframed as a scoped fork of the scrolled path; WI-1a
   inventories + branches every consumer; **feasibility itself is gated on WI-0's
   iOS measurement** (which element scrolls, K-iframe stability, memory). Auditor:
   re-check that WI-0's deliverable (a revised technical design) adequately gates
   WI-1+.
3. **Relocate/fraction — RESOLVED, contract was stated WRONG (Gate-2 C1).**
   `#afterScroll` emits an **intra-section** fraction (`this.start /
   this.viewSize`, `:977`); `view.js#onRelocate` (`view.js:327-328`) feeds it to
   `SectionProgress.getProgress` (`progress.js:74-98`) which is the **canonical
   whole-book converter**; `foliate-host.js` (`:26-40`) forwards the converted
   value. The windowed `#afterScroll` must derive current section from scroll
   offset and still emit **intra-section** (NOT whole-book) — see §3.2. Emitting
   whole-book would double-apply and break Bug #260/#265.
4. **Does `view.js` need changes at all,** or can the renderer own all the new
   scrolled math while `view.js`'s `resolveNavigation`/`goToFraction`
   (`view.js:444-473`) keep delegating unchanged? (§5 assumes minimal `view.js`
   change; the media-overlay `getContents().find(...)` at `view.js:276-277` and
   `deselect` at `:484-486` DO interact with multi-doc `getContents()` — WI-7.)
   **RESOLVED round 2 (H1):** the navigation resolution stays minimal, BUT the
   **host-side selection handler** (`foliate-host.js:81-100`) was the missed
   multi-doc consumer — it reads `contents[0]` and builds the CFI from the first
   doc only. WI-7 now explicitly owns rewriting it to track the selection-owning
   mounted section (§5 foliate-host.js bullet / WI-7).
5. **Outer vs inner scroll contract — RESTATED, was BACKWARDS (Gate-2 C2).** The
   live code **ENABLES** the outer WKWebView scrollView in scrolled mode
   (`isScrollEnabled = (layoutFlow == "scrolled")`, `:244`/`:305`), while
   `paginator.js` reads/writes the inner `#container[scrollProp]`
   (`:780-801`,`:906-928`). Which element actually receives touch scroll on iOS
   is UNKNOWN — WI-0 must measure it (§3.3) before any windowing math is trusted.
6. **#235 boundary-epsilon reuse / split (Gate-2 M10).** The `atEnd`/`atStart`
   epsilons (`viewSize - end <= 2`, `start <= 0`, `:1130-1131`) drove the swap.
   Mount-ahead needs an **earlier** trigger; the exact-edge epsilon is RETAINED
   as a graceful hard-edge fallback. Both paths tested (WI-3).
7. **Concurrency / Sendable** on the Swift side: `FoliateScrolledWindowMath` is a
   pure value type (no actor concerns); confirm no new `@MainActor` hops are
   introduced in the relocate forward path.

---

## 11. Backward compatibility

- **Saved AZW3/MOBI positions** persist as whole-book `fraction` (progression)
  in `ReadingPosition`; restore is `goToFraction` (Bug #265). `goToFraction`
  resolves `fraction → (section, intra-anchor)` via `SectionProgress.getSection`
  (`view.js:469-473`); the windowed surface then mounts that section's window and
  translates `(index, intra-anchor) → continuous container offset` (WI-1b/WI-6
  rect translation) and lands there — **same persisted data, same restore API,
  same SectionProgress conversion**. Saved CFIs remain a fallback only
  (unchanged).
- **Paged mode** is byte-for-byte unaffected (single-`#view` branch retained).
- **Bilingual** (`FoliateBilingualContainerView`) continues via `getContents()`
  + per-section enumerate (WI-7).
- **Existing readers / older app data** — no schema change; the change is
  rendering-only inside the vendored bundle.
- **Fixed-layout** Foliate books unaffected (gated out).

---

## 12. Verification strategy (Gate-5)

- **Foundational WI-1** — unit tests both sides (Swift + Node) + parity guard;
  no device verification required.
- **Behavioral WIs (WI-2..WI-7)** — slice-verify the *mechanism* via the
  live-WKWebView DOM test + the WI-8 DebugBridge `scroll-boundary` driver
  (multiple mounted sections, monotonic `scrollTop` across a boundary, stable
  visible rect on evict). Record in each PR.
- **Final WI-8 — full acceptance pass.** Device/Simulator (iPhone 17 Pro) with
  a real AZW3 fixture:
  - `mini-azw3` (DebugFixtureCatalog) for the CU-free harness mechanism checks
    + DebugBridge boundary driving (`vreader-debug://` seed/open/settle +
    the new `scroll-boundary` driver).
  - A **multi-section / large CJK** AZW3 from local `test-books/`
    (`被讨厌的勇气.azw3`, `道诡异仙`) for the **visual smoothness** judgment —
    scroll across a boundary, observe no jump/flash/hitch. **This is visual →
    needs CU / on-device eyes**, not the CU-free harness (rAF/scroll observers
    paused on the virtual display — project memory).
  - Reopen-at-saved-position (Bug #265) + TOC tap landing + bottom-chrome
    fraction (Bug #260) re-verified over the continuous surface.
  - Evidence file: `dev-docs/verification/feature-73-<YYYYMMDD>.md` (per
    `dev-docs/verification/SCHEMA.md`) flips the row `DONE` → `VERIFIED`.

---

## 13. Docs sync (per-PR, rule 24)

- **`docs/architecture.md` Foliate section — MANDATORY EARLY UPDATE (Gate-2
  M12).** The section is currently **stale**: lines `:111`, `:113-117`, `:134`,
  `:171` still describe `FoliateViewBridge` / `FoliateViewCoordinator` /
  `FoliateReaderHost` / `FoliateReaderViewModel` as the Foliate bridge, but the
  **live load path is `FoliateBilingualContainerView → FoliateSpikeView`**
  (see `:71-73`, `:203`). This stale text mis-states the very files this feature
  edits, so the correction is **not deferred to WI-8** — it lands as an early doc
  commit (with WI-1a, the first paginator-touching WI) so every downstream WI
  reads an accurate map. The update: (1) correct the Foliate-js Bridge section to
  name `FoliateSpikeView` (+ `FoliateBilingualContainerView` wrapper) as the live
  host; (2) note the **vendored fork** — scrolled mode now renders a windowed
  multi-section continuous surface (diverges from upstream foliate-js, which is
  single-section, #1455).
- `README.md` — only if the Features list calls out AZW3 scroll behavior
  (likely no change).

---

## Gate-2 audit — round 1

**Verdict: MAJOR GAPS.** Independent Codex/cc-suite audit of plan v1 returned
major gaps centered on wrong/backwards model assumptions and an under-stated
coupling cost. The body above (v2) has been revised to resolve every
Critical/High/Medium finding. **The round-1 revisions below OVERRIDE any
conflicting earlier body text** — where v1 prose and these revisions disagree
(notably the scroll contract, the "whole-book fraction" relocate, the "flex
column already exists" claim, and the "small generalization" framing), the
revision is authoritative for a re-auditor.

### Findings (verbatim severity / issue)

| ID | Sev | Issue | Fix applied |
|----|-----|-------|-------------|
| C1 | Critical | Relocate "whole-book fraction" is WRONG. `Paginator.#afterScroll` (`paginator.js:977`) passes **intra-section** `fraction` to `view.js:327`; `SectionProgress.getProgress` (`progress.js:74`) converts it to whole-book. Passing whole-book double-applies + breaks Bug #265. | §3.2, §10.3, R3, WI-1/WI-5: renderer emits **intra-section** fraction; `SectionProgress` stays the canonical whole-book source; `#afterScroll` derives current section from scroll offset but still emits intra. `wholeBookFraction` helper removed from §6. |
| C2 | Critical | Swift scroll contract stated BACKWARDS. Real code ENABLES the WKWebView scrollView in scrolled mode: `isScrollEnabled = (layoutFlow == "scrolled")` (`FoliateSpikeView.swift:244`). Foliate's `#container` (`:506-515`) also has its own scroll listener. Which element receives touch scroll on iOS is UNKNOWN + central. | §3.3, §5, §10.5: contract corrected; WI-0 must first MEASURE (on iOS) which element scrolls + whether nested `#container` stays stable with K iframes. All behavior WIs blocked on that measurement. |
| H3 | High | Wrong Swift path: `FoliateSpikeView.swift` is under `vreader/Views/Reader/`, NOT `vreader/Services/Foliate/`. | §5 Swift bullet path corrected. |
| H4 | High | Single-`#view` invariant far broader than admitted: `render`, `viewSize`, `#getVisibleRange`, `#getRectMapper`, `setStyles`, `focusView`, `destroy`, background, media-overlay all deref one `#view`. | New §1.1 inventories every consumer; approach reframed as a **scoped fork** (not a small generalization); new WI-1a inventories + branches every consumer before behavior work. |
| H5 | High | `scrollToAnchor`/`#scrollToRect` (`:936`/`:898`) map only inside the one current view; they don't add a mounted-section offset. TTS + CFI/TOC anchors land wrong across iframes. | New foundational **WI-1b** (anchor coordinate translation rect→container coords) BEFORE navigation-landing WI-6; `rectToContainerOffset` helper added to §6. |
| H6 | High | "Flex column already exists" is wrong: `View.#element` is `flex:0 0 auto` but `#container` is NOT `display:flex` (`:506`/`:226`). Horizontal may block-stack; vertical-writing/RTL won't be correct by assumption. | §3.2 corrected: `#container` is a grid cell; WI-0 defines explicit per-writing-mode container layout (horizontal LTR, horizontal CJK, vertical-writing/RTL). |
| H7 | High | K=3 mounted iframes is a real memory/perf risk for large CJK AZW3 (full iframe + layout + fonts + images + ResizeObserver + overlay SVG + styles + selection each). Mitigation too soft. | WI-0 + WI-4 hard memory/perf gate with large local AZW3 fixtures; **adaptive K=2/3** by measured section size. R4 hardened. |
| H8 | High | `setStyles` (`:1166`) only applies to `this.#view`; mounted non-current views miss theme/font updates. | §3.2/§5/WI-2: style lifecycle applies cached `#styles` + `fonts.ready→expand()` to ALL mounted views (current + future mounts); new style-propagation live-DOM test. |
| M10 | Medium | Bug #235 regression risk higher: `#maybeCrossSectionBoundary` (`:1126`) uses exact-edge detection; windowing needs earlier prefetch + different fallback. | WI-3 splits prefetch-near-edge (earlier threshold) from hard-edge fallback (retained `:1130-1131` epsilons); both tested. R2/§10.6 updated. |
| M11 | Medium | WI-7 (`getContents` multi-doc) is real impl/test work for overlay/TTS/bilingual/selection/media-overlay (`view.js:276`/`:484` latent assumptions), not "confirm". | WI-7 reframed as implementation+tests; §5 getContents bullet + §5 view.js bullet enumerate the multi-doc consumers; live-DOM tests added. |
| M12 | Medium | `docs/architecture.md` Foliate section stale (names `FoliateViewBridge`/`FoliateViewCoordinator`; live path is `FoliateBilingualContainerView → FoliateSpikeView`). | §13: architecture.md correction is a MANDATORY EARLY doc step (lands with WI-1a), not deferred to WI-8. |
| M13 | Medium | WI-1 (pure math) too early if WI-0 invalidates the model. | WI-0 reframed as a **design gate** whose deliverable is a revised technical design; WI-1+ explicitly gated on it. §3 + §7 updated. |
| L14 | Low | JS-only risk + DebugBridge strategy good; add live-DOM tests for anchor coord translation + style propagation. | Two new live-DOM tests added to §8 (anchor translation, style propagation). |

### Round-1 revisions applied (override map)

- **Scroll contract (C2):** v1 §5/§10.5 said the WKWebView scrollView is *disabled*
  in scrolled mode. **OVERRIDDEN** — it is ENABLED (`:244`); the true scroller is a
  WI-0 measurement. Use §3.3 / §5 / §10.5 v2.
- **Relocate fraction (C1):** v1 §3.2/§10.3 said the renderer emits whole-book
  fraction. **OVERRIDDEN** — renderer emits intra-section; `SectionProgress`
  converts. Use §3.2 C1 block / §10.3 v2 / §6 (no `wholeBookFraction`).
- **Container layout (H6):** v1 §3.2 said "a flex column already exists."
  **OVERRIDDEN** — `#container` is a grid cell; WI-0 defines per-writing-mode
  layout. Use §3.2 H6 block.
- **Approach framing (H4):** v1 §3 said the design "generalizes the renderer" (a
  small change). **OVERRIDDEN** — it is a scoped fork gated on WI-0; the
  single-`#view` coupling is pervasive. Use §1.1 + §3 feasibility-gate note.
- **WI list:** v1 had WI-0..WI-8 with WI-0 a throwaway spike and WI-7 a "confirm."
  **OVERRIDDEN** — WI-0 is a design gate; new WI-1a (`#view` inventory) and WI-1b
  (anchor translation) are foundational; WI-7 is implementation+tests; WI-8 folds
  in the mandatory-early architecture.md note. Use §7 v2 table.

Open items carried to round 2 (auditor re-check): the exact `#view` field
declaration line; whether `view.js` navigation resolution truly needs zero change
once the renderer owns the new math; and WI-0's iOS scroller-measurement
methodology (the central feasibility unknown).

---

## Gate-2 audit — round 2

**Verdict: NEEDS REVISION (1 High).** The independent Codex/cc-suite round-2 audit
**confirmed every round-1 fix is correctly resolved** (C1 intra-section fraction,
C2 scroll contract, H3 path, H4 scoped-fork + WI-1a, H5 WI-1b anchor translation,
H6 grid-not-flex container, H7 memory gate + adaptive K, H8 style lifecycle, M10
prefetch/fallback split, M11 WI-7 impl+tests, M12 early architecture.md, M13 WI-0
design gate) and confirmed the **size-model open question is consistent with no
drift** — the relocate `index`-from-live-offset vs `fraction`-from-`SectionProgress`
split (§3.2 caveat) holds, the live measured iframe sizes (WI-1 layout) and the
spine-estimated `SectionProgress.sizes` (whole-book fraction) are correctly kept
on separate channels, no double-application. It found exactly **one open High**.

### Findings (verbatim severity / issue)

| ID | Sev | Issue | Fix applied |
|----|-----|-------|-------------|
| H1 | High | WI-7 still misses the real multi-doc **selection** consumer in `vreader/Services/Foliate/JS/foliate-host.js` (~line 81). The host's selection handler always reads `contents[0]` and computes the CFI from that **first** mounted doc/index. With multiple sections mounted in the window, selecting text in section N+1 can serialize the **wrong CFI/index** or miss the selection. The plan currently names only `view.js#deselect` for selection, leaving highlight-creation / selection-popover routing under-specified. | §5 new `foliate-host.js` bullet + §5 getContents bullet + §10.4 + WI-7: the host selection handler (`:76-109`) is added as a named multi-doc consumer. WI-7 now explicitly rewrites it to identify the mounted entry that OWNS the active selection (iterate `getContents()`, pick the `{doc, index}` whose `doc.getSelection()` is non-collapsed with a range), emit that section's `index`/`href`, and build `view.getCFI(ownerIndex, range)` (`view.js:429-432`) against the owning doc — not always `contents[0]`. New live-DOM test: create a highlight from a selection in a **non-first** mounted section, assert the correct section index/CFI + that the highlight renders on the right section. |

### Round-2 revision applied (override map)

- **WI-7 selection scope (H1):** v2 named only `view.js#deselect` (`:484-486`,
  which merely clears) and the media-overlay `find` as the selection-related
  multi-doc consumers. **OVERRIDDEN** — the load-bearing selection consumer is the
  **host** handler in `foliate-host.js` (`:76-109`), which reads `contents[0]`
  (`:83`) and builds the CFI from `contents[0].index` (`:92`). WI-7 + the new §5
  `foliate-host.js` bullet now own rewriting it to track the selection-owning
  mounted section. The round-2 (and any later round-3) revisions OVERRIDE
  conflicting earlier body/round-1 text wherever WI-7's selection scope is
  described.

Source facts verified against current source (re-checkable by a re-auditor):
`foliate-host.js` selection handler `:76-109`; `getContents()` read at `:81`;
`const { doc, index } = contents[0]` at `:83`; `doc.getSelection()` at `:84`;
`view.getCFI(index, range)` at `:92`; the per-section `selectionchange` attach
in the `load` listener at `:105-108`. `view.js#getCFI` roots the CFI in
`this.book.sections[index].cfi` at `view.js:429-432`; `view.js#deselect` iterates
all `getContents()` docs at `view.js:484-486`.

Confirmation: round 2 found **no other** open findings; all round-1 C/H/M fixes
re-verified resolved, and the size-model open question is consistent with no
drift. H1 is the sole change for round 3.

---

## Revision history
- v3 (2026-05-30) — Gate-2 round-2 audit returned **NEEDS REVISION (1 High)**.
  Round 2 confirmed all round-1 C/H/M fixes resolved and the size-model open
  question consistent (no drift). The single round-2 High (H1) was addressed:
  WI-7's selection scope now explicitly includes the **host-side** multi-doc
  selection handler in `foliate-host.js` (`:76-109`) — the real
  highlight-creation / selection-popover consumer that read `contents[0]` and
  built the CFI from the first mounted doc. WI-7 rewrites it to track the
  selection-owning mounted section (correct `index`/`href`/CFI), with a new
  live-DOM test for a highlight created from a selection in a non-first mounted
  section. §5 (new `foliate-host.js` bullet, getContents bullet), §10.4, WI-7
  updated. Awaiting Gate-2 round 3 re-check.
- v2 (2026-05-30) — Gate-2 round-1 audit returned **MAJOR GAPS**. Body revised to
  resolve all C/H/M findings (C1 intra-section fraction, C2 scroll contract,
  H3 path, H4 scoped-fork + WI-1a, H5 WI-1b anchor translation, H6 grid-not-flex
  container, H7 memory gate + adaptive K, H8 style lifecycle, M10 prefetch/fallback
  split, M11 WI-7 impl+tests, M12 early architecture.md, M13 WI-0 design gate).
  WI list grew to WI-0/1/1a/1b/2..8. Awaiting Gate-2 round 2.
- v1 (2026-05-30) — initial Gate-1 plan. Awaiting Gate-2 independent audit
  (cc-suite / Codex). Audit must verify §10 open questions, especially the line
  ranges (§10.1) and windowing feasibility (§10.2).

---

## WI-0 progress log (2026-05-30, Gate-3 start)

**(a) Which element scrolls in Foliate scrolled mode — code-derived verdict: the inner `#container`.**
The audit's C2 asked whether the outer WKWebView scrollView or the inner shadow-DOM `#container` is the real scroller. The JS source settles it: in scrolled mode `:host([flow="scrolled"]) #container` gets `overflow: auto` (`paginator.js:511-514`) and owns the scroll listeners (`paginator.js:559, 575`) that drive `#afterScroll` + `#maybeCrossSectionBoundary` — i.e. the **inner `#container` is the scroll element**. The outer WKWebView scrollView is left `isScrollEnabled = true` (`FoliateSpikeView.swift:244`) but the rendered document is sized to the viewport (the `#container` scrolls internally), so its `contentSize ≈ bounds` and it has nothing to scroll. **This is the feasibility unlock for the windowed model**: mounting K sections inside `#container` and letting that one inner scroller move continuously is the natural substrate; the outer scrollView is a near-no-op (the `FoliateSpikeView` comment claiming "the outer scrollView IS the scroller" is misleading — corrected in the Gate-2 C2 record).

**Empirical iOS confirmation — instrumentation built, BLOCKED on AZW3 fixture.**
A throwaway `UIScrollViewDelegate.scrollViewDidScroll` was added to `FoliateSpikeView.Coordinator` (DEBUG-gated) logging the outer scrollView's `contentOffset.y`/`contentSize` to category `Feat73WI0`; build SUCCEEDED + installed on iPhone 17 Pro Sim. The plan was to open an AZW3 in scrolled mode, scroll via CU, and confirm the outer `contentOffset.y` stays ≈0 (inner `#container` scrolls). **This is blocked**: the `vreader-debug://seed?fixture=mini-azw3` DebugBridge fixture silently fails to import an AZW3 into the library (consistently, all session) — the resource IS bundled (`vreader.app/DebugFixtures/mini-azw3.azw3`, 128 KB) and the seed resolves + calls `importer.importFile`, so the failure is in the AZW3 import path (error lands in `snapshot.lastError`, not surfaced to the host openurl). Filed as a DevTools/Verification bug. Without a Foliate AZW3 in scrolled mode, none of WI-0 (a)-empirical / (b) multi-section coexistence / (c) expand-no-shift / (d) memory gate can be measured CU-free.

**(b)(c)(d): not yet measured** — gated on the AZW3 fixture fix (or a sim-transferred real AZW3).

**Preliminary WI-0 verdict: GO-leaning** on the windowed model (the inner-`#container`-scroller finding is the key de-risk), but the empirical multi-iframe coexistence + memory measurements remain — WI-0 stays OPEN until the AZW3 fixture is unblocked and (a)-empirical/(b)/(c)/(d) are run on-device.

### WI-0 update (2026-05-30, later) — measurement (a) EMPIRICALLY CONFIRMED

The AZW3 fixture imports fine (the earlier "#288 blocker" was an observation error — the `mini-azw3` AZW3 and the EPUB Masque fixture share the title "The Masque of the Red Death"; #288 closed not-a-bug). With the AZW3 open in the Foliate **scrolled** reader on iPhone 17 Pro Sim (instrumented build), a finger-drag scroll:
- **scrolled the content and crossed Chapter 1 → Chapter 2** (the current per-section swap — the very jump this feature removes), AND
- the outer WKWebView scrollView's `scrollViewDidScroll` fired **ZERO times** (instrumentation category `Feat73WI0`, 0 OUTER lines).

**Verdict on (a): CONFIRMED both code-derived AND empirically — the outer WKWebView scrollView is a no-op in scrolled mode; the inner shadow-DOM `#container` (`overflow:auto`) is the sole scroller.** This is the windowed model's substrate de-risk: mounting K sections inside `#container` and letting that one inner scroller move continuously is the right design. **GO on (a).**

**Remaining WI-0: (b) multi-section coexistence, (c) expand-no-shift, (d) memory gate** — these require the experimental mounting code (mount the next section contiguously in `#container`, measure coexistence + memory with large CJK AZW3). Not yet run. WI-0 stays OPEN until (b)/(c)/(d) land, but (a)'s confirmation materially de-risks the approach.
