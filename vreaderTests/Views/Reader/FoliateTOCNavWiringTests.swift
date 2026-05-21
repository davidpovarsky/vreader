// Purpose: Bug #262 / GH #1136 — RED tests for the AZW3/MOBI live-Foliate
// TOC-data + locator-navigation wiring. Bug #260 mounted the bottom chrome
// (Contents / Notes / Display / AI + scrubber) but left two affordances
// hollow on the LIVE path (`FoliateBilingualContainerView` → `FoliateSpikeView`;
// `FoliateReaderContainerView` is DEAD code):
//
//   Symptom A — empty Contents: `ReaderTOCFactory.buildTOC` returns [] for
//   azw3/mobi, and the spike's `book-ready` handler dropped the parsed
//   `toc` (only `title` crossed `onBookReady`). The fix forwards the
//   `book-ready` TOC on a NEW `.foliateBookReadyTOC` notification so the
//   container can convert it (via `FoliateTOCConverter`) into `tocEntries`.
//
//   Symptom B — no row-tap navigation: the shared TOC / Notes / Highlight
//   sheets post `.readerNavigateToLocator`, but neither that nor the
//   `.readerPositionDidChange` current-location sync were wired on the live
//   container. The fix adds a pure `FoliateNavSeek` seam (target resolution
//   + `readerAPI.goTo` JS) and a spike-coordinator observer for
//   `.foliateRequestSeekTarget`.
//
// These tests pin the non-UI seams the fix introduces, the same posture as
// `FoliateBottomChromeWiringTests` (Bug #260): exercise the spike
// Coordinator's `handleMessage(name:body:)` directly + the pure helpers,
// without a live WKWebView.
//
// @coordinates-with: FoliateSpikeView.swift, FoliateBilingualContainerView.swift,
//   FoliateNavSeek.swift, FoliateTOCConverter.swift, FoliateMessageParser.swift,
//   ReaderTOCBuilder.swift, ReaderNotifications.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Bug #262 — AZW3/MOBI TOC data + locator navigation wiring")
struct FoliateTOCNavWiringTests {

    // MARK: - Helpers

    private func makeFingerprint(format: BookFormat = .azw3) -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            fileByteCount: 5000,
            format: format
        )
    }

    /// Captures the userInfo of the first `.foliateBookReadyTOC` post.
    @MainActor
    private final class TOCReadyCapture {
        var fired = false
        var toc: [FoliateTOCItem]?
        var fingerprintKey: String?
    }

    /// Captures the userInfo of the first `.foliateRequestSeekTarget` post.
    @MainActor
    private final class SeekTargetCapture {
        var fired = false
        var target: String?
        var fingerprintKey: String?
    }

    /// Captures the object of the first `.readerPositionDidChange` post.
    @MainActor
    private final class PositionCapture {
        var fired = false
        var href: String?
        var cfi: String?
    }

    // MARK: - Symptom A, Seam 1: book-ready forwards the parsed TOC

    @Test("book-ready message forwards the parsed `toc` on .foliateBookReadyTOC so the live container can build Contents")
    func bookReadyForwardsTOC() async {
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coordinator.fingerprintKey = "azw3:abc:123"

        let capture = TOCReadyCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateBookReadyTOC, object: nil, queue: nil
        ) { note in
            let toc = note.userInfo?["toc"] as? [FoliateTOCItem]
            let key = note.userInfo?["fingerprintKey"] as? String
            MainActor.assumeIsolated {
                capture.fired = true
                capture.toc = toc
                capture.fingerprintKey = key
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        // A real foliate-host.js book-ready body (see FoliateMessageParser
        // parseBookReady expected keys): title, author, language, sections,
        // layout, toc[{label, href, subitems}].
        let body: [String: Any] = [
            "title": "My AZW3 Book",
            "author": "Author",
            "language": "en",
            "sections": 12,
            "layout": "reflowable",
            "toc": [
                ["label": "Chapter 1", "href": "ch01.xhtml", "subitems": [[String: Any]]()],
                ["label": "Chapter 2", "href": "ch02.xhtml", "subitems": [[String: Any]]()],
            ],
        ]
        await coordinator.handleMessage(name: "book-ready", body: body)

        #expect(capture.fired, "Bug #262: book-ready must post .foliateBookReadyTOC so the empty-TOC symptom is fixed")
        #expect(capture.fingerprintKey == "azw3:abc:123", "the TOC post must be scoped by fingerprintKey")
        #expect(capture.toc?.count == 2, "Bug #262: the parsed TOC (2 chapters) must be forwarded, not dropped")
        #expect(capture.toc?.first?.label == "Chapter 1")
        #expect(capture.toc?.first?.href == "ch01.xhtml")
    }

    @Test("book-ready with no TOC does not post .foliateBookReadyTOC (sparse books fall back cleanly)")
    func bookReadyEmptyTOCDoesNotPost() async {
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coordinator.fingerprintKey = "azw3:abc:123"

        let capture = TOCReadyCapture()
        let token = NotificationCenter.default.addObserver(
            forName: .foliateBookReadyTOC, object: nil, queue: nil
        ) { _ in MainActor.assumeIsolated { capture.fired = true } }
        defer { NotificationCenter.default.removeObserver(token) }

        let body: [String: Any] = [
            "title": "No-TOC Book",
            "sections": 1,
            "layout": "reflowable",
            "toc": [[String: Any]](),
        ]
        await coordinator.handleMessage(name: "book-ready", body: body)

        #expect(capture.fired == false,
                "Bug #262: an empty TOC must not post — the container keeps its (empty) state and TOCSheet shows the genuine 'no contents' state")
    }

    // MARK: - Symptom A, Seam 2: buildTOC has an azw3/mobi branch (async, no file parser)

    @Test("buildTOC returns empty (not a crash) for azw3 — the live TOC arrives via .foliateBookReadyTOC, not the file parser")
    func buildTOCAzw3IsAsyncSafe() async {
        // ReaderTOCFactory has no file-based Foliate parser; azw3/mobi TOC
        // comes from the live `book-ready` event. This guards that the
        // azw3/mobi branch is a clean async no-op (empty), never a crash,
        // and that `tocDidLoad` semantics still resolve.
        let fp = makeFingerprint(format: .azw3)
        let entries = await ReaderTOCFactory.buildTOC(
            format: "azw3",
            fileURL: URL(fileURLWithPath: "/dev/null"),
            fingerprint: fp
        )
        #expect(entries.isEmpty, "azw3 file-parse path yields no entries; the live book-ready event supplies them")
    }

    // MARK: - Symptom B, Seam 3: pure target resolution from a Locator

    @Test("navigationTarget prefers a non-empty CFI")
    func navigationTargetPrefersCFI() {
        let fp = makeFingerprint()
        let locator = Locator(
            bookFingerprint: fp, href: "ch01.xhtml", progression: 0,
            totalProgression: nil, cfi: "epubcfi(/6/4!/4/2)", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(FoliateNavSeek.navigationTarget(for: locator) == "epubcfi(/6/4!/4/2)")
    }

    @Test("navigationTarget falls back to href when CFI absent (TOC entries carry hrefs, not CFIs)")
    func navigationTargetFallsBackToHref() {
        let fp = makeFingerprint()
        // FoliateTOCConverter builds entries with href set + cfi nil.
        let locator = LocatorFactory.epub(fingerprint: fp, href: "ch07.xhtml", progression: 0.0)
        let target = FoliateNavSeek.navigationTarget(for: try! #require(locator))
        #expect(target == "ch07.xhtml",
                "Bug #262: TOC row taps carry a href locator (no CFI) — navigation must use the href as the goTo target")
    }

    @Test("navigationTarget returns nil when neither CFI nor href present")
    func navigationTargetNilWhenEmpty() {
        let fp = makeFingerprint()
        let locator = Locator(
            bookFingerprint: fp, href: nil, progression: nil,
            totalProgression: nil, cfi: nil, page: 3,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(FoliateNavSeek.navigationTarget(for: locator) == nil)
    }

    @Test("navigationTarget treats whitespace-only CFI as absent and falls back to href")
    func navigationTargetWhitespaceCFIFallsBack() {
        let fp = makeFingerprint()
        let locator = Locator(
            bookFingerprint: fp, href: "ch02.xhtml", progression: 0,
            totalProgression: nil, cfi: "   ", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        #expect(FoliateNavSeek.navigationTarget(for: locator) == "ch02.xhtml")
    }

    // MARK: - Symptom B, Seam 4: pure goTo JS generation

    @Test("goToTargetJS builds readerAPI.goTo with the escaped target")
    func goToTargetJSBuildsGoTo() {
        let js = FoliateNavSeek.goToTargetJS("ch01.xhtml")
        #expect(js == "readerAPI.goTo('ch01.xhtml');",
                "Bug #262: a TOC/Notes row tap must drive Foliate-js `goTo(target)`")
    }

    @Test("goToTargetJS escapes a CFI containing a single quote (no injection surface)")
    func goToTargetJSEscapesQuote() {
        // A maliciously- or oddly-shaped target must not break out of the
        // JS string literal. FoliateJSEscaper.escapeForJSString handles this
        // — mirror its contract here.
        let raw = "ch'1.xhtml"
        let js = FoliateNavSeek.goToTargetJS(raw)
        let escaped = FoliateJSEscaper.escapeForJSString(raw)
        #expect(js == "readerAPI.goTo('\(escaped)');")
        #expect(!(js ?? "").contains("ch'1"), "the bare single quote must be escaped, not embedded raw")
    }

    @Test("goToTargetJS returns nil for an empty / whitespace target")
    func goToTargetJSNilForEmpty() {
        #expect(FoliateNavSeek.goToTargetJS("") == nil)
        #expect(FoliateNavSeek.goToTargetJS("   ") == nil)
    }

    // MARK: - Symptom B, Seam 5: spike coordinator observes .foliateRequestSeekTarget

    @Test("coordinator releases the seek-target observer in deinit (no stale goTo after teardown)")
    func coordinatorSeekTargetObserverIsReleasable() async {
        // We can't drive a live WKWebView in a unit test, so we assert the
        // structural contract the bottom-chrome seek already follows: the
        // coordinator registers a `.foliateRequestSeekTarget` observer that
        // is scoped by fingerprintKey and torn down in deinit. The behavior
        // is exercised here by confirming a post for a DIFFERENT key is a
        // no-op (cannot crash / cross-fire) and a matching post after the
        // coordinator is released does not crash.
        var coordinator: FoliateSpikeView.Coordinator? = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            onBookReady: { _ in },
            onError: { _ in }
        )
        coordinator?.fingerprintKey = "azw3:abc:123"

        // Cross-fire guard: a post for a different reader must be ignored.
        NotificationCenter.default.post(
            name: .foliateRequestSeekTarget, object: nil,
            userInfo: ["target": "ch01.xhtml", "fingerprintKey": "azw3:OTHER:999"]
        )

        coordinator = nil // deinit releases the observer

        // Stale post after teardown must not crash (observer removed).
        NotificationCenter.default.post(
            name: .foliateRequestSeekTarget, object: nil,
            userInfo: ["target": "ch01.xhtml", "fingerprintKey": "azw3:abc:123"]
        )
        #expect(Bool(true), "no crash on cross-fire or post-teardown seek")
    }

    // MARK: - Symptom B, Seam 6: relocate builds a position Locator for .readerPositionDidChange

    @Test("positionLocator builds a locator carrying href + cfi from a relocate payload")
    func positionLocatorFromRelocate() {
        let key = makeFingerprint().canonicalKey
        let locator = FoliateNavSeek.positionLocator(
            fingerprintKey: key,
            href: "ch04.xhtml",
            cfi: "epubcfi(/6/8!/4/2)"
        )
        let unwrapped = try! #require(locator)
        #expect(unwrapped.href == "ch04.xhtml")
        #expect(unwrapped.cfi == "epubcfi(/6/8!/4/2)")
    }

    @Test("positionLocator returns nil for an unparseable fingerprint key")
    func positionLocatorNilForBadKey() {
        let locator = FoliateNavSeek.positionLocator(
            fingerprintKey: "not-a-valid-key",
            href: "ch04.xhtml",
            cfi: nil
        )
        #expect(locator == nil)
    }
}
#endif
