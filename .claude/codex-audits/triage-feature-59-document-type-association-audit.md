---
branch: triage/feature-59-document-type-association
feature: 59
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Feature #59 row to `docs/features.md`.
No Swift source changes. No `Info.plist` / `project.yml` Info-properties changes (those land with the implementation, not the triage).

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:

**Confirmed absent capabilities** (the gap this feature must close):
- `vreader/SupportingFiles/Info.plist`: contains `CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `NSAppTransportSecurity`, `UISupportedInterfaceOrientations`, and the App-icon / launch-screen plumbing — but NO `CFBundleDocumentTypes`, NO `UTImportedTypeDeclarations`, NO `UTExportedTypeDeclarations`, NO `LSSupportsOpeningDocumentsInPlace`. The app declares no document-type association.
- `project.yml` `targets.vreader.info.properties` mirrors the same set; no document-type or UTI registration there either.
- `vreader/App/VReaderApp.swift:307`: the only `.onOpenURL` handler is wrapped in `#if DEBUG` and guarded by `guard url.scheme == DebugCommand.scheme else { return }` — it ignores `file://` URLs entirely.

**Confirmed-present capabilities** (this feature does not need to add format handling):
- `vreader/Models/BookFormat.swift:7-32`: enum covers `.epub`, `.pdf`, `.txt`, `.md`, `.azw3` with file-extension mapping (`.azw3` covers `azw3/azw/mobi/prc`; `.md` covers `md/markdown`; `.txt` covers `txt/text`).
- `vreader/Services/BookImporter.swift:57`: registers an `AZW3MetadataExtractor` (and equivalents for the other formats), confirming the import pipeline supports all five formats end-to-end.
- `vreader/ViewModels/{TXT,EPUB,MD}ReaderViewModel.swift`: each exposes an `open(url:)` async method ready to accept a `URL` directly.

**No duplicate / overlap**:
- No feature row in `docs/features.md` mentions document-type association, UTI, "Open in", Share Sheet, or `CFBundleDocumentTypes`.
- Not a duplicate of feature #44 (DebugBridge URL scheme) — that registers `vreader-debug://` as a custom scheme via `DebugBridge.plist` merged at Debug build only; it does not register file-format document types and is Release-stripped.
- Not a duplicate of feature #46/#47 (WebDAV backup / selective restore) — those move books between WebDAV and the local library, never deal with iOS-level UTI registration.

Severity: Medium. Files arrive at vreader today only via Library → Add → file picker; this feature unlocks the "tap a file anywhere on iOS → opens in vreader" affordance that users expect from a reader.

## Verdict

ship-as-is — documentation only, no code risk. Status moves to `PLANNED` via `/feature-workflow` Gate 1 (Plan) + Gate 2 (Independent Plan Audit), which will be where the UTI declarations are concretely drafted and audited against Apple's `UTType` / iOS document-type reference.
