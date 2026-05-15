// Purpose: Tests for PDFViewBridge's theme-background application — bug #198 / GH #710.
// Confirms PDFView.backgroundColor is set from ReaderTheme.backgroundColor so the
// page-area gutter flips to dark when the user picks Dark theme (was silently no-op
// before the fix). Tests the static helper, not the full UIViewRepresentable
// construction, so they remain fast and don't need a UIScene environment.

#if canImport(UIKit)
import Testing
import PDFKit
import UIKit
@testable import vreader

@Suite("PDFViewBridge — theme background (bug #198)")
struct PDFViewBridgeThemeTests {

    @Test
    func applyThemeBackground_dark_setsDarkBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white  // simulates default
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .dark)
        #expect(pdfView.backgroundColor == ReaderTheme.dark.backgroundColor,
                "Dark theme must set PDFView.backgroundColor to the dark palette")
    }

    @Test
    func applyThemeBackground_sepia_setsSepiaBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .sepia)
        #expect(pdfView.backgroundColor == ReaderTheme.sepia.backgroundColor)
    }

    @Test
    func applyThemeBackground_light_setsLightBackgroundColor() {
        let pdfView = PDFView()
        pdfView.backgroundColor = .red  // any non-light color
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .light)
        #expect(pdfView.backgroundColor == ReaderTheme.light.backgroundColor)
    }

    @Test
    func applyThemeBackground_dark_thenLight_flipsBack() {
        // Regression guard: re-applying Light after Dark must actually flip
        // BACK (no sticky state). Mirrors the user's bug-report flow:
        // Light → Sepia → Dark should also work in reverse Dark → Light.
        let pdfView = PDFView()
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .dark)
        #expect(pdfView.backgroundColor == ReaderTheme.dark.backgroundColor)
        PDFViewBridge.applyThemeBackground(to: pdfView, theme: .light)
        #expect(pdfView.backgroundColor == ReaderTheme.light.backgroundColor)
    }

    @Test
    func darkThemeBackground_isNotEqualToLight() {
        // Sanity guard: the bug was Dark looking identical to Light because
        // nothing themed the PDFView. After the fix, the three theme colors
        // must each be distinct so the user's eye can tell them apart.
        #expect(ReaderTheme.dark.backgroundColor != ReaderTheme.light.backgroundColor)
        #expect(ReaderTheme.dark.backgroundColor != ReaderTheme.sepia.backgroundColor)
        #expect(ReaderTheme.light.backgroundColor != ReaderTheme.sepia.backgroundColor)
    }

    @Test
    @MainActor
    func applyThemeIfChanged_drivesProductionGuard() {
        // Drives the SAME helper that PDFViewBridge.makeUIView /
        // updateUIView call (PDFViewBridge.applyThemeIfChanged), so a future
        // regression that weakens the `lastAppliedTheme != theme` guard or
        // breaks the nil-coalescing fails here without needing a SwiftUI
        // host. The pure helper tests above only cover the unconditional
        // assignment; this test covers the gated dispatch and the
        // last-applied threading the bridge actually performs.
        let pdfView = PDFView()
        var lastApplied: ReaderTheme?

        // Initial mount with Light: applied + last-applied advances to Light.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .light, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderTheme.light.backgroundColor)
        #expect(lastApplied == .light)

        // Redundant update with same theme: short-circuit, no reapply.
        // Sentinel: pre-set a distinct color and confirm it survives.
        pdfView.backgroundColor = .red
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .light, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == .red,
                "Same-theme update must short-circuit and not reapply")
        #expect(lastApplied == .light)

        // User switches to Dark mid-session: reapplies.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .dark, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderTheme.dark.backgroundColor)
        #expect(lastApplied == .dark)

        // Switch to Sepia: reapplies.
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .sepia, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderTheme.sepia.backgroundColor)
        #expect(lastApplied == .sepia)

        // Switch back to Light: reapplies (no sticky state across the cycle).
        lastApplied = PDFViewBridge.applyThemeIfChanged(
            pdfView: pdfView, theme: .light, lastAppliedTheme: lastApplied
        )
        #expect(pdfView.backgroundColor == ReaderTheme.light.backgroundColor)
        #expect(lastApplied == .light)

        // Nil theme on a fresh PDFView (preview / ad-hoc harness): no-op,
        // last-applied stays nil so the bridge keeps PDFKit's default gutter.
        let freshView = PDFView()
        let originalBackground = freshView.backgroundColor
        let result = PDFViewBridge.applyThemeIfChanged(
            pdfView: freshView, theme: nil, lastAppliedTheme: nil
        )
        #expect(freshView.backgroundColor == originalBackground)
        #expect(result == nil)
    }
}
#endif
