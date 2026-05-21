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
    /// relocate payload, plus the reading-progress `fraction` as the
    /// locator's `progression`.
    ///
    /// Bug #262 Codex round-1 fix: `AIContextExtractor` treats `.azw3` like
    /// EPUB and reads `locator.progression` (`extractByProgression`). Without
    /// the fraction, progression is nil → the extractor falls back to 0.0 and
    /// pins AI context to the start of the book. The relocate `fraction`
    /// (0...1) is exactly the EPUB-style total progression Foliate reports, so
    /// it threads straight into `progression`. Non-finite / out-of-range
    /// fractions are dropped (a nil progression is safer than a NaN one —
    /// `Locator.validate()` rejects non-finite progression).
    ///
    /// Returns `nil` when `fingerprintKey` cannot be parsed into a
    /// `DocumentFingerprint`, or when the resulting locator fails validation.
    static func positionLocator(
        fingerprintKey: String,
        href: String?,
        cfi: String?,
        fraction: Double? = nil
    ) -> Locator? {
        guard let fingerprint = DocumentFingerprint(canonicalKey: fingerprintKey) else {
            return nil
        }
        let cleanHref = href?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCFI = cfi?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only carry a finite, in-range fraction; clamp to 0...1.
        let progression: Double?
        if let f = fraction, f.isFinite {
            progression = max(0, min(1, f))
        } else {
            progression = nil
        }
        return Locator.validated(
            bookFingerprint: fingerprint,
            href: (cleanHref?.isEmpty == false) ? cleanHref : nil,
            progression: progression,
            totalProgression: progression,
            cfi: (cleanCFI?.isEmpty == false) ? cleanCFI : nil
        )
    }
}
