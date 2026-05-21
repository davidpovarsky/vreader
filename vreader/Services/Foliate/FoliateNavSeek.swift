// Purpose: Bug #262 / GH #1136 — pure helpers for AZW3/MOBI locator
// navigation on the live Foliate path. The shared TOC / Notes / Highlight
// sheets post `.readerNavigateToLocator` with a `Locator`; this enum
// resolves that locator to a Foliate-js navigation target and builds the
// `readerAPI.goTo(...)` JS, and builds the position `Locator` the live
// container posts back on `.readerPositionDidChange` for current-location
// sync (AI panel + DebugBridge snapshot).
//
// Pure functions only — no WKWebView dependency — so the target resolution,
// JS escaping, and locator construction are unit-testable without WebKit
// (mirrors `FoliateBottomChromeSeek` from Bug #260).
//
// Key decisions:
// - CFI is the preferred goTo target; Foliate-js `goTo(target)` accepts both
//   CFI and href. TOC entries built by `FoliateTOCConverter` carry an
//   EPUB-style href and NO CFI, so href is the fallback.
// - Whitespace-only targets are treated as absent (downstream `readerAPI.goTo`
//   would otherwise no-op or throw on an empty target).
// - JS strings escape the target via `FoliateJSEscaper.escapeForJSString`
//   (rule 50 bridge safety).
//
// @coordinates-with: FoliateSpikeView.swift, FoliateBilingualContainerView.swift,
//   FoliateJSEscaper.swift, LocatorFactory.swift, Locator.swift,
//   FoliateTOCConverter.swift

import Foundation

enum FoliateNavSeek {

    /// Resolve a Foliate-js navigation target from a `Locator`.
    /// Prefers a non-empty CFI (precise anchor); falls back to the
    /// EPUB-style href (TOC-row locators carry an href, not a CFI).
    /// Returns `nil` when neither is usable.
    static func navigationTarget(for locator: Locator) -> String? {
        if let cfi = locator.cfi,
           !cfi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cfi
        }
        if let href = locator.href,
           !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return href
        }
        return nil
    }

    /// Build the JS that drives Foliate-js navigation to `target`
    /// (a CFI or href). The target is escaped for safe embedding in the
    /// single-quoted JS string literal. Returns `nil` for an empty /
    /// whitespace-only target (no navigation to perform).
    static func goToTargetJS(_ target: String) -> String? {
        guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let escaped = FoliateJSEscaper.escapeForJSString(target)
        return "readerAPI.goTo('\(escaped)');"
    }

    /// Build the position `Locator` the live Foliate container posts on
    /// `.readerPositionDidChange` so the AI panel + DebugBridge probe track
    /// the live reading position. Carries the section href + CFI from the
    /// relocate payload. Returns `nil` when `fingerprintKey` cannot be
    /// parsed into a `DocumentFingerprint`.
    static func positionLocator(
        fingerprintKey: String,
        href: String?,
        cfi: String?
    ) -> Locator? {
        guard let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey) else {
            return nil
        }
        let cleanHref = href?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCFI = cfi?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Locator(
            bookFingerprint: fingerprint,
            href: (cleanHref?.isEmpty == false) ? cleanHref : nil,
            progression: nil,
            totalProgression: nil,
            cfi: (cleanCFI?.isEmpty == false) ? cleanCFI : nil,
            page: nil,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: nil,
            textContextBefore: nil,
            textContextAfter: nil
        )
    }
}
