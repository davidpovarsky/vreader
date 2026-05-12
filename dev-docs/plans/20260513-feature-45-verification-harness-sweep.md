# Feature #45 — Verification Harness Sweep — Implementation Plan

**Status**: Gate 1 (Plan)
**Date**: 2026-05-13
**Feature row**: `docs/features.md` § Feature #45 — status `PLANNED`
**GH Issue**: (assigned at PLANNED time — see features.md Notes column)

---

## Revision History

| Rev | Date       | Author       | Change                        |
|-----|------------|--------------|-------------------------------|
| v1  | 2026-05-13 | Claude Agent | Initial plan draft            |
| v2  | 2026-05-13 | Claude Agent | Manual audit fixes: corrected Feature #27 replacement rules UI path (global Settings, not reader panel); corrected Chinese conversion label to "Chinese Text"; clarified auto-page-turn toggle AID strategy; added `settingsView` AID to verified list |

---

## 1. Problem

`docs/features.md` and `docs/bugs.md` carry a monotonically-growing "Needs device verification" backlog. Every release adds entries faster than humans can verify old ones. The repetitive UI-driving work that verification requires is both error-prone and time-consuming for humans. The result: tracker statuses lie (`DONE` means "code shipped, untested"), regressions go undetected, and pre-release manual passes balloon in scope.

13 of the backlog items are simulator-automatable using XCUITest and the existing DebugBridge (`vreader-debug://`) harness introduced in feature #44. This plan builds the harness to auto-verify those 13 items, leaving only the irreducible real-device items in the human checklist.

The two items that remain manual after this feature:
- **Feature #26** — TTS audio quality (no programmatic way to QA voice quality on simulator)
- Any flow requiring real iCloud, real haptics, or real Apple ID

---

## 2. Surface Area

### New Files Created

#### `vreaderUITests/Verification/` — verification test suite root

All tests use `verify_feature_<NN>_<slug>` naming convention so failures map mechanically to tracker rows.

---

**`vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests.swift`** (proving-ground item 1)

```
class Feature37PerBookSettingsVerificationTests: XCTestCase
  func verify_feature_37_perbook_settings_toggle_isolated_to_book()
    // open book A → settings → "Custom settings for this book" toggle ON
    // → change font size → back to library → open book B
    // → assert book B has original font size (not book A's override)
    // AID: "readerSettingsPanel", Toggle "Custom settings for this book"
    // AID: no unique ID on the toggle — locate via label string

  func verify_feature_37_perbook_settings_persists_across_reopen()
    // open book A → per-book ON → change font to XXL → back → reopen book A
    // → assert settings panel shows XXL font persisted
```

Key AccessibilityIDs used: `readerSettingsButton` (→ `readerSettingsPanel`), label-match on "Custom settings for this book" toggle.

---

**`vreaderUITests/Verification/Feature34CollectionsVerificationTests.swift`** (proving-ground item 2)

```
class Feature34CollectionsVerificationTests: XCTestCase
  func verify_feature_34_create_collection_appears_in_sidebar()
    // collectionsToolbarButton → newCollectionButton → newCollectionTextField
    // → type "Test Suite Collection" → addCollectionButton → filterDoneButton
    // → reopen sidebar → assert filterAllBooks + "Test Suite Collection" row exists

  func verify_feature_34_add_book_to_collection_filters_library()
    // create collection → long-press bookCard → "Add to Collection" → select
    // collection → filterAllBooks sidebar → tap collection filter → assert only
    // the tagged book is visible in library grid
```

Key AccessibilityIDs used: `collectionsToolbarButton`, `newCollectionButton`, `newCollectionTextField`, `addCollectionButton`, `filterDoneButton`, `filterAllBooks`, `bookCard_<fingerprintKey>`.

---

**`vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`** (proving-ground item 3)

```
class Feature11EPUBHighlightVerificationTests: XCTestCase
  func verify_feature_11_epub_highlight_happy_path()
    // seed mini-epub3 → open → long-press word → Highlight menu → tap
    // → annotations panel → Highlights tab → assert highlight row exists
    // → close+reopen → assert highlight row still exists (persistence)
    // AID: "epubReaderContent", "readerAnnotationsButton", "annotationsPanelSheet",
    //       "Highlights" tab button, "highlightEmptyState" (must be absent)

  func verify_feature_11_epub_highlight_regression_bug77_buffering_race()
    // Specifically targets the JS buffering race (bug #77): rapid long-press
    // before DOMContentLoaded settles → verify highlight is still created
    // Uses vreader-debug://settle to gate on ready state before action
```

Key AccessibilityIDs used: `epubReaderContent`, `epubReaderContainer`, `readerAnnotationsButton`, `annotationsPanelSheet`, `highlightEmptyState` (must disappear), `highlightRow-<id>`.

---

**`vreaderUITests/Verification/Feature21PaginatedModeVerificationTests.swift`**

```
class Feature21PaginatedModeVerificationTests: XCTestCase
  func verify_feature_21_paged_mode_shows_paged_view()
    // seed books → open TXT book → readerSettingsButton → readingModeSection
    // → pick "Paged" → assert "nativeTextPagedView" appears
    // AID: "readerSettingsPanel", Picker "Reading Mode", "nativeTextPagedView"

  func verify_feature_21_paged_mode_page_navigation()
    // in paged mode → tap right zone → assert page number increments
    // AID: "nativeTextPagedView", "readingProgressLabel"
```

Key AccessibilityIDs used: `readerSettingsButton`, `readerSettingsPanel`, `nativeTextPagedView`, `readingProgressLabel`.

---

**`vreaderUITests/Verification/Feature23TXTTocVerificationTests.swift`**

```
class Feature23TXTTocVerificationTests: XCTestCase
  func verify_feature_23_txt_toc_populated_for_chinese_chapters()
    // seed war-and-peace (has chapter headers) → open → readerAnnotationsButton
    // → Contents tab → assert tocEmptyState is absent (entries exist)
    // AID: "annotationsPanelSheet", "Contents" tab button, "tocEmptyState" (must be absent),
    //       "tocRow-<id>" prefix

  func verify_feature_23_txt_toc_navigation_jumps_to_chapter()
    // tap a tocRow → assert reader scrolls to that chapter position
    // AID: "tocRow-<id>", "txtReaderContainer"
```

Key AccessibilityIDs used: `readerAnnotationsButton`, `annotationsPanelSheet`, `tocEmptyState`, `tocRow-<id>`.

---

**`vreaderUITests/Verification/Feature27ReplacementRulesVerificationTests.swift`**

```
class Feature27ReplacementRulesVerificationTests: XCTestCase
  func verify_feature_27_replacement_rule_ui_surface()
    // From library: settingsToolbarButton → "settingsReplacementRules" row visible
    // → tap → ReplacementRulesView navigation push renders (assert title/add button)
    // AID: "settingsToolbarButton", "settingsReplacementRules"
    // NOTE: Replacement rules live in global Settings (not reader settings panel).
    //       Path: LibraryView toolbar → SettingsView sheet → Replacement Rules row.

  func verify_feature_27_replacement_rule_applies_in_reader()
    // (a) From global Settings: add replacement rule pattern="Chapter" → replacement=""
    // (b) settingsDoneButton → library → open war-and-peace TXT
    // (c) assert "txtReaderContent" value does NOT contain visible "Chapter" tokens
    //     (spot-check via snapshot or textView value predicate)
    // AID: "settingsToolbarButton", "settingsReplacementRules", "settingsDoneButton",
    //       "txtReaderContent"
    // CAUTION: ReplacementRulesView has no explicit AID for "Add rule" button.
    //           Locate by label-match ("Add Rule" or "+" system button).
    //           Flag as AID-gap: "replacementRulesAddButton" needed in ReplacementRulesView.
```

Key AccessibilityIDs used: `settingsToolbarButton`, `settingsReplacementRules`, `settingsDoneButton`, `settingsView`, `txtReaderContent`. **Replacement rules are in global Settings (SettingsView), not in the reader settings panel. The `readerSettingsButton` / `readerSettingsPanel` path does NOT reach them.** AID gap: `replacementRulesAddButton` needed in `ReplacementRulesView.swift`.

---

**`vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift`**

```
class Feature28ChineseConversionVerificationTests: XCTestCase
  func verify_feature_28_simp_to_trad_conversion_active()
    // seed war-and-peace (CJK content needed — or use a CJK fixture if available)
    // open → readerSettingsButton → scroll to "Chinese Text" segmented picker
    // → tap "Simp → Trad" segment → assert picker selection updated
    // AID: "readerSettingsPanel", Picker with accessibilityLabel "Chinese text conversion"
    //      (segmented style — locate via app.segmentedControls["Chinese text conversion"])
    // IMPORTANT: The picker label is "Chinese Text" (section header), accessibilityLabel
    //            is "Chinese text conversion". It is DISABLED unless format + mode supports it.
    //            Test must open a TXT book in Unified mode to enable the picker.
    //            NOTE: Needs CJK fixture for meaningful content assertion. Flag as
    //                  FIXTURE-GAP: a zh-simp TXT fixture is needed.

  func verify_feature_28_conversion_applies_to_reader_content()
    // Dependent on CJK fixture. Skips if fixture absent.
    // AID: "txtReaderContent" (value must contain trad chars, not simp chars)
```

Key AccessibilityIDs used: `readerSettingsPanel`. **Fixture gap: CJK TXT fixture needed**.

---

**`vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift`**

```
class Feature29WebDAVVerificationTests: XCTestCase
  func verify_feature_29_webdav_backup_ui_available()
    // settingsToolbarButton → WebDAV section → assert "webdavBackupNowButton" exists
    // (smoke: UI surface is reachable, credentials form renders)
    // AID: "settingsToolbarButton", "webdavServerURL", "webdavBackupNowButton"

  func verify_feature_29_webdav_backup_executes_when_configured()
    // CONDITIONAL: skipped with XCTSkip if CI_WEBDAV_URL env var is unset
    // Configure from env vars → trigger backup → assert no "webdavBackupErrorText"
    // AID: "webdavTestButton", "webdavSaveButton", "webdavBackupNowButton",
    //       "webdavBackupErrorText" (must be absent)
```

Key AccessibilityIDs used: `settingsToolbarButton`, `webdavServerURL`, `webdavTestButton`, `webdavSaveButton`, `webdavBackupNowButton`, `webdavBackupErrorText`. **WebDAV test is CI-conditional** (`XCTSkip` when server URL absent).

---

**`vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`**

```
class Feature31AutoPageTurnVerificationTests: XCTestCase
  func verify_feature_31_auto_page_turn_advances_page()
    // seed books → open TXT book → set paged mode → enable autoPageTurn
    // (short interval, e.g. 1s via settings) → wait 2.5s → assert page advanced
    // AID: "readerSettingsPanel", Toggle "Auto Page Turn", "nativeTextPagedView",
    //       "readingProgressLabel"
    // NOTE: Auto-page-turn toggle has no dedicated AID. Flag as AID-gap.
    // ANTI-FLAKE: Use XCTNSPredicateExpectation on readingProgressLabel value change,
    //             not Thread.sleep.
```

Key AccessibilityIDs used: `nativeTextPagedView`, `readingProgressLabel`. **AID gap: `autoPageTurnToggle` + `autoPageTurnIntervalSlider` needed in `ReaderSettingsPanel.swift`**. Fallback without AIDs: `app.switches["Auto page turn"]` + `app.sliders["Auto page turn interval"]`.

---

**`vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`**

```
class Feature35AnnotationsExportVerificationTests: XCTestCase
  func verify_feature_35_export_button_triggers_share_sheet()
    // seed books → open a book → create highlight (gesture or via debug URL)
    // → readerAnnotationsButton → annotationsPanelSheet → annotationsExportButton
    // → assert share sheet / document picker appears (UIActivityViewController)
    // AID: "annotationsExportButton", "annotationsPanelSheet"
    // NOTE: Can't assert exported file contents via XCUI; assert sheet _presence_ only.

  func verify_feature_35_import_button_is_visible()
    // readerAnnotationsButton → annotationsPanelSheet → assert annotationsImportButton hittable
    // (import flow uses DocumentPicker — can't drive OS picker in XCUI without workaround)
    // AID: "annotationsImportButton"
```

Key AccessibilityIDs used: `annotationsExportButton`, `annotationsImportButton`, `annotationsPanelSheet`.

---

**`vreaderUITests/Verification/Feature36OPDSVerificationTests.swift`**

```
class Feature36OPDSVerificationTests: XCTestCase
  func verify_feature_36_opds_catalog_ui_surface()
    // opdsCatalogsToolbarButton → assert "opdsCatalogList" or "opdsEmptyState" present
    // → opdsAddCatalog button → assert form fields (opdsCatalogNameField, opdsCatalogURLField)
    // AID: "opdsCatalogsToolbarButton", "opdsCatalogList", "opdsEmptyState",
    //       "opdsAddCatalog", "opdsCatalogNameField", "opdsCatalogURLField",
    //       "opdsCatalogSaveButton"

  func verify_feature_36_opds_browse_with_local_fixture()
    // CONDITIONAL: skipped if CI_OPDS_URL env var unset
    // Configure local OPDS feed → browse → assert opdsEntryDetail reachable
    // AID: "opdsCatalog_<id>", "opdsEntryDetail", "opdsDownload_<format>"
```

Key AccessibilityIDs used: `opdsCatalogsToolbarButton`, `opdsEmptyState`, `opdsCatalogList`, `opdsAddCatalog`, `opdsCatalogNameField`, `opdsCatalogURLField`, `opdsCatalogSaveButton`. **OPDS browse is CI-conditional**.

---

**`vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`**

```
class Feature40TTSSentenceHighlightVerificationTests: XCTestCase
  func verify_feature_40_tts_sentence_highlight_fires_callback()
    // seed war-and-peace → open → readerTTSButton → ttsPlayPauseButton
    // → wait for ttsControlBar → use vreader-debug://snapshot to read
    //   DebugSnapshot.ttsState → assert sentenceRange is non-nil
    // AID: "readerTTSButton", "ttsControlBar", "ttsPlayPauseButton"
    // NOTE: Uses DebugBridge snapshot for assertion, not visual inspection.
    //       TTS uses AVSpeechSynthesizer on simulator (no audio, but callbacks fire).

  func verify_feature_40_tts_sentence_highlight_callback_count_advances()
    // After 2s of TTS playback, assert sentenceHighlightCount > 0
    // via snapshot.ttsState (DebugSnapshot schema v2, feature #49 WI-7a)
    // ANTI-FLAKE: XCTNSPredicateExpectation on snapshot sentinel file, not sleep.
```

Key AccessibilityIDs used: `readerTTSButton`, `ttsControlBar`, `ttsPlayPauseButton`. **DebugSnapshot `ttsState` field requires feature #49 WI-7a to be shipped** — verify before implementing this test.

---

**`vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`**

```
class Feature41TTSAutoScrollVerificationTests: XCTestCase
  func verify_feature_41_tts_autoscroll_advances_position()
    // seed war-and-peace → open in scroll mode → TTS start → 2s wait
    // → assert txtReaderContainer value (restoredOffset) changed from initial
    // AID: "txtReaderContainer" (value contains restoredOffset:<N>),
    //       "ttsPlayPauseButton", "ttsControlBar"
    // Uses same value-predicate pattern as TXTHighlightGestureVerificationTests.

  func verify_feature_41_tts_autoscroll_pauses_on_stop()
    // start TTS → record offset → stop → wait 2s → assert offset unchanged
```

Key AccessibilityIDs used: `txtReaderContainer`, `ttsPlayPauseButton`, `ttsStopButton`, `ttsControlBar`.

---

#### `vreaderUITests/Verification/Helpers/` — shared test helpers

These helpers are scoped to the Verification group. They do not modify existing `vreaderUITests/Helpers/` files.

**`vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`**

Helper methods wrapping `xcrun simctl openurl` calls for reset, seed, settle, snapshot. Provides a `settleApp(token:timeout:)` that watches the sentinel file produced by `vreader-debug://settle?token=<X>` instead of sleeping.

Concrete methods:
```
func resetApp()                                         // vreader-debug://reset
func seedFixture(named name: String)                    // vreader-debug://seed?fixture=<name>
func settleApp(token: String, timeout: TimeInterval)    // writes Caches/ready-<token>.json
func snapshotApp(dest: String) -> DebugSnapshotDTO?     // reads snapshot JSON
```

**`vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift`**

Reusable helpers for opening/closing the reader settings panel and scrolling to named sections.

```
func openReaderSettings(in app: XCUIApplication) -> XCUIElement  // returns panel element
func scrollToSection(_ sectionHeader: String, in panel: XCUIElement)
func closeReaderSettings(in app: XCUIApplication)
```

---

#### `vreaderTests/Verification/` — unit tests for harness helpers

**`vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift`**

Swift Testing suite:

```
@Suite("VerificationDebugBridgeHelper")
struct VerificationDebugBridgeHelperSuite {
  @Test func resetURL_hasCorrectScheme()
  @Test func seedURL_encodesFixtureName()
  @Test func settleURL_encodesToken()
  @Test func snapshotURL_encodesDest()
  @Test func fixtureNamesInCatalog_resolveToBundle()
}
```

**`vreaderTests/Verification/VerificationSettingsHelperTests.swift`**

```
@Suite("VerificationSettingsHelper")
struct VerificationSettingsHelperSuite {
  // These are pure URL-construction tests; no app launch.
  @Test func sectionHeaderMatches_known_sections()
}
```

---

### Files Modified

| File | Change |
|------|--------|
| `vreaderUITests/Helpers/TestConstants.swift` | Add new `AccessibilityID` constants for identified gaps (see AID Gaps section) |
| `vreader/Views/Reader/ReaderSettingsPanel.swift` | Add `accessibilityIdentifier` to auto-page-turn toggle (`autoPageTurnToggle`) and auto-page-turn interval slider (`autoPageTurnIntervalSlider`) |
| `vreader/Views/Settings/ReplacementRulesView.swift` | Add `accessibilityIdentifier("replacementRulesAddButton")` to the Add Rule button |
| `docs/manual-test-checklist.md` | Mark 13 items "Auto-verified by `<test-name>`"; add "Real-device only" section for #26 and iCloud flows |

### Files OUT of Scope

- `vreaderTests/Services/DebugBridge/` — existing DebugBridge unit tests are unaffected
- `vreader/Views/` outside `ReaderSettingsPanel.swift` (no new production features — harness only)
- `vreader/Services/` — no service changes
- `vreaderUITests/` existing tests outside `Verification/` — untouched
- `vreaderUITests/Helpers/LaunchHelper.swift` — not modified; Verification uses it as-is
- `project.yml` scheme configuration — CI integration deferred to WI-4 (add `Verification` test plan entry)
- Any WebDAV or OPDS server fixtures — existing bundle fixtures from feature #44 are used; new CJK fixture is a conditional addition for feature #28

---

## 3. AID Gaps (Required Before Gate 3)

The following AccessibilityIDs are missing from production code but required for tests. WI-1 must add them to both `TestConstants.swift` and the production views **before** the tests that depend on them are written.

| AID String | Production File | Used By |
|---|---|---|
| `replacementRulesAddButton` | `ReplacementRulesView.swift` | Feature27 test (add a rule) |
| `autoPageTurnToggle` | `ReaderSettingsPanel.swift` | Feature31 test |
| `autoPageTurnIntervalSlider` | `ReaderSettingsPanel.swift` | Feature31 test |

**Corrected: `replacementRulesSection` was incorrectly planned for `ReaderSettingsPanel.swift`. Replacement rules are accessed via the global Settings sheet (`settingsToolbarButton` → `settingsReplacementRules`), not via the reader settings panel. No changes to `ReaderSettingsPanel.swift` are needed for feature #27.**

**Note on `perBookCustomSettingsToggle`**: The per-book toggle exists (Toggle "Custom settings for this book") but has no `accessibilityIdentifier`. Tests for feature #37 can locate it by label text (`app.switches.matching(NSPredicate(format: "label == 'Custom settings for this book'"))`). This is acceptable because the label is stable — no production AID change required.

**Note on auto-page-turn**: The auto-page-turn Toggle label is "Auto page turn" (accessibilityLabel). The interval Slider label is "Auto page turn interval". Both can be located via label-match (`app.switches["Auto page turn"]`, `app.sliders["Auto page turn interval"]`). Dedicated AIDs are still recommended for stability. The `accessibilityLabel` fallback is documented in the test comment.

---

## 4. Prior Art / Project Precedent / Rejected Alternatives

### Prior art used as the pattern

**`TXTHighlightGestureVerificationTests.swift`** is the canonical template:
- `setUp` uses `launchApp(seed:resetPreferences:)` — never `vreader-debug://reset` for tests that use `LaunchHelper`, since the app restarts fresh each time
- `continueAfterFailure = false`
- `@MainActor` on the test class
- `XCTNSPredicateExpectation` for all async waits — no `Thread.sleep`
- `waitForExistence(timeout:)` / `waitForHittable(timeout:)` / `waitForDisappearance(timeout:)` from `LaunchHelper.swift` extension
- Accessibility-ID-first element location; falls back to label-match only when AID absent

**`DebugBridgeTests.swift`** and `RealDebugBridgeContextTests.swift` show how `vreader-debug://` commands are tested at the unit level. The `VerificationDebugBridgeHelper` in this plan follows the same command URL schema.

**`CollectionSidebarTests.swift`** shows the pattern for testing sidebar-based features: `resetPreferences: true` on launch + label-string tap for tabs/sections.

**`OPDSCatalogListTests.swift`** shows the conditional server-dependent test pattern: tests assert UI surface without a live server; browsing tests are structurally present but stub-safe (they assert the entry-point button is hittable, not that a live catalog loads).

### Rejected alternative: DebugBridge URL-only verification

The `vreader-debug://snapshot` command (feature #49 WI-7a) could be used to drive all verifications without XCUI gestures — just send commands and read back JSON. Rejected because:
1. Snapshot-only testing does not prove the **gesture path** works (e.g., long-press highlight). Feature #11's original bug was in the gesture pipeline, not persistence.
2. XCUITest drives the same code paths a real user exercises; `simctl openurl` bypasses SwiftUI and UIKit gesture recognizers.
3. The project already has XCUI infrastructure that works and is maintainable — adding a parallel test runner would fragment coverage.

DebugBridge is used as a **complement** in this plan (settle + snapshot for async-state assertions), not a replacement.

### Rejected alternative: Snapshot-diffing (visual regression)

Rejected per features.md Scope "Excluded": separate concern, separate feature if/when it arrives. This harness verifies behavior, not pixels.

### Rejected alternative: Docker WebDAV / OPDS for all CI runs

Real-server tests add CI complexity (container management, port allocation, teardown). The plan uses `XCTSkip` when server env vars are absent, preserving the ability to run the full suite when a server is available without blocking CI when it isn't. This mirrors the pattern used in feature #46's Docker integration tests.

---

## 5. Work-Item Sequencing

### WI-1 — Harness scaffolding + AID gaps + proving-ground items (#37, #34, #11)

**Type**: Behavioral
**PR size estimate**: ~350 LOC (2 helper files + 3 feature test files + AID additions)

Deliverables:
1. `vreaderUITests/Verification/Helpers/VerificationDebugBridgeHelper.swift`
2. `vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift`
3. `vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift` (Swift Testing)
4. `vreaderTests/Verification/VerificationSettingsHelperTests.swift` (Swift Testing)
5. `vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests.swift`
6. `vreaderUITests/Verification/Feature34CollectionsVerificationTests.swift`
7. `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`
8. AID additions to `vreader/Views/Reader/ReaderSettingsPanel.swift` (autoPageTurnToggle, autoPageTurnIntervalSlider) and `vreader/Views/Settings/ReplacementRulesView.swift` (replacementRulesAddButton)
9. Add new AID constants to `vreaderUITests/Helpers/TestConstants.swift`

Gate: all tests pass in `xcodebuild test -only-testing:vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests` etc. + `vreaderTests/Verification`.

---

### WI-2 — Features #21, #23, #27, #28

**Type**: Behavioral
**PR size estimate**: ~280 LOC (4 feature test files)

Deliverables:
1. `vreaderUITests/Verification/Feature21PaginatedModeVerificationTests.swift`
2. `vreaderUITests/Verification/Feature23TXTTocVerificationTests.swift`
3. `vreaderUITests/Verification/Feature27ReplacementRulesVerificationTests.swift`
4. `vreaderUITests/Verification/Feature28ChineseConversionVerificationTests.swift`

Prerequisite: WI-1 AID additions merged (`replacementRulesAddButton` AID in `ReplacementRulesView.swift` needed by feature #27 test).

Note on feature #28: if no CJK TXT fixture is available in the bundle, `verify_feature_28_conversion_applies_to_reader_content` is implemented as `XCTSkip("CJK TXT fixture not present in bundle")` with a fixture-request filed in the WI-2 PR description. The UI-surface test (`verify_feature_28_simp_to_trad_conversion_active`) does not require CJK content and runs unconditionally.

Gate: all tests in WI-2 test files pass.

---

### WI-3 — Features #29, #31, #35, #36, #40

**Type**: Behavioral
**PR size estimate**: ~300 LOC (5 feature test files)

Deliverables:
1. `vreaderUITests/Verification/Feature29WebDAVVerificationTests.swift`
2. `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`
3. `vreaderUITests/Verification/Feature35AnnotationsExportVerificationTests.swift`
4. `vreaderUITests/Verification/Feature36OPDSVerificationTests.swift`
5. `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift`

Dependency check before implementation: confirm `DebugSnapshot.ttsState` schema is available (feature #49 WI-7a). If not shipped, feature #40 TTS state assertion falls back to asserting `ttsControlBar` is visible (weaker but valid smoke check).

Gate: all tests pass (server-dependent tests skip cleanly when env vars absent).

---

### WI-4 — Feature #41, CI integration, docs update

**Type**: Behavioral + foundational (CI integration is foundational; #41 test is behavioral)
**PR size estimate**: ~200 LOC

Deliverables:
1. `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift`
2. CI: Add `Verification` test plan to `project.yml` scheme (new `testPlans` entry under `vreaderUITests` target, referencing `Verification/` directory)
3. Update `docs/manual-test-checklist.md`: mark 13 items auto-verified, add "Real-device only" section
4. Update `docs/architecture.md`: add `vreaderUITests/Verification/` to the UITest section
5. Add `dev-docs/verification-red-checks.md`: record RED-proof checks for regression tests

Gate: `xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in under 8 minutes on the CI runner. All 13 features reach `VERIFIED` status in `docs/features.md`.

---

## 6. Test Catalogue

### Unit Tests (run in `vreaderTests/`)

| File | Suite | What It Covers |
|------|-------|----------------|
| `vreaderTests/Verification/VerificationDebugBridgeHelperTests.swift` | `VerificationDebugBridgeHelper` | URL construction for reset/seed/settle/snapshot commands; edge cases: empty token, missing fixture name, special chars in token |
| `vreaderTests/Verification/VerificationSettingsHelperTests.swift` | `VerificationSettingsHelper` | Section-header string matching; no app launch |

### UITests (run in `vreaderUITests/`)

| File | Happy Path Method | Regression Methods |
|------|---|---|
| `Feature37PerBookSettingsVerificationTests.swift` | `verify_feature_37_perbook_settings_toggle_isolated_to_book` | `verify_feature_37_perbook_settings_persists_across_reopen` |
| `Feature34CollectionsVerificationTests.swift` | `verify_feature_34_create_collection_appears_in_sidebar` | `verify_feature_34_add_book_to_collection_filters_library` |
| `Feature11EPUBHighlightVerificationTests.swift` | `verify_feature_11_epub_highlight_happy_path` | `verify_feature_11_epub_highlight_regression_bug77_buffering_race` |
| `Feature21PaginatedModeVerificationTests.swift` | `verify_feature_21_paged_mode_shows_paged_view` | `verify_feature_21_paged_mode_page_navigation` |
| `Feature23TXTTocVerificationTests.swift` | `verify_feature_23_txt_toc_populated_for_chinese_chapters` | `verify_feature_23_txt_toc_navigation_jumps_to_chapter` |
| `Feature27ReplacementRulesVerificationTests.swift` | `verify_feature_27_replacement_rule_removes_text_from_reader` | — |
| `Feature28ChineseConversionVerificationTests.swift` | `verify_feature_28_simp_to_trad_conversion_active` | `verify_feature_28_conversion_applies_to_reader_content` (conditional) |
| `Feature29WebDAVVerificationTests.swift` | `verify_feature_29_webdav_backup_ui_available` | `verify_feature_29_webdav_backup_executes_when_configured` (conditional) |
| `Feature31AutoPageTurnVerificationTests.swift` | `verify_feature_31_auto_page_turn_advances_page` | `verify_feature_31_auto_page_turn_pauses_on_stop` |
| `Feature35AnnotationsExportVerificationTests.swift` | `verify_feature_35_export_button_triggers_share_sheet` | `verify_feature_35_import_button_is_visible` |
| `Feature36OPDSVerificationTests.swift` | `verify_feature_36_opds_catalog_ui_surface` | `verify_feature_36_opds_browse_with_local_fixture` (conditional) |
| `Feature40TTSSentenceHighlightVerificationTests.swift` | `verify_feature_40_tts_sentence_highlight_fires_callback` | `verify_feature_40_tts_sentence_highlight_callback_count_advances` |
| `Feature41TTSAutoScrollVerificationTests.swift` | `verify_feature_41_tts_autoscroll_advances_position` | `verify_feature_41_tts_autoscroll_pauses_on_stop` |

**Total test methods (UITests)**: 26 (13 happy-path + 13 regression/secondary)
**Total test methods (unit)**: ~7

---

## 7. Risks + Mitigations

### Risk 1 — Timing / flakiness in WebView-backed readers (features #11, #40, #41)

**Risk**: EPUB highlight and TTS tests rely on WKWebView rendering completing before gesture/action. Previous bugs (#77 buffering race) were timing-related.

**Mitigation**: Use `vreader-debug://settle?token=<X>` to gate on the app's own ready signal before any gesture. The settle token writes `Caches/ready-<token>.json` only after `DOMContentLoaded` + a configurable layout settle cycle. `VerificationDebugBridgeHelper.settleApp(token:timeout:)` polls for this file. Never use `Thread.sleep`.

### Risk 2 — WebDAV / OPDS server dependency

**Risk**: Tests that require a live server will fail in environments where no server is available.

**Mitigation**: All server-dependent tests call `XCTSkip("CI_WEBDAV_URL not set")` when the env var is absent. CI runs the full suite only when job-level server containers are started. Local development can run the server-independent subset without skips.

### Risk 3 — Fixture pollution between tests

**Risk**: One test's created highlight / collection / per-book setting leaks into the next test.

**Mitigation**: Every test class uses `continueAfterFailure = false` and `setUp` calls `launchApp(seed: .books, resetPreferences: true)` — this relaunches the app with an in-memory SwiftData container (not the on-disk database) and wipes known UserDefaults keys. Per-book settings files in the sandbox are written by the app under the standard documents directory — `resetPreferences: true` does NOT clear these. **AID mitigation**: features #37, #31 must call `launchApp` with a fresh app instance (relaunching clears the sandbox on simulator between runs only if the simulator's data is reset, which `--uitesting` does not do automatically). For per-book settings specifically, the test must explicitly turn off the per-book toggle in `tearDown` or use a fixture fingerprintKey that changes between runs.

**Stronger mitigation**: `setUp` should add a `vreader-debug://reset` call via `xcrun simctl openurl` *in addition to* the in-memory seed, to ensure any PerBookSettingsStore files are cleared. Document this in `VerificationDebugBridgeHelper`.

### Risk 4 — Chapter-mode vs non-chapter-mode distinctions (TXT)

**Risk**: Feature #23 (TOC) tests only exercise the non-chapter TXT path if `war-and-peace.txt` doesn't have chapter markers matching `TXTTocRuleEngine`. The fixture must be verified to contain `Chapter` / `第X章` / similar patterns.

**Mitigation**: WI-2 includes a preflight check — inspect `war-and-peace.txt` fixture to confirm chapter headers exist. If not, the test will use the fixture that feature #44 provides that is known to have chapter markers, or a dedicated TOC-test fixture is added to the bundle.

### Risk 5 — DebugSnapshot `ttsState` availability (features #40, #41)

**Risk**: Feature #49 WI-7a is needed to surface `ttsState` in `DebugSnapshot`. If it's not yet merged when WI-3 implements the feature #40 test, the snapshot-based assertion is unavailable.

**Mitigation**: WI-3 pre-checks that `DebugSnapshot` contains `ttsState`. If absent, the test uses a fallback assertion (`ttsControlBar` visible + `ttsPlayPauseButton` state = "Pause"). The stronger `sentenceHighlightCount` assertion is added in a follow-up commit once feature #49 WI-7a ships. This is explicitly noted in the PR description.

### Risk 6 — OPDS URL encoding and `resetPreferences` interaction

**Risk**: OPDS catalogs are persisted in UserDefaults under `opds.savedCatalogs`, and `--uitesting` does NOT reset UserDefaults (only SwiftData). `resetPreferences: true` wipes known keys — but OPDS catalog storage key must be included in the wipe list.

**Mitigation**: Confirm `--reset-preferences` handler in `VReaderApp.swift` includes the OPDS UserDefaults key. If not, add it in WI-3. Test launches for feature #36 pass `resetPreferences: true`.

### Risk 7 — Feature #28 CJK fixture absence

**Risk**: No CJK TXT fixture currently in the bundle. The `verify_feature_28_conversion_applies_to_reader_content` test would have nothing to convert.

**Mitigation**: The content-conversion test is marked `XCTSkip` when the fixture is absent. A CJK fixture addition request is filed as a follow-up task. The UI-surface test (picker appears and accepts selection) runs unconditionally and is sufficient for `VERIFIED` status on this feature's core claim.

### Risk 8 — Auto-page-turn interval minimum on simulator

**Risk**: Setting a 1-second auto-page-turn interval for tests may not trigger fast enough or may be too aggressive for the test runner.

**Mitigation**: Use 2 seconds as the test interval (configurable via `autoPageTurnIntervalSlider` AID once added, or `app.sliders["Auto page turn interval"]` label-match in the interim). Assert using `XCTNSPredicateExpectation` with a 10-second timeout on `readingProgressLabel` value change, not a fixed sleep. If the assertion flakes in CI, bump the interval to 3 seconds.

---

## 8. Backward Compatibility

This feature adds new test files only. No production code changes (other than three `accessibilityIdentifier` additions in `ReaderSettingsPanel.swift` which are purely additive and do not affect app behavior).

Existing tests in `vreaderUITests/` are unaffected — the new files live in `Verification/` subdirectory and do not share state or modify any helpers shared with existing tests. `LaunchHelper.swift` and `TestConstants.swift` are extended (additive only).

The CI test gate command `xcodebuild test -only-testing:vreaderUITests` continues to work; a new `only-testing:vreaderUITests/Verification` target is added without replacing the existing gate.

---

## 9. Acceptance Criteria Mapping

From `docs/features.md` Feature #45:

| Criterion | Addressed By |
|---|---|
| 13 items reach `VERIFIED`, each citing test name | 13 test files × 2+ methods; WI-4 updates tracker |
| 2 items stay manual, listed in checklist | WI-4 updates `docs/manual-test-checklist.md` |
| `xcodebuild test -only-testing:vreaderUITests/Verification` exits 0 in <8min | WI-4 CI integration + timing validation |
| Each regression test fails on pre-fix commit (RED proof) | WI-4 `dev-docs/verification-red-checks.md` |
| Checklist updated with "Auto-verified by" lines | WI-4 `docs/manual-test-checklist.md` |
| CI prints per-verification summary line | WI-4 (xcodebuild native output provides this) |
| No test uses `sleep` / `Thread.sleep` | Anti-flake invariant enforced in code review |
| Helper LOC <500; per-feature test avg ~80 LOC | Tracked during implementation; split if needed |

---

## 10. Known Limitations (to be addressed in audit)

1. **Feature #11 regression test** — the "rapid long-press before DOMContentLoaded" race (bug #77) is hard to reproduce deterministically in XCUI without a fault injection path. The test uses `vreader-debug://settle` to gate on a *settled* state, which means the happy path is exercised but the pre-settle race is only partially covered. A future improvement would add a DebugBridge command to delay DOMContentLoaded artificially.

2. **Feature #41 auto-scroll assertion** — asserting that `txtReaderContainer.value` changes (i.e., `restoredOffset:N` increases) is an indirect proxy. A direct assertion would require reading scroll offset from the UITextView, which is not exposed via accessibility value on all iOS versions. The proxy is sufficient for regression detection but could produce false-passes if the offset value changes for a reason other than TTS scroll.

3. **Feature #40 TTS assertions depend on simulator behavior** — `AVSpeechSynthesizer` on simulator fires `speakingWillBegin/didFinish` delegate callbacks but with different timing than device. The `sentenceHighlightCount` assertion via DebugSnapshot is more reliable than trying to observe live highlight changes in the WKWebView.

4. **The CJK fixture gap for feature #28** — identified and explicitly handled via `XCTSkip`. Not a blocker for `VERIFIED` status given that the picker UI assertion is sufficient.

---

---

## 11. Manual Audit Evidence (Gate 2 — Codex unavailable, manual fallback)

Codex MCP stream disconnected on first ping attempt (2026-05-13). Manual audit performed per rule 47 fallback procedure.

### Files Read

- `docs/features.md` (feature #45 plan section via `grep -A 120`)
- `docs/architecture.md` (full)
- `vreaderUITests/Helpers/LaunchHelper.swift` (full)
- `vreaderUITests/Reader/TXTHighlightGestureVerificationTests.swift` (full)
- `vreaderUITests/Helpers/TestConstants.swift` (full — all AccessibilityID constants)
- `vreaderUITests/Library/CollectionSidebarTests.swift` (head)
- `vreaderUITests/Library/OPDSCatalogListTests.swift` (head)
- `vreaderUITests/Reader/ReaderSettingsPanelTests.swift` (head)
- `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift` (full)
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` (head)
- `vreader/Services/DebugBridge/DebugCommand.swift` (grep)
- `vreader/Views/Reader/ReaderSettingsPanel.swift` (targeted grep + sed reads)
- `vreader/Views/Reader/ReaderChromeBar.swift` (grep)
- `vreader/Views/Reader/AnnotationsPanelView.swift` (grep)
- `vreader/Views/Reader/TTSControlBar.swift` (grep)
- `vreader/Views/Reader/NativeTextPagedView.swift` (grep)
- `vreader/Views/Annotations/HighlightListView.swift` (grep)
- `vreader/Views/Annotations/AnnotationListView.swift` (grep)
- `vreader/Views/Bookmarks/TOCListView.swift` (grep)
- `vreader/Views/Library/CollectionSidebar.swift` (grep)
- `vreader/Views/LibraryView.swift` (grep)
- `vreader/Views/OPDS/OPDSCatalogListView.swift` (grep)
- `vreader/Views/Settings/WebDAVSettingsView.swift` (grep)
- `vreader/Views/Settings/SettingsView.swift` (grep)
- `vreader/Views/Settings/ReplacementRulesView.swift` (grep)

### Symbols / Signatures Verified

- All `AccessibilityID` constants in `TestConstants.swift` cross-checked against production views
- `DebugCommand` cases: `reset`, `seed`, `open`, `settle`, `snapshot`, `eval`, `theme` — confirmed
- `LaunchHelper.launchApp(seed:resetPreferences:)` — confirmed parameter names
- `ReaderSettingsPanel` sections verified: `readingModeSection` (Picker "Reading Mode"), `autoPageTurnSection` (Toggle "Auto page turn" + Slider "Auto page turn interval"), `chineseConversionSection` (Picker label "Chinese Text", accessibilityLabel "Chinese text conversion"), `perBookSection` (Toggle "Custom settings for this book")
- Replacement rules path confirmed: `settingsToolbarButton` → `settingsReplacementRules` (SettingsView, not ReaderSettingsPanel) — this was a critical plan error in v1, fixed in v2
- `nativeTextPagedView` AID confirmed in `NativeTextPagedView.swift:36`
- TTS AIDs confirmed: `ttsPlayPauseButton`, `ttsStopButton`, `ttsControlBar`, `ttsSpeedSlider`
- Collection AIDs confirmed: `collectionsToolbarButton`, `newCollectionButton`, `newCollectionTextField`, `addCollectionButton`, `filterAllBooks`, `filterDoneButton`
- OPDS AIDs confirmed: `opdsCatalogsToolbarButton`, `opdsEmptyState`, `opdsCatalogList`, `opdsAddCatalog`, `opdsCatalogNameField`, `opdsCatalogURLField`, `opdsCatalogSaveButton`
- Annotation AIDs confirmed: `annotationsExportButton`, `annotationsImportButton`, `annotationsPanelSheet`, `highlightEmptyState`
- WebDAV AIDs confirmed: `webdavServerURL`, `webdavTestButton`, `webdavSaveButton`, `webdavBackupNowButton`, `webdavBackupErrorText`
- TOC AIDs confirmed: `tocEmptyState`, `tocRow-<id>`
- `settingsToolbarButton`, `settingsView`, `settingsDoneButton`, `settingsReplacementRules` confirmed in `SettingsView.swift` and `LibraryView.swift`
- `readerTTSButton` confirmed in `ReaderChromeBar.swift:55` (id: "readerTTSButton")

### Findings Fixed (v1 → v2)

| Severity | Finding | Fix Applied |
|---|---|---|
| **High** | Feature #27 test described path through `readerSettingsPanel` — WRONG. Replacement rules are in global `SettingsView` (`settingsReplacementRules`). | Rewrote Feature27 test description with correct path. Updated Modified Files table. Changed AID gap from `replacementRulesSection` in ReaderSettingsPanel to `replacementRulesAddButton` in ReplacementRulesView. |
| **Medium** | Chinese conversion picker described with label "Chinese Conversion" — actual label is "Chinese Text", accessibilityLabel is "Chinese text conversion". | Corrected picker label + access pattern in Feature28 section. Added note that picker is disabled unless format + mode supports it; test must use Unified mode. |
| **Low** | AID gap table listed `autoPageTurnIntervalStepper` — UI is a Slider, not a Stepper. | Corrected to `autoPageTurnIntervalSlider`. |
| **Low** | AID gap table listed `replacementRulesSection` in wrong file. | Corrected per High finding above. |

### Edge Cases Checked

- Fixture availability: `war-and-peace.txt`, `mini-epub3.epub`, `mini-azw3.azw3` confirmed in `DebugFixtureCatalog.all()`; no CJK TXT fixture — documented as fixture gap for feature #28
- `resetPreferences: true` effect on OPDS UserDefaults key — flagged as risk #6 with mitigation
- Auto-page-turn on simulator timing — flagged as risk #8 with 2-second interval recommendation
- Feature #40 `ttsState` snapshot dependency on feature #49 WI-7a — flagged as risk #5 with fallback
- ChineseConversionDisableReason gate: picker disabled for native mode / non-unified formats — documented in Feature28 test notes

### Risks Accepted (with rationale)

- Feature #11 regression test cannot perfectly replicate the bug #77 pre-settle race (deterministic fault injection not available) — accepted because the settle-gated happy path still exercises the fixed code path.
- Feature #41 uses `restoredOffset` proxy for TTS scroll assertion — accepted as sufficient for regression detection.
- CJK fixture absence for feature #28 content test — accepted with `XCTSkip` + fixture-request follow-up.

*End of Gate 1 Plan — v2 (manual audit complete)*
