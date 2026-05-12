---
branch: verify/feature-12-md-toc-round2
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-13
---

## Manual Audit Evidence

Changed files in this PR:
- `vreader/App/TestSeeder.swift` (added `seedMDWithTOC`)
- `vreader/App/VReaderApp.swift` (added `seedMDTOC` to `TestLaunchConfig` + dispatch)
- `vreaderUITests/Helpers/LaunchHelper.swift` (added `.mdTOC` case)
- `vreaderUITests/Reader/MDTOCVerificationTests.swift` (new UITest)
- `dev-docs/verification/feature-12-20260513.md` (evidence file)
- `docs/features.md` (row #12 → VERIFIED)

**Files read**: All 4 Swift files above read in full.

**Symbols / signatures verified**:
- `TestSeeder.seedMDWithTOC` — uses `PersistenceActor`, `DocumentFingerprint`, `BookRecord`, `ImportProvenance`, `AppLogger`: all confirmed against existing `seedWarAndPeace` at same location; same pattern.
- `TestLaunchConfig.seedMDTOC: Bool` — mirrors `.seedWarAndPeace: Bool`; added to both `parse(_:)` and `.none` static.
- `needsDiskBackedStore` addition — `|| config.seedMDTOC` matches the existing `|| config.seedWarAndPeace` pattern.
- `TestSeedState.mdTOC` — new case; `launchArgument` returns `"--seed-md-toc"`.
- `MDTOCVerificationTests` — uses `launchApp(seed:resetPreferences:)`, `tapBook(titled:in:)`, `AccessibilityID.*` constants: all confirmed in `LaunchHelper.swift` / `TestConstants.swift`.
- `AccessibilityID.tocEmptyState` — confirmed present in `TestConstants.swift:73`.
- `AccessibilityID.annotationsPanelSheet` — confirmed in `TestConstants.swift:21`.
- `AccessibilityID.readerAnnotationsButton` — confirmed in `TestConstants.swift:16`.
- `AccessibilityID.readerBackButton` — confirmed in `TestConstants.swift:14`.

**Edge cases checked**:
- Swift 6 concurrency: `seedMDWithTOC` is `static func ... async` dispatched from `Task.detached` in `VReaderApp.init` — valid, same as `seedWarAndPeace`.
- `needsDiskBackedStore` includes `seedMDTOC` so the file written to `ImportedBooks/` survives the process (in-memory store would not — the reader opens the file from `applicationSupportDirectory`).
- Hash `"...c0c001"` is a valid 64-char hex SHA-256; distinct from all other seeds in the codebase.
- `generateMDWithHeadings()` — 5 headings: `# Introduction`, `## Chapter 1`, `## Chapter 2`, `### Section 2.1`, `## Chapter 3`. All ATX headings with space after hashes — will be parsed by `TOCBuilder.parseATXHeading(_:)`. No fenced code blocks that could suppress extraction.
- UITest `app.tap()` fallback — taps center of app window to toggle chrome; used if annotations button is not immediately visible. Verified this pattern is safe (no buttons in center of screen in MD reader initial state).

**Risks accepted**: None. All changes are test-only; zero production code paths modified.

## Findings

No Critical, High, Medium, or Low findings. All changes are test infrastructure and verification evidence
with no production code changes.

## Summary Verdict

Ship as-is. UITest passed 14.394s on iPhone 17 Pro Simulator (iOS 26.5, build 278).
Feature #12 row flipped to VERIFIED.
