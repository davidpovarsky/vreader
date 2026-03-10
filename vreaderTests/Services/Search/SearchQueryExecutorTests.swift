// Purpose: Tests for SearchQueryExecutor — verifies FTS5 query building,
// snippet extraction, and span map lookups after extracting from SearchIndexStore.
//
// @coordinates-with: SearchQueryExecutor.swift, SearchIndexCore.swift,
//   SearchIndexStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFP = "query_executor_test_fp_000"

private let testUnits = [
    TextUnit(sourceUnitId: "seg:0", text: "Hello world this is a test document"),
    TextUnit(sourceUnitId: "seg:1", text: "Another segment with different words"),
    TextUnit(sourceUnitId: "seg:2", text: "CJK测试内容包含中文字符")
]

// MARK: - Tests

@Suite("SearchQueryExecutor")
struct SearchQueryExecutorTests {

    private func makeIndexedStore() throws -> SearchIndexStore {
        let store = try SearchIndexStore()
        try store.indexBook(fingerprintKey: testFP, textUnits: testUnits)
        return store
    }

    @Test("search returns hits with correct offsets")
    func searchReturnsHits() throws {
        let store = try makeIndexedStore()

        let hits = try store.search(query: "Hello", bookFingerprintKey: testFP)
        #expect(!hits.isEmpty)
        #expect(hits[0].fingerprintKey == testFP)
        #expect(hits[0].sourceUnitId == "seg:0")
        #expect(hits[0].matchStartOffsetUTF16 >= 0)
        #expect(hits[0].matchEndOffsetUTF16 > hits[0].matchStartOffsetUTF16)
    }

    @Test("search with CJK query returns results")
    func searchCJK() throws {
        let store = try makeIndexedStore()

        let hits = try store.search(query: "测试", bookFingerprintKey: testFP)
        #expect(!hits.isEmpty)
        #expect(hits[0].sourceUnitId == "seg:2")
    }

    @Test("empty query returns empty results")
    func emptyQuery() throws {
        let store = try makeIndexedStore()

        let hits = try store.search(query: "", bookFingerprintKey: testFP)
        #expect(hits.isEmpty)
    }

    @Test("snippet extraction returns context around match")
    func snippetExtraction() {
        let text = "The quick brown fox jumps over the lazy dog"
        let snippet = SearchIndexStore.extractSnippet(
            from: text, matchStart: 10, matchEnd: 15, contextChars: 10
        )
        #expect(snippet.contains("<b>"))
        #expect(snippet.contains("</b>"))
        #expect(snippet.contains("brown"))
    }

    @Test("snippet extraction with nil text returns empty")
    func snippetNilText() {
        let snippet = SearchIndexStore.extractSnippet(
            from: nil, matchStart: 0, matchEnd: 5, contextChars: 10
        )
        #expect(snippet == "")
    }

    @Test("tokenSpans returns spans for indexed book")
    func tokenSpansReturned() throws {
        let store = try makeIndexedStore()

        let spans = try store.tokenSpans(
            fingerprintKey: testFP,
            sourceUnitId: "seg:0",
            normalizedToken: "hello"
        )
        #expect(!spans.isEmpty)
        #expect(spans[0].normalizedToken == "hello")
    }

    @Test("concurrent search calls don't deadlock")
    func concurrentSearch() async throws {
        let store = try makeIndexedStore()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    _ = try? store.search(query: "test", bookFingerprintKey: testFP)
                }
            }
        }
        // If we reach here, no deadlock occurred
    }

    @Test("search respects limit parameter")
    func searchRespectsLimit() throws {
        let store = try SearchIndexStore()
        // Index multiple units with the same word
        var units: [TextUnit] = []
        for i in 0..<20 {
            units.append(TextUnit(sourceUnitId: "seg:\(i)", text: "test word repeated"))
        }
        try store.indexBook(fingerprintKey: testFP, textUnits: units)

        let hits = try store.search(query: "test", bookFingerprintKey: testFP, limit: 5)
        #expect(hits.count <= 5)
    }
}
