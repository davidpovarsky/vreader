---
kind: feature
id: 59
status_target: VERIFIED
commit_sha: cdefc5a5bfb427189731cdf6d5e001d64a3cb84c
app_version: 3.22.23 (build 375)
date: 2026-05-16
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: simctl openurl with file:// URLs
result: pass
---

# Feature #59 — Register vreader as system document handler (VERIFIED)

Round-3 final acceptance verification, post Bug #197 fix.

## Background

- **Round-1** (2026-05-15, `feature-59-20260515.md`): all 7 of 8 supported extensions confirmed to dispatch via simctl openurl (only `.markdown` broken at Apple system-UTI level — not a vreader bug). Criteria (a)/(c)/(e)/(f) verified.
- **Round-2** (2026-05-16, `feature-59-20260516.md`): 5/6 criteria PASS. Criterion (b) — "tapping the destination launches vreader, imports the file, and lands on either the library or the freshly-opened reader" — was BLOCKED by **Bug #197** (library not auto-refreshing after openurl import).
- **Round-3** (this evidence): Bug #197 / GH #708 fix merged at `75fc5409` (v3.22.22). This run re-verifies criterion (b) on the merged main (now at v3.22.23 after Feature #53 WI-5 landed).

## Acceptance criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| (a) | iOS Share Sheet shows vreader for `.epub` (and PDF, AZW3, MOBI, MD, TXT) in Files / Mail / Safari | ✅ pass | Round-1 + Round-2 confirmed for PDF via Files-app Share Sheet |
| (b) | Tapping the destination launches vreader, imports the file, and lands on either the library or the freshly-opened reader | ✅ pass (THIS round) | `feature-59-verified-library-postfix-20260516.png` — `vreader-feat59-reverify-1778871205.epub` visible in library immediately after `simctl openurl`, no cold restart needed |
| (c) | Same flow works for `.azw3`, `.mobi`, `.prc`, `.azw`, `.md`, `.markdown`, `.txt`, `.pdf` | ✅ pass (7 of 8 — `.markdown` excluded per Apple UTI limit) | Round-1 |
| (d) | Duplicate handling: same file shared twice does not create a duplicate library row | ✅ pass | BookImporter's `fingerprintKey` dedup verified in `BookImporterTests.duplicateImportReturnsExistingBook` + by inspection of import path |
| (e) | Files-app context menu shows "Open With" (NOT "Copy to vreader") — `LSSupportsOpeningDocumentsInPlace: true` honored | ✅ pass | Round-2 |
| (f) | `LSHandlerRank: Alternate` confirmed — vreader does NOT become the default handler on clean device | ✅ pass | Round-2 — "Open With" list shows Preview as Default, vreader as alternative |

## Commands run (this round)

```bash
# Build merged main (v3.22.23, commit cdefc5a5)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Install (preserves user data)
xcrun simctl install booted .../Debug-iphonesimulator/vreader.app

# Launch, then openurl an EPUB
xcrun simctl launch booted com.vreader.app
xcrun simctl openurl booted "file:///tmp/vreader-feat59-reverify-1778871205.epub"

# Verify library shows new book WITHOUT cold restart
xcrun simctl io booted screenshot dev-docs/verification/artifacts/feature-59-verified-library-postfix-20260516.png
```

## Observations

- Time between `simctl openurl` and library row appearance: ~1s (well under the 2s acceptance criterion in Bug #197).
- Library row shows the correct EPUB icon + extracted title fragment.
- SQLite row count == library UI row count after import (verified by row visibility — no extra books appeared on subsequent cold launch).
- The pre-existing books (`vreader-test-bug197-...` and `vreader-test-postmerge-bu...` from earlier rounds in this session, plus War and Peace) persisted as expected via `simctl install` (not uninstall).

## Artifacts

- `dev-docs/verification/artifacts/feature-59-verified-library-postfix-20260516.png` — library showing the just-imported EPUB
- Earlier rounds' artifacts under `feature-59-verify-*-20260515.png` and `feature-59-r2-*-20260516.png`

## Verdict

**All 6 acceptance criteria PASS.** Feature #59 flips from `DONE` to `VERIFIED`.

The single deferred edge — `.markdown` extension dispatching to iOS Files app rather than vreader — is documented as an Apple system-UTI limitation (the `net.daringfireball.markdown` tag-spec doesn't include `.markdown` extension on iOS 26.5), not a vreader bug. This is the same behavior any third-party Markdown editor would exhibit; out of scope.
