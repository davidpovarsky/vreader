// Purpose: DEBUG-only wiring that presents a reader sheet from the
// `.debugBridgePresentSheet` notification (Bug #253 verification harness;
// Bug #256 detent reveal). The observer in ReaderContainerView calls
// `handleDebugBridgePresentSheet`, which resolves a `DebugPresentSheetEffect`
// and applies it by setting the SAME `@State` / `annotationsRoute` /
// `presentationDetents(selection:)` binding the chrome buttons + a user drag
// set — so the harness drives the real presentation path (no parallel
// sheet-presentation logic) and the presented sheet's rendered content becomes
// CU-free verifiable via `snapshot` + `eval`.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with: ReaderContainerView.swift, DebugPresentSheetEffect.swift,
//   AnnotationsSheetRoute.swift, RealDebugBridgeContext+Present.swift,
//   DebugBridgeNotifications.swift

#if DEBUG

import SwiftUI
import OSLog

/// Dedicated `ViewModifier` for the Bug #253 present-sheet observer. Mirrors
/// the `ReaderDebugBridgeSearchObserver` pattern — extracting the `.onReceive`
/// keeps the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgePresentObserver: ViewModifier {
    let onCommand: (_ sheet: String, _ tab: String?, _ detent: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgePresentSheet)
        ) { notification in
            guard let sheet = notification.userInfo?["sheet"] as? String else { return }
            let tab = notification.userInfo?["tab"] as? String
            let detent = notification.userInfo?["detent"] as? String
            onCommand(sheet, tab, detent)
        }
    }
}

extension ReaderContainerView {

    /// Handle a `.debugBridgePresentSheet` notification by presenting the
    /// requested sheet through the SAME `@State` / route the chrome buttons
    /// set. Resolves a `DebugPresentSheetEffect` from the `(sheet, tab, detent)`
    /// and:
    ///
    /// - `.annotations(route)` → sets `annotationsRoute` (the bottom-chrome
    ///   Contents/Notes buttons set this too).
    /// - `.ai(initialTab, detent)` → sets `aiInitialTab` + `showAIPanel = true`,
    ///   gated on `resolvedAICoordinator.isAIAvailable` (the chrome's AI
    ///   gate). `ensureAIReady()` runs via the `.onChange(of: showAIPanel)`
    ///   already wired on the body (the same path the chrome AI tap takes).
    ///   `detent` (Bug #256) sets `aiPanelDetent` — the `.medium`/`.large`
    ///   bound to the AI sheet's `presentationDetents(_:selection:)`. A nil
    ///   detent resets the binding to `.medium`, so a prior `detent=large`
    ///   never leaks into a later default open (the binding is `@State`, which
    ///   would otherwise persist across opens).
    /// - `.settings` → sets `showSettings = true` (the Display chrome button).
    ///
    /// An unrecognized `sheet` or `detent` string (shouldn't happen — the
    /// parser validates both) is treated as nil. No-op when no reader is
    /// presented — `.onReceive` only delivers to a mounted view, so callers
    /// see the same posture as `tts` / `search` / `highlight`.
    @MainActor
    func handleDebugBridgePresentSheet(sheet: String, tab: String?, detent: String?) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        guard let kind = DebugCommand.SheetKind(rawValue: sheet) else {
            log.error("present observer: unknown sheet=\(sheet, privacy: .public)")
            return
        }
        // The parser validated `detent` against `SheetDetent`; map the rawValue
        // back. An unknown string degrades to nil (default `.medium`) rather
        // than crashing — defensive against a stray hand-posted notification.
        let parsedDetent = detent.flatMap(DebugCommand.SheetDetent.init(rawValue:))
        log.info(
            "present observer: sheet=\(sheet, privacy: .public) tab=\(tab ?? "nil", privacy: .public) detent=\(parsedDetent?.rawValue ?? "nil", privacy: .public)"
        )

        let effect = DebugPresentSheetEffect.resolve(sheet: kind, tab: tab, detent: parsedDetent)
        switch effect {
        case .annotations(let route):
            annotationsRoute = route
        case .ai(let initialTab, let aiDetent):
            // Mirror the chrome's AI gate (`onAI` in
            // `readerToolbarActionObservers`) — a no-op when AI isn't
            // configured rather than presenting an empty sheet.
            guard resolvedAICoordinator.isAIAvailable else {
                log.info("present observer: AI sheet requested but AI unavailable — no-op")
                return
            }
            // Gate-4 round-1 M1: this is a selectionless cold open (no
            // text-selection drives it), so mirror the production
            // selectionless-translate path (`ReaderOpenAITranslateObserver`):
            // ensure the AI VMs exist, then clear stale Translate-tab state
            // when opening on `.translate`. Without the reset, a prior
            // selection's translated text + result would still be visible —
            // which would corrupt the very verification this command exists
            // to enable. Summarize / Chat carry no stale-translate concern,
            // so the reset is scoped to the translate tab to match production.
            ensureAIReady()
            if initialTab == .translate {
                resolvedAICoordinator.translationViewModel?.reset()
            }
            aiInitialTab = initialTab
            // Bug #256: set the active detent BEFORE presenting so the sheet
            // mounts at the requested detent. A nil request resets to `.medium`
            // (the default) so a prior `detent=large` open doesn't carry over.
            aiPanelDetent = aiDetent.presentationDetent
            showAIPanel = true
        case .settings:
            showSettings = true
        }
    }
}

/// Bug #256 — map the parser's pure `SheetDetent` to SwiftUI's
/// `PresentationDetent` at the View boundary (keeps `DebugCommand` /
/// `DebugPresentSheetEffect` free of a SwiftUI import). A nil request maps to
/// `.medium` — the AI sheet's default presentation — so the absence of a
/// `detent` param leaves the sheet exactly as the Release build presents it.
extension Optional where Wrapped == DebugCommand.SheetDetent {
    var presentationDetent: PresentationDetent {
        switch self {
        case .large:           return .large
        case .medium, .none:   return .medium
        }
    }
}

#endif
