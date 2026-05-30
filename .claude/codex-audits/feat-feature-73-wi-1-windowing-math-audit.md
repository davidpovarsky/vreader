---
branch: feat/feature-73-wi-1-windowing-math
threadId: codex-exec-2026-05-30-wi73-gate4
rounds: 2
final_verdict: ship-as-is
date: 2026-05-30
---

# Gate-4 audit — Feature #73 windowed Foliate continuous-scroll surface

Independent Codex audit (`codex exec --sandbox read-only`) of the windowed diff
(`paginator.js` +312, `foliate-host.js` +16, `FoliateScrolledWindowMath.swift`
+88). The whole surface is gated behind `#windowedScroll` (shipped `false`); a
flag-off parity suite passes. Verdict: **follow-up-recommended** — no Critical;
the round-1 fixes below land the tractable findings; 3 High findings are deferred
to round 2 and are **blockers for the default-ON flag flip** (not for the
flag-off shipped state).

## Findings + resolution

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | paginator.js:#mountSection | High | Not generation-safe: a navigation/flow change during an awaited `load()` can resume a stale mount into the new window. `#mountingIndices` only dedups same-index. | **DEFERRED → round 2.** Mitigated partly: `#createView` + `destroy()` now clear `#mountingIndices`. Full fix needs a monotonic window-generation token captured across awaits. |
| 2 | paginator.js:#mountSection | High | Neighbour sections don't dispatch the `load`/`create-overlayer` lifecycle, so view.js never wires their docs (selection listeners, tap/link handlers, overlays) — neighbour-section selection/highlights won't fire. | **DEFERRED → round 2.** The selection source-doc + owner-finding fixes are in place but only take effect once neighbours dispatch `load`. Keystone round-2 item. |
| 3 | paginator.js (helpers) | High | Windowed math is vertical-scroll-only (`top`/`height`/`scrollTop`); vertical-WRITING scrolled mode scrolls horizontally → wrong resolution/restore. | **FIXED.** Windowing scoped to horizontal writing: `#ensureWindow`, the `#maybeCrossSectionBoundary`/`#afterScroll` windowed branches, `#viewRelativeStart`, and both scroll-offset additions now bail on `this.#vertical` → vertical writing falls back to the proven per-section swap (window stays empty). |
| 4 | paginator.js:#scrollPrev/#scrollNext | High | Programmatic prev/next use single-section assumptions; in windowed mode `start` is container-absolute vs section `viewSize`, so `#scrollNext` can false-positive "at end" and `#goTo` (tearing down the window) instead of scrolling. | **DEFERRED → round 2.** Affects auto-advance (Bug #235) + side-tap page-turn in windowed mode. Needs a windowed branch that scrolls within the mounted surface and only `#goTo`s at true book/window ends. |
| 5 | foliate-host.js selection | Medium | Owner detection picked the first non-collapsed selection among all mounted docs — a stale selection in another iframe could win. | **FIXED.** `handleSelection(sourceDoc)` now prefers the doc that fired `selectionchange`, falling back to scanning. |
| 6 | paginator.js:setStyles | Medium | Updated only `#view`; mounted neighbours kept old theme/typography until evicted. | **FIXED.** Iterates `#mountedViews()`, applies the style pair + re-expands each. |
| 7 | paginator.js:render | Medium | `render()` rerenders only `#view`; neighbours keep stale dimensions on resize/margin/flow change → invalidates offset math. | **DEFERRED → round 2** (pairs with #2's lifecycle work; lower-risk while flag off). |
| 8 | paginator.js:#createView | Medium | Cleared `#scrolledViews` but didn't `sections[i].unload()` on full navigation teardown → retained section resources. | **FIXED.** Now destroys + removes + unloads each neighbour and clears `#mountingIndices`. |
| 9 | paginator.js:destroy | Medium | Destroyed only `#view`; mounted neighbours' Views (+ their ResizeObservers) leaked on reader close. | **FIXED.** Destroys/removes/unloads all `#scrolledViews`, clears `#mountingIndices`, then `#view`. |
| 10 | paginator.js:#windowedResolve | Low | 1px boundary bias promotes to the later section 1px early vs the Swift helper's exact-boundary rule. | **ACCEPTED** as intentional hysteresis; documented here. Swift helper models exact boundary for its unit tests; JS adds 1px slack to match the scroll-settle epsilons. |
| 11 | FoliateScrolledWindowMath.swift | Low | Pure helper models positive vertical offsets only; won't catch vertical-writing sign bugs. | **ACCEPTED** — finding #3 scopes vertical writing out of windowing; the Swift helper is intentionally horizontal-writing-only. WI-8 will add windowed parity tests. |

## Round-1 verdict

5 findings fixed (1 High + 4 Medium), 2 Low accepted with rationale, 3 High +
1 Medium deferred to round 2 as **default-ON-flip blockers**. The flag-off shipped
state is unaffected (parity suite green). The flag stays OFF until round 2 closes
findings #1, #2, #4 (#7 rides with #2).

## Round 2 (2026-05-30)

Re-audit of the round-1 fixes + verification of the round-2 changes.

**Round-1 findings confirmed RESOLVED, no regressions:** H1 (generation checks
prevent stale mounts dispatching lifecycle / staying in `#scrolledViews`; `finally`
clears `#mountingIndices`), H2 (neighbour `load`/`create-overlayer` dispatch is
per-doc and safe; Swift `section-load` doesn't mutate current-section state;
promotion is pointer-only so no double-wiring), H4 (prev/next vertical-guarded,
true book-end handled), M7 (flag-off parity intact), selection owner correct.

**New findings (all FIXED this round):**

| # | file:line | sev | issue | fix |
|---|---|---|---|---|
| R2-1 | paginator.js:#mountSection insert | High | Forward-neighbour insertion filtered only `#scrolledViews` (excludes `#view`); once the window had slid with `#view` in the middle, mounting a forward section could land it BEFORE `#view` → DOM order `[1,3,2]` while sorted indices still READ `[1,2,3]` (masked from index-only checks). | Insert against ALL mounted views (anchor + neighbours) sorted by real index: place after the highest-index mounted view `< index`, else before the lowest. **Verified flag-on CU-free**: after sliding the window, ordering mounted iframes by actual `frameElement.top` gives `[1,2,3]` monotonic. |
| R2-2 | paginator.js stale-abort | Medium | Stale/failed mount unloaded the section by index even if the current generation re-owned it (anchor or re-mounted neighbour) → could revoke a fresh load's resources. Dormant for MOBI (no `unload`) but incorrect lifecycle. | `#unloadIfUnowned(index)`: unload only if `index` is neither `#index` nor a mounted neighbour. Used at both stale-abort sites + the load-failure catch. |
| R2-3 | paginator.js load-failure catch | Medium | A failed `view.load` removed the phantom view but never unloaded the section → repeated failures leak loader refs. | catch now `view.destroy()` + `#unloadIfUnowned(index)` before rethrow. |

## Verdict

Two independent audit rounds; every Critical/High/Medium resolved. Low findings
(1px boundary hysteresis, Swift horizontal-only helper) accepted with rationale.
Flag-off parity GREEN; flag-on verified CU-free (window mount/slide, neighbour
overlayers, next/prev no-teardown, DOM order monotonic, position restore) plus the
earlier full CU visual verification of the core crossing. **Verdict: ship-as-is.**
The default-ON flag flip is now unblocked.
