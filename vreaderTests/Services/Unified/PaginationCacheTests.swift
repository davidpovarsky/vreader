// Purpose: Tests for PaginationCache — in-memory pagination result caching.
// Validates cache hit/miss, invalidation by parameter change, and bulk clear.
//
// @coordinates-with PaginationCache.swift, TextKit2PageInfo (TextKit2Paginator.swift)

import Testing
import Foundation
@testable import vreader

@Suite("PaginationCache")
struct PaginationCacheTests {

    // MARK: - Helpers

    private func sampleKey(
        fingerprint: String = "doc-abc",
        fontSize: CGFloat = 17,
        fontName: String = "Georgia",
        lineSpacing: CGFloat = 1.4,
        viewportWidth: CGFloat = 375,
        viewportHeight: CGFloat = 667
    ) -> PaginationCacheKey {
        PaginationCacheKey(
            documentFingerprint: fingerprint,
            fontSize: fontSize,
            fontName: fontName,
            lineSpacing: lineSpacing,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    private func samplePages() -> [PaginationCachePage] {
        [
            PaginationCachePage(pageIndex: 0, charLocation: 0, charLength: 500),
            PaginationCachePage(pageIndex: 1, charLocation: 500, charLength: 500),
            PaginationCachePage(pageIndex: 2, charLocation: 1000, charLength: 300),
        ]
    }

    // MARK: - Cache Hit / Miss

    @Test func cacheMiss_returnsNil() {
        let cache = PaginationCache()
        let result = cache.get(key: sampleKey())
        #expect(result == nil)
    }

    @Test func cacheHit_returnsCachedPages() {
        let cache = PaginationCache()
        let key = sampleKey()
        let pages = samplePages()
        cache.set(key: key, pages: pages)

        let result = cache.get(key: key)
        #expect(result == pages)
    }

    @Test func sameParams_hits() {
        let cache = PaginationCache()
        let key1 = sampleKey()
        let key2 = sampleKey() // identical params
        let pages = samplePages()
        cache.set(key: key1, pages: pages)

        let result = cache.get(key: key2)
        #expect(result == pages)
    }

    // MARK: - Invalidation by Parameter Change

    @Test func fontSizeChange_invalidates() {
        let cache = PaginationCache()
        let key = sampleKey(fontSize: 17)
        cache.set(key: key, pages: samplePages())

        let differentKey = sampleKey(fontSize: 20)
        #expect(cache.get(key: differentKey) == nil)
    }

    @Test func fontNameChange_invalidates() {
        let cache = PaginationCache()
        let key = sampleKey(fontName: "Georgia")
        cache.set(key: key, pages: samplePages())

        let differentKey = sampleKey(fontName: "Helvetica")
        #expect(cache.get(key: differentKey) == nil)
    }

    @Test func lineSpacingChange_invalidates() {
        let cache = PaginationCache()
        let key = sampleKey(lineSpacing: 1.4)
        cache.set(key: key, pages: samplePages())

        let differentKey = sampleKey(lineSpacing: 1.8)
        #expect(cache.get(key: differentKey) == nil)
    }

    @Test func viewportWidthChange_invalidates() {
        let cache = PaginationCache()
        let key = sampleKey(viewportWidth: 375)
        cache.set(key: key, pages: samplePages())

        let differentKey = sampleKey(viewportWidth: 414)
        #expect(cache.get(key: differentKey) == nil)
    }

    @Test func viewportHeightChange_invalidates() {
        let cache = PaginationCache()
        let key = sampleKey(viewportHeight: 667)
        cache.set(key: key, pages: samplePages())

        let differentKey = sampleKey(viewportHeight: 812)
        #expect(cache.get(key: differentKey) == nil)
    }

    // MARK: - invalidateAll

    @Test func invalidateAll_clearsEverything() {
        let cache = PaginationCache()
        cache.set(key: sampleKey(fingerprint: "doc-1"), pages: samplePages())
        cache.set(key: sampleKey(fingerprint: "doc-2"), pages: samplePages())

        cache.invalidateAll()

        #expect(cache.get(key: sampleKey(fingerprint: "doc-1")) == nil)
        #expect(cache.get(key: sampleKey(fingerprint: "doc-2")) == nil)
    }

    // MARK: - invalidate(documentFingerprint:)

    @Test func invalidateDocument_clearsOnlyThatDoc() {
        let cache = PaginationCache()
        let pagesA = samplePages()
        let pagesB = [PaginationCachePage(pageIndex: 0, charLocation: 0, charLength: 1000)]

        cache.set(key: sampleKey(fingerprint: "doc-A"), pages: pagesA)
        cache.set(key: sampleKey(fingerprint: "doc-B"), pages: pagesB)

        cache.invalidate(documentFingerprint: "doc-A")

        #expect(cache.get(key: sampleKey(fingerprint: "doc-A")) == nil)
        #expect(cache.get(key: sampleKey(fingerprint: "doc-B")) == pagesB)
    }

    @Test func invalidateDocument_multipleKeysForSameDoc_allCleared() {
        let cache = PaginationCache()
        // Same doc, different font sizes
        let key1 = sampleKey(fingerprint: "doc-X", fontSize: 14)
        let key2 = sampleKey(fingerprint: "doc-X", fontSize: 18)
        cache.set(key: key1, pages: samplePages())
        cache.set(key: key2, pages: samplePages())

        cache.invalidate(documentFingerprint: "doc-X")

        #expect(cache.get(key: key1) == nil)
        #expect(cache.get(key: key2) == nil)
    }

    // MARK: - Edge Cases

    @Test func emptyPages_cachedCorrectly() {
        let cache = PaginationCache()
        let key = sampleKey()
        cache.set(key: key, pages: [])

        let result = cache.get(key: key)
        #expect(result == [])
    }

    @Test func overwrite_replacesOldValue() {
        let cache = PaginationCache()
        let key = sampleKey()
        let oldPages = samplePages()
        let newPages = [PaginationCachePage(pageIndex: 0, charLocation: 0, charLength: 999)]

        cache.set(key: key, pages: oldPages)
        cache.set(key: key, pages: newPages)

        let result = cache.get(key: key)
        #expect(result == newPages)
    }

    @Test func invalidateNonExistentDoc_noOp() {
        let cache = PaginationCache()
        cache.set(key: sampleKey(fingerprint: "doc-1"), pages: samplePages())
        cache.invalidate(documentFingerprint: "no-such-doc")

        // Existing entry should be untouched
        #expect(cache.get(key: sampleKey(fingerprint: "doc-1")) != nil)
    }

    // MARK: - PaginationCacheKey Hashable

    @Test func cacheKey_equalWhenAllFieldsMatch() {
        let key1 = sampleKey()
        let key2 = sampleKey()
        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)
    }

    @Test func cacheKey_notEqualWhenFingerprintDiffers() {
        let key1 = sampleKey(fingerprint: "a")
        let key2 = sampleKey(fingerprint: "b")
        #expect(key1 != key2)
    }
}
