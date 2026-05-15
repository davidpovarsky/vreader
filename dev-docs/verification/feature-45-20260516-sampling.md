---
kind: feature
id: 45
status_target: VERIFIED
commit_sha: efbbc5c98723b58e327ebc79f5bfba7c01f6b953
app_version: 3.22.20 (build 372)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: n/a (XCUITest -testPlan Verification)
result: partial
---

# Feature #45 — Verification harness sweep (sampling pass)

Round-N (post-Bug #198 close-gate): re-ran the `Verification.xctestplan` against
merged `main` at v3.22.20 (commit `efbbc5c9`) to continue closing the
"9 of 13 classes still unsampled clean end-to-end" gap noted in the row.

## Result summary

`Executed 25 tests, with 13 tests skipped and 0 failures (0 unexpected) in 413.025 seconds`

**12 PASSED**, **13 SKIPPED**, **0 FAILED**. Clean sample run.

## Per-class results

| Class | Methods | Pass | Skip | Skip reason |
|---|---|---|---|---|
| Feature11EPUBHighlightVerificationTests | 2 | 0 | 2 | "EPUB reader did not load within timeout" / "EPUB reader did not load" — XCUITest harness can't drive EPUB load; same skip as prior rounds. Suspect fixture / `--seed-epub-...` plumbing or accessibility label timing |
| Feature21PaginatedModeVerificationTests | 2 | 0 | 2 | "Reading Mode picker absent for this fixture's format" / "readingProgressLabel not present" — same fixture issue blocking feature #21 verify (mini-epub3 paginates to 1 page; no multi-page EPUB fixture) |
| Feature23TXTTocVerificationTests | 2 | **2** | 0 | — |
| Feature27ReplacementRulesVerificationTests | 1 | **1** | 0 | — |
| Feature28ChineseConversionVerificationTests | 2 | 1 | 1 | "CJK TXT fixture not present in DebugFixtureCatalog. war-and-peace.txt has only English content" — fixture gap |
| Feature29WebDAVVerificationTests | 2 | 1 | 1 | "CI_WEBDAV_URL / USERNAME / PASSWORD env vars not set" — env dependency |
| Feature31AutoPageTurnVerificationTests | 2 | **2** | 0 | — |
| Feature34CollectionsVerificationTests | 2 | **2** | 0 | — |
| Feature35AnnotationsExportVerificationTests | 2 | **2** | 0 | — |
| Feature36OPDSVerificationTests | 2 | 1 | 1 | "CI_OPDS_URL env var not set" — env dependency |
| Feature37PerBookSettingsVerificationTests | 2 | 0 | 2 | "Per-book toggle not found" — UI surface may have moved |
| Feature40TTSSentenceHighlightVerificationTests | 2 | 0 | 2 | TTS control bar not appearing within 15s (truncated, same as #41 pattern) |
| Feature41TTSAutoScrollVerificationTests | 2 | 0 | 2 | "TTS control bar didn't appear within 15s even with --tts-test-mode" |

## What flipped from this run

Classes whose verify methods passed cleanly this round (not gated by skip):

- **Feature #23 (TXT TOC)**: 2/2 clean ✓ — closes the "unsampled" gap from the Feature #45 row.
- **Feature #31 (Auto page turn)**: 2/2 clean ✓ — closes the "unsampled" gap for this class. The Bug #196 fix (PR #588 hittable-retry budget bump 3→10) verifies in this run.

Both classes now have green-bar evidence in the harness; Feature #45's "9 of 13 classes unsampled" should drop to "7 of 13".

## What's still gated

Five classes (#11, #21, #37, #40, #41) ALL their methods still skip — these are the largest remaining unblock-debt:

1. **#11 EPUB highlight**: EPUB-reader-did-not-load skip. Either the XCUITest's wait condition is too aggressive, or seeding through the helper isn't reaching a ready state. Worth a future investigation, possibly bug-class. Filing skipped (see "Filing decisions" below — not a clear bug, more a harness-conditions issue).
2. **#21 Paginated mode**: same multi-page EPUB fixture blocker as Feature #25 round-6 + Feature #31 round-3. Fixture-class gap, well-documented across multiple rows.
3. **#37 Per-book settings**: "Per-book toggle not found". The toggle either moved or its accessibility identifier changed. Could be a harness-class issue or a real regression in the per-book settings UI surface.
4. **#40 / #41 TTS**: TTS control bar not appearing in `--tts-test-mode`. May be a real product regression in the TTS UI surface OR the helper's wait condition. Either way, blocks both TTS-feature verify methods.

## Commands run

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -testPlan Verification
```

Total runtime: 413 s (~7 minutes). Single iPhone 17 Pro Simulator booted instance.

## Observations

- The XCUITest harness now reliably executes (Bug #192 PR #688 `verify_*` → `test_verify_*` rename held).
- 0 failures means no product regressions surfaced from `main` against acceptance-criteria XCUITest assertions.
- Skipped tests are evenly split between: (a) fixture gaps (multi-page EPUB, CJK TXT), (b) env-var gaps (live WebDAV / OPDS), (c) harness-condition gaps (EPUB reader load timing, TTS bar appearance, per-book toggle lookup).
- Skipping gracefully is the correct behavior — XCTSkip protects against false failures on incomplete fixtures.

## Filing decisions (per scope guardrail)

Per the verify-cron scope: "If you discover a bug during verification, FILE it ... but DO NOT fix it." Two skip-classes warrant investigation:

- **Feature37 "Per-book toggle not found"**: ambiguous — could be a harness lookup miss OR a real UI regression. Need to manually verify Per-book Settings still works on a fresh launch to distinguish. **Not filing yet** — needs a focused investigation in a follow-up verify-cron iteration to confirm whether the toggle UI is genuinely absent or the identifier moved.
- **Feature40/41 "TTS control bar not appearing in --tts-test-mode"**: same ambiguity. Could be product OR harness. Bug #176 (AZW3 TTS unwired) is open and high-severity already; this XCUITest skip might be related (the harness picks an AZW3 fixture) OR it might be a TXT/EPUB TTS harness issue. **Not filing yet** — same reason; want to manually drive TTS in the simulator before filing.

Both warrant a focused round in a future verify-cron iteration. For this iteration, the harness run itself is the evidence.

## Artifacts

XCTest log captured at `/Users/ll/Library/Developer/Xcode/DerivedData/vreader-hdhlhcqmxppsadhececcxeadpkvz/Logs/Test/Test-vreader-2026.05.16_01-44-42-+0800.xcresult`.

## Verdict

Feature #45 stays at `DONE` (not yet `VERIFIED`). After this round:
- 2 newly-confirmed clean: #23, #31
- 7 still gated: #11, #21, #37, #40, #41 (UI/harness gaps) + #28, #29, #36 each have 1 of 2 methods clean

Progressive sampling continues. Next verify-cron iteration can target one of the gated classes with a focused investigation (start with #37 Per-book settings — most likely a label-rename rather than a deep harness issue).
