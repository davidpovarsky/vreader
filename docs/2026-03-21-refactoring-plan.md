# Refactoring Plan

Prerequisite for continuing bug fixes and feature implementation.

## Problem

Rapid feature development across 6 phases accumulated debt that causes recurring bugs:

- Container views have 12-15 `@State` variables each — hard to trace state bugs
- TXT/MD share highlight/annotation logic via `ReaderNotificationModifier` but EPUB/PDF don't use it
- PersistenceActor extensions (1,035 lines) have partial test coverage — collections and sessions tested, highlights/bookmarks not
- Bridges (467-537 lines) each handle 3-5 concerns
- Reader ViewModel lifecycle (open/close/background/foreground) duplicated across 4 VMs

## Phases

### Phase R1 — Persistence & Integration Tests

**Goal**: Safety net for subsequent refactors.

**Scope**:

- Test `PersistenceActor+Highlights.swift` (161 lines) — create, fetch, delete, deduplication
- Test `PersistenceActor+Bookmarks.swift` — create, fetch, delete, rename
- Integration tests: TXT highlight create → delete → visual verify
- Integration tests: EPUB page-load highlight restore → remove
- Integration tests: PDF annotation create → restore → delete

**Note**: Collections and sessions already have tests (`CollectionPersistenceTests`, `SwiftDataSessionStoreTests`). Don't duplicate.

**Acceptance**: Highlight/bookmark persistence > 80% coverage. Integration test suite for each format's highlight flow.

**Effort**: Medium.

### Phase R2 — Extend Notification Modifier to EPUB/PDF

**Goal**: Unify notification handling across all 4 formats.

**Note**: `ReaderNotificationModifier` already handles 5 notifications for TXT/MD with tests (`ReaderNotificationHandlerTests`). Extend it, don't replace it.

**Scope**:

- Adapt `ReaderNotificationModifier` to support EPUB highlight flow (JS-based)
- Adapt it to support PDF annotation flow (PDFAnnotation-based)
- Move EPUB's 6 scattered `.onReceive` handlers into the modifier
- Move PDF's handlers into the modifier
- Reduce each container to ≤2 direct `.onReceive` calls

**Acceptance**: All 4 containers use `ReaderNotificationModifier`. Each has ≤2 direct `.onReceive`.

**Effort**: Medium.

### Phase R3 — Shared Text Reader UI State ✅

**Goal**: Eliminate duplicate UI state between TXT and MD containers.

**Scope — SHARED** (move to `TextReaderUIState`):

- `scrollToOffset`, `highlightRange`, `highlightIsTemporary`
- `persistedHighlightRanges`, `pendingAnnotationInfo`, `annotationNoteText`
- Pagination state (pageNavigator, pagedCurrentPage)
- `refreshPersistedHighlights()`

**Scope — KEEP SEPARATE** (format-specific):

- TXT: chunking, chunk offsets, background attr-string building, large-file detection
- MD: pre-rendered attributed string, MD parser state
- Locator factories (TXT raw text vs MD rendered text)

**Acceptance**: TXT and MD containers share one UI state object. No behavior change.

**Effort**: Medium.

### Phase R4a — Highlight Contract + Format Adapters ✅

**Goal**: Define a shared highlight protocol without merging implementations.

**Scope**:

- Define `HighlightRenderer` protocol: `apply(record)`, `remove(id)`, `restore(records)`
- TXT/MD adapter: wraps existing NSRange highlight logic
- EPUB adapter: wraps existing JS injection logic
- PDF adapter: wraps existing PDFAnnotation logic + **retain highlightId → [PDFAnnotation] mapping** (needed for delete — bug #87)
- Wire `readerHighlightRemoved` through all 4 containers via adapters

**Acceptance**: Bug #87 (PDF delete) fixed. All formats respond to `readerHighlightRemoved`.

**Effort**: Medium.

### Phase R4b — Highlight Orchestration ✅

**Goal**: Single coordinator for highlight lifecycle.

**Scope**:

- `HighlightCoordinator` owns: create, delete, restore, refresh-after-import
- Calls format-specific `HighlightRenderer` adapter
- Handles persistence via `PersistenceActor+Highlights`
- Replaces per-container highlight logic

**Acceptance**: Highlight bug fixes touch `HighlightCoordinator` + adapter, not container views.

**Effort**: Medium.

### Phase R5a — Container View Slimming ✅

**Goal**: Container views under 350 lines.

**Scope**:

- `ReaderContainerView` (619 lines): extract deferred setup to `ReaderSetupCoordinator`
- `EPUBReaderContainerView` (616 lines): extract spine nav + highlight sheet to subviews
- `TXTReaderContainerView` (515 lines): reduced by R3

**Acceptance**: No container view exceeds 350 lines.

**Effort**: Medium. Pure extraction — no logic changes.

### Phase R5b — Bridge Slimming ✅

**Goal**: Bridge files under 400 lines.

**Scope**:

- `TXTChunkedReaderBridge` (537 lines): extract chunk manager
- `EPUBWebViewBridge` (535 lines): extract JS injection to `EPUBJSInjector`
- `TXTTextViewBridge` (467 lines): extract offset mapping (already partial via `TXTOffsetMapper`)

**Acceptance**: No bridge file exceeds 400 lines.

**Effort**: Medium. Pure extraction.

### Phase R6 — Shared Reader ViewModel Lifecycle ✅

**Goal**: Eliminate duplicated open/close/background/foreground logic across 4 VMs.

**Scope**:

- Extract shared lifecycle (session tracking, position save/restore, stats recompute) to `ReaderLifecycleBase` protocol or base class
- TXT/MD/EPUB/PDF ViewModels adopt it
- Format-specific open/close logic stays in each VM

**Acceptance**: Adding a new lifecycle hook (e.g., iCloud sync on close) touches 1 file, not 4.

**Effort**: Large.

## Execution Order

```
R1 → R2 → R3 → R4a → R4b → R5a → R5b → R6
```

R1 first (safety net). R2-R4 reduce complexity. R5 is mechanical cleanup. R6 is optional polish.

## Rules

- Zero behavior changes in any phase
- Unit tests must pass after every phase (`xcodebuild test -only-testing:vreaderTests`)
- Skip UI tests during refactoring — they test behavior, not structure, and add 10+ minutes per run
- Read `docs/architecture.md` before starting any phase
- Update `docs/architecture.md` after completing each phase

## Testing Strategy

- **Now**: Add geometry assertions to UI tests (free, catches layout regressions like bug #62)
- **After UI settles**: Add `swift-snapshot-testing` for reader chrome/layout baselines (16-24 snapshots)
- **Pre-release only**: Run UI tests on 2 simulators — iPhone 17 Pro (Dynamic Island) + iPhone SE (no notch)
- **Default simulator**: iPhone 17 Pro (Dynamic Island — catches safe area bugs like #73)

