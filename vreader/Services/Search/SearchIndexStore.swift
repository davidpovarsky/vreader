// Purpose: SQLite FTS5 wrapper for full-text search indexing and querying.
// Owns SearchIndexCore (db + lock) and SearchQueryExecutor (query logic).
// Stores content in FTS5 virtual table and token positions in a span map table.
//
// Key decisions:
// - All DB access goes through SearchIndexCore — no raw SQLite3 in this file.
// - Query execution delegated to SearchQueryExecutor (WI-007).
// - In-memory database for this vertical slice (":memory:").
// - FTS5 with unicode61 tokenizer handles diacritic removal at query time.
// - Span map stores per-token UTF-16 offsets for locator resolution.
// - Thread-safe via SearchIndexCore's internal lock.
// - Re-indexing the same book DELETEs old rows before INSERT (no duplicates).
//
// @coordinates-with: SearchIndexCore.swift, SearchQueryExecutor.swift,
//   SearchTextExtractor.swift, SearchTextNormalizer.swift,
//   SearchHitToLocatorResolver.swift, TokenSpan.swift, SearchTokenizer.swift

import Foundation

/// A search result from the FTS5 index.
struct SearchHit: Sendable, Equatable {
    /// Canonical fingerprint key of the book.
    let fingerprintKey: String
    /// Source unit ID (e.g., "epub:chapter1.xhtml", "pdf:page:0", "txt:segment:0").
    let sourceUnitId: String
    /// Snippet of matching text (may contain FTS5 highlight markers).
    let snippet: String?
    /// Start offset of the match in UTF-16 code units within the source unit.
    let matchStartOffsetUTF16: Int
    /// End offset of the match in UTF-16 code units within the source unit.
    let matchEndOffsetUTF16: Int
}

/// Errors from SearchIndexStore operations.
enum SearchIndexError: Error, Sendable {
    case databaseOpenFailed(String)
    case queryFailed(String)
    case indexFailed(String)
}

/// SQLite FTS5 search index with token span map for offset resolution.
/// Thread-safe via SearchIndexCore's internal lock — callers may call from any thread.
final class SearchIndexStore: @unchecked Sendable {

    private let core: SearchIndexCore
    private let queryExecutor: SearchQueryExecutor

    /// Creates a new in-memory search index.
    init() throws {
        let core = try SearchIndexCore()
        self.core = core
        self.queryExecutor = SearchQueryExecutor(core: core)
        try createTables()
    }

    // MARK: - Schema

    private func createTables() throws {
        try core.exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                fingerprint_key, source_unit_id, content,
                tokenize='unicode61 remove_diacritics 2'
            )
        """)

        try core.exec("""
            CREATE TABLE IF NOT EXISTS token_spans (
                fingerprint_key TEXT NOT NULL,
                source_unit_id TEXT NOT NULL,
                normalized_token TEXT NOT NULL,
                start_offset_utf16 INTEGER NOT NULL,
                end_offset_utf16 INTEGER NOT NULL
            )
        """)

        try core.exec("""
            CREATE INDEX IF NOT EXISTS idx_spans_lookup
            ON token_spans(fingerprint_key, source_unit_id, normalized_token)
        """)

        // Store original texts for per-occurrence snippet generation (bug #28).
        try core.exec("""
            CREATE TABLE IF NOT EXISTS source_texts (
                fingerprint_key TEXT NOT NULL,
                source_unit_id TEXT NOT NULL,
                original_text TEXT NOT NULL,
                PRIMARY KEY (fingerprint_key, source_unit_id)
            )
        """)
    }

    // MARK: - Indexing

    /// Removes all indexed data for a book.
    func removeBook(fingerprintKey: String) throws {
        try core.withLock {
            try core.exec("BEGIN TRANSACTION")
            do {
                try deleteBookDataUnlocked(fingerprintKey: fingerprintKey)
                try core.exec("COMMIT")
            } catch {
                try? core.exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Indexes a book's text units into FTS5 and the span map.
    /// Re-indexing the same book replaces existing rows (no duplicates).
    /// Empty textUnits clears stale data for the book without inserting new rows.
    func indexBook(fingerprintKey: String, textUnits: [TextUnit]) throws {
        try core.withLock {
            try core.exec("BEGIN TRANSACTION")
            do {
                try deleteBookDataUnlocked(fingerprintKey: fingerprintKey)

                let ftsSQL = "INSERT INTO search_index(fingerprint_key, source_unit_id, content) VALUES (?, ?, ?)"
                let srcSQL = "INSERT INTO source_texts(fingerprint_key, source_unit_id, original_text) VALUES (?, ?, ?)"
                for unit in textUnits {
                    let normalized = SearchTextNormalizer.normalize(unit.text)
                    let segmented = SearchTextNormalizer.segmentCJK(normalized)
                    try core.execBind(ftsSQL, params: [fingerprintKey, unit.sourceUnitId, segmented])
                    try core.execBind(srcSQL, params: [fingerprintKey, unit.sourceUnitId, unit.text])
                }
                for unit in textUnits {
                    try indexSpans(fingerprintKey: fingerprintKey, sourceUnitId: unit.sourceUnitId, text: unit.text)
                }
                try core.exec("COMMIT")
            } catch {
                try? core.exec("ROLLBACK")
                throw error
            }
        }
    }

    /// Deletes all rows for a book across all tables. Must be called within core.withLock.
    private func deleteBookDataUnlocked(fingerprintKey: String) throws {
        try core.execBind("DELETE FROM search_index WHERE fingerprint_key = ?", params: [fingerprintKey])
        try core.execBind("DELETE FROM token_spans WHERE fingerprint_key = ?", params: [fingerprintKey])
        try core.execBind("DELETE FROM source_texts WHERE fingerprint_key = ?", params: [fingerprintKey])
    }

    private func indexSpans(fingerprintKey: String, sourceUnitId: String, text: String) throws {
        let tokens = SearchTokenizer.tokenize(text)
        let sql = """
            INSERT INTO token_spans(fingerprint_key, source_unit_id, normalized_token,
                                    start_offset_utf16, end_offset_utf16) VALUES (?, ?, ?, ?, ?)
        """
        for token in tokens {
            try core.execBind(sql, params: [
                fingerprintKey, sourceUnitId, token.normalized,
                "\(token.startUTF16)", "\(token.endUTF16)"
            ])
        }
    }

    // MARK: - Searching (delegated to SearchQueryExecutor)

    /// Searches the FTS5 index for the given query within a specific book.
    func search(query: String, bookFingerprintKey: String, limit: Int = 50) throws -> [SearchHit] {
        try queryExecutor.search(query: query, bookFingerprintKey: bookFingerprintKey, limit: limit)
    }

    /// Retrieves token spans for a specific source unit and optional token filter.
    func tokenSpans(fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil) throws -> [TokenSpan] {
        try queryExecutor.tokenSpans(fingerprintKey: fingerprintKey, sourceUnitId: sourceUnitId, normalizedToken: normalizedToken)
    }

    /// Extracts a context snippet around match offsets in the original text.
    static func extractSnippet(from text: String?, matchStart: Int, matchEnd: Int, contextChars: Int) -> String {
        SearchQueryExecutor.extractSnippet(from: text, matchStart: matchStart, matchEnd: matchEnd, contextChars: contextChars)
    }
}
