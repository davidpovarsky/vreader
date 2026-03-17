// Purpose: Tests for Phase B medium-severity audit fixes (Issues 5-10).
// Issue 5: EPUB paged CSS dynamically injected/removed on isPaged toggle.
// Issue 6: EPUB chapter navigation resets currentPaginationPage.
// Issue 7: PaginationCache wired into UnifiedTextRendererViewModel.
// Issue 8: Native TXT/MD paged mode uses NativeTextPaginator.
// Issue 9: AutoPageTurner + PageTurnAnimator wired for use.
// Issue 10: EPUB unified loading reports skipped chapters.
//
// @coordinates-with: EPUBWebViewBridge.swift, EPUBReaderContainerView.swift,
//   UnifiedTextRendererViewModel.swift, PaginationCache.swift,
//   NativeTextPaginator.swift, AutoPageTurner.swift, PageTurnAnimator.swift,
//   ReaderContainerView.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import vreader

// MARK: - Issue 5: EPUB paged CSS live injection/removal

@Suite("PhaseBMediumAudit — Issue 5: EPUB pagination CSS dynamic toggle")
struct EPUBPaginationDynamicToggleTests {

    @Test("EPUBPaginationHelper.injectPaginationCSSJS produces JS that creates style element")
    func injectCSSJS_createsStyleElement() {
        let js = EPUBPaginationHelper.injectPaginationCSSJS(viewportWidth: 375, viewportHeight: 667)
        #expect(js.contains("createElement"), "JS must create a style element")
        #expect(js.contains("vreader-pagination"), "JS must use vreader-pagination ID")
        #expect(js.contains("appendChild"), "JS must append to head")
    }

    @Test("EPUBPaginationHelper.removePaginationCSSJS removes the pagination style element")
    func removeCSSJS_removesStyleElement() {
        let js = EPUBPaginationHelper.removePaginationCSSJS
        #expect(js.contains("vreader-pagination"), "JS must target vreader-pagination ID")
        #expect(js.contains("remove"), "JS must remove the element")
    }

    @Test("EPUBWebViewBridge Coordinator tracks isPaged state for live toggle detection")
    @MainActor
    func coordinatorTracksIsPaged() {
        let coordinator = EPUBWebViewBridge.Coordinator(
            onProgressChange: { _ in },
            onLoadError: { _ in }
        )
        // Default is false
        #expect(coordinator.isPaged == false)
        coordinator.isPaged = true
        #expect(coordinator.isPaged == true)
    }

    @Test("EPUBWebViewBridge Coordinator tracks previousIsPaged for change detection")
    @MainActor
    func coordinatorTracksPreviousIsPaged() {
        let coordinator = EPUBWebViewBridge.Coordinator(
            onProgressChange: { _ in },
            onLoadError: { _ in }
        )
        // Should have a previousIsPaged property for change detection
        #expect(coordinator.previousIsPaged == false)
    }
}

// MARK: - Issue 6: EPUB chapter navigation resets pagination page

@Suite("PhaseBMediumAudit — Issue 6: chapter navigation resets pagination page")
struct EPUBChapterNavPaginationResetTests {

    @Test("BasePageNavigator reset sets currentPage to 0")
    @MainActor
    func pageNavigatorResetSetsPageToZero() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.nextPage()
        nav.nextPage()
        nav.nextPage()
        #expect(nav.currentPage == 3)

        nav.reset()
        #expect(nav.currentPage == 0)
    }

    @Test("BasePageNavigator reset clears totalPages")
    @MainActor
    func pageNavigatorResetClearsTotalPages() {
        let nav = BasePageNavigator()
        nav.totalPages = 10
        nav.nextPage()

        nav.reset()
        #expect(nav.totalPages == 0)
    }

    @Test("BasePageNavigator reset from various states")
    @MainActor
    func pageNavigatorResetFromVariousStates() {
        let nav = BasePageNavigator()

        // Reset from empty state (no-op essentially)
        nav.reset()
        #expect(nav.currentPage == 0)
        #expect(nav.totalPages == 0)

        // Reset from middle of book
        nav.totalPages = 50
        nav.jumpToPage(25)
        nav.reset()
        #expect(nav.currentPage == 0)
        #expect(nav.totalPages == 0)
    }
}

// MARK: - Issue 7: PaginationCache wired into UnifiedTextRendererViewModel

@Suite("PhaseBMediumAudit — Issue 7: PaginationCache in UnifiedTextRendererVM")
@MainActor
struct PaginationCacheWiringTests {

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    private let phoneViewport = CGSize(width: 375, height: 667)

    @Test("ViewModel accepts optional PaginationCache")
    func vmAcceptsPaginationCache() {
        let cache = PaginationCache()
        let vm = UnifiedTextRendererViewModel(text: "Hello world", cache: cache)
        #expect(vm.text == "Hello world")
    }

    @Test("ViewModel still works without cache (nil)")
    func vmWorksWithoutCache() {
        let vm = UnifiedTextRendererViewModel(text: "Hello world")
        vm.configure(font: defaultFont, viewportSize: phoneViewport, layout: .paged)
        #expect(vm.totalPages >= 1)
    }

    @Test("ViewModel stores result in cache after pagination")
    func vmStoresResultInCache() {
        let cache = PaginationCache()
        let text = String(repeating: "Test line for pagination caching. ", count: 200)
        let vm = UnifiedTextRendererViewModel(text: text, cache: cache, documentFingerprint: "test-doc-1")
        vm.configure(font: defaultFont, viewportSize: phoneViewport, layout: .paged)

        // Cache should have an entry for this configuration
        let key = PaginationCacheKey(
            documentFingerprint: "test-doc-1",
            fontSize: 17,
            fontName: defaultFont.fontName,
            lineSpacing: 0,
            viewportWidth: 375,
            viewportHeight: 667
        )
        let cached = cache.get(key: key)
        #expect(cached != nil, "Cache should have stored pagination results")
        #expect(cached?.count == vm.totalPages, "Cached page count should match VM")
    }

    @Test("ViewModel retrieves from cache on second configure with same params")
    func vmRetrievesFromCache() {
        let cache = PaginationCache()
        let text = String(repeating: "Test line for cache retrieval. ", count: 200)

        // First VM paginates and stores
        let vm1 = UnifiedTextRendererViewModel(text: text, cache: cache, documentFingerprint: "test-doc-2")
        vm1.configure(font: defaultFont, viewportSize: phoneViewport, layout: .paged)
        let firstPageCount = vm1.totalPages

        // Second VM with same cache should hit cache
        let vm2 = UnifiedTextRendererViewModel(text: text, cache: cache, documentFingerprint: "test-doc-2")
        vm2.configure(font: defaultFont, viewportSize: phoneViewport, layout: .paged)
        #expect(vm2.totalPages == firstPageCount, "Second VM should get same result from cache")
    }

    @Test("Cache invalidated on font change")
    func cacheInvalidatedOnFontChange() {
        let cache = PaginationCache()
        // Use enough text to span multiple pages at both font sizes
        let lines = (0..<300).map { _ in "This is a line of text for testing font change pagination cache invalidation." }
        let text = lines.joined(separator: "\n")

        let vm = UnifiedTextRendererViewModel(text: text, cache: cache, documentFingerprint: "test-doc-3")
        vm.configure(font: UIFont.systemFont(ofSize: 12), viewportSize: phoneViewport, layout: .paged)
        let smallFontPages = vm.totalPages

        let bigFont = UIFont.systemFont(ofSize: 28)
        vm.configure(font: bigFont, viewportSize: phoneViewport, layout: .paged)
        let bigFontPages = vm.totalPages

        #expect(bigFontPages > smallFontPages, "Bigger font should produce more pages than smaller font")
    }
}

// MARK: - Issue 8: Native TXT/MD paged mode wiring

@Suite("PhaseBMediumAudit — Issue 8: NativeTextPaginator integration")
@MainActor
struct NativeTextPaginatorIntegrationTests {

    @Test("NativeTextPaginator paginate returns pages for multi-line text")
    func paginatorReturnsPages() {
        let paginator = NativeTextPaginator()
        let text = String(repeating: "This is a line of text for testing pagination.\n", count: 100)
        let pages = paginator.paginate(
            text: text,
            font: .systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667)
        )
        #expect(pages.count > 1, "Should have multiple pages")
        #expect(paginator.totalPages == pages.count)
    }

    @Test("NativeTextPaginator provides page count and content range")
    func paginatorProvidesPageInfo() {
        let paginator = NativeTextPaginator()
        let text = String(repeating: "Short line.\n", count: 200)
        let pages = paginator.paginate(
            text: text,
            font: .systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667)
        )
        #expect(!pages.isEmpty)

        // First page should start at 0
        let firstPage = pages[0]
        #expect(firstPage.charRange.location == 0)
        #expect(firstPage.charRange.length > 0)
    }

    @Test("NativeTextPaginator handles attributed text (for MD)")
    func paginatorHandlesAttributedText() {
        let paginator = NativeTextPaginator()
        let boldFont = UIFont.boldSystemFont(ofSize: 20)
        let normalFont = UIFont.systemFont(ofSize: 17)

        let attrStr = NSMutableAttributedString()
        attrStr.append(NSAttributedString(string: "# Heading\n\n", attributes: [.font: boldFont]))
        for _ in 0..<100 {
            attrStr.append(NSAttributedString(string: "Body text line.\n", attributes: [.font: normalFont]))
        }

        let pages = paginator.paginateAttributed(
            attributedText: attrStr,
            viewportSize: CGSize(width: 375, height: 667)
        )
        #expect(pages.count > 1, "Attributed text should paginate to multiple pages")
    }

    @Test("NativeTextPaginator empty text returns zero pages")
    func paginatorEmptyTextReturnsZero() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "",
            font: .systemFont(ofSize: 17),
            viewportSize: CGSize(width: 375, height: 667)
        )
        #expect(pages.isEmpty, "Empty text should have zero pages")
    }
}

// MARK: - Issue 9: AutoPageTurner + PageTurnAnimator availability

@Suite("PhaseBMediumAudit — Issue 9: AutoPageTurner wiring readiness")
struct AutoPageTurnerWiringTests {

    @Test @MainActor
    func autoPageTurnerCanBeStartedWithBasePageNavigator() {
        let turner = AutoPageTurner()
        let nav = BasePageNavigator()
        nav.totalPages = 10

        turner.start(navigator: nav)
        #expect(turner.state == .running)
        turner.stop()
    }

    @Test @MainActor
    func pageTurnAnimatorDurationRespectsSetting() {
        // Verify animations work with explicit reduceMotion flag
        let slideDuration = PageTurnAnimator.duration(for: .slide, reduceMotion: false)
        #expect(slideDuration == 0.3)

        let coverDuration = PageTurnAnimator.duration(for: .cover, reduceMotion: false)
        #expect(coverDuration == 0.3)

        let noneDuration = PageTurnAnimator.duration(for: .none, reduceMotion: false)
        #expect(noneDuration == 0)
    }

    @Test("ReaderSettingsStore has autoPageTurn setting")
    @MainActor
    func settingsStoreHasAutoPageTurnSetting() {
        let defaults = UserDefaults(suiteName: "test-audit-9")!
        defaults.removePersistentDomain(forName: "test-audit-9")
        let store = ReaderSettingsStore(defaults: defaults)
        // autoPageTurn should default to false
        #expect(store.autoPageTurn == false)

        store.autoPageTurn = true
        #expect(store.autoPageTurn == true)

        // Should persist
        let store2 = ReaderSettingsStore(defaults: defaults)
        #expect(store2.autoPageTurn == true)
    }

    @Test("ReaderSettingsStore has autoPageTurnInterval setting")
    @MainActor
    func settingsStoreHasAutoPageTurnInterval() {
        let defaults = UserDefaults(suiteName: "test-audit-9-interval")!
        defaults.removePersistentDomain(forName: "test-audit-9-interval")
        let store = ReaderSettingsStore(defaults: defaults)
        // Should have a default interval
        #expect(store.autoPageTurnInterval >= 1.0)
        #expect(store.autoPageTurnInterval <= 60.0)

        store.autoPageTurnInterval = 10.0
        #expect(store.autoPageTurnInterval == 10.0)
    }
}

// MARK: - Issue 10: EPUB unified loading skipped chapter reporting

@Suite("PhaseBMediumAudit — Issue 10: EPUB unified load skipped chapter count")
@MainActor
struct EPUBUnifiedLoadSkippedChaptersTests {

    @Test("EPUBTextStripper.attributedString returns nil for invalid HTML")
    func stripperReturnsNilForInvalidHTML() {
        // attributedString(from:) should return nil for content it can't process
        let result = EPUBTextStripper.attributedString(from: "")
        #expect(result == nil, "Empty HTML should return nil")
    }

    @Test("EPUBTextStripper.attributedString returns content for valid HTML")
    func stripperReturnsContentForValidHTML() {
        let html = "<html><body><p>Hello World</p></body></html>"
        let result = EPUBTextStripper.attributedString(from: html)
        #expect(result != nil, "Valid HTML should return attributed string")
    }

    @Test("EPUBTextStripper.shouldUseNative detects complex HTML")
    func stripperDetectsComplexHTML() {
        // Complex HTML (with SVG, MathML, etc.) should be flagged
        let complexHTML = "<html><body><svg><circle/></svg></body></html>"
        let isComplex = EPUBTextStripper.shouldUseNative(html: complexHTML)
        #expect(isComplex, "HTML with SVG should be detected as complex")
    }

    @Test("Unified EPUB load should count skipped chapters")
    func unifiedLoadCountsSkippedChapters() {
        // UnifiedEPUBLoadResult should track skipped chapter count
        let result = UnifiedEPUBLoadResult(
            text: "Combined text",
            attributedText: NSAttributedString(string: "Combined text"),
            skippedChapterCount: 3,
            totalChapterCount: 10
        )
        #expect(result.skippedChapterCount == 3)
        #expect(result.totalChapterCount == 10)
        #expect(result.hasSkippedChapters)
    }

    @Test("UnifiedEPUBLoadResult with no skipped chapters reports clean")
    func noSkippedChaptersIsClean() {
        let result = UnifiedEPUBLoadResult(
            text: "All chapters loaded",
            attributedText: NSAttributedString(string: "All chapters loaded"),
            skippedChapterCount: 0,
            totalChapterCount: 5
        )
        #expect(result.skippedChapterCount == 0)
        #expect(!result.hasSkippedChapters)
    }

    @Test("UnifiedEPUBLoadResult with all chapters failed")
    func allChaptersFailed() {
        let result = UnifiedEPUBLoadResult(
            text: nil,
            attributedText: nil,
            skippedChapterCount: 5,
            totalChapterCount: 5
        )
        #expect(result.allChaptersFailed)
        #expect(result.hasSkippedChapters)
    }

    @Test("UnifiedEPUBLoadResult edge case: zero total chapters")
    func zeroTotalChapters() {
        let result = UnifiedEPUBLoadResult(
            text: nil,
            attributedText: nil,
            skippedChapterCount: 0,
            totalChapterCount: 0
        )
        #expect(!result.hasSkippedChapters)
        #expect(result.allChaptersFailed) // empty book = all failed
    }
}
#endif
