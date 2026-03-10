// Purpose: Query execution logic for the FTS5 search index. Handles FTS5 query
// building, result mapping, per-occurrence snippet extraction, and span map lookups.
//
// Key decisions:
// - All queries go through SearchIndexCore.query() — no raw pointer access.
// - Lock scope managed by core.withLock() for multi-step operations.
// - extractSnippet is static (pure function) for testability.
// - Extracted from SearchIndexStore in WI-007.
//
// @coordinates-with: SearchIndexCore.swift, SearchIndexStore.swift,
//   SearchTextNormalizer.swift, SearchTokenizer.swift

import Foundation

/// Executes search queries against a SearchIndexCore.
final class SearchQueryExecutor: @unchecked Sendable {

    private let core: SearchIndexCore

    init(core: SearchIndexCore) {
        self.core = core
    }

    // MARK: - Public API

    /// Searches the FTS5 index for the given query within a specific book.
    func search(query: String, bookFingerprintKey: String, limit: Int = 50) throws -> [SearchHit] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let safeLimit = limit
        let normalized = SearchTextNormalizer.normalize(query)
        let normalizedQuery = SearchTextNormalizer.segmentCJK(normalized)
        guard !normalizedQuery.isEmpty else { return [] }

        let escapedQuery = SearchTokenizer.escapeFTS5Query(normalizedQuery)
        guard !escapedQuery.isEmpty else { return [] }

        return try core.withLock {
            let sql = """
                SELECT fingerprint_key, source_unit_id
                FROM search_index WHERE search_index MATCH ? AND fingerprint_key = ?
            """
            let ftsQuery = "content : \(escapedQuery)"

            let ftsRows = try core.query(sql, params: [ftsQuery, bookFingerprintKey]) { row in
                (fpKey: row.text(0), unitId: row.text(1))
            }

            var results: [SearchHit] = []
            for row in ftsRows {
                let allOffsets = try findAllMatchOffsetsUnlocked(
                    fingerprintKey: row.fpKey,
                    sourceUnitId: row.unitId,
                    normalizedQuery: normalizedQuery
                )
                let originalText = try fetchSourceTextUnlocked(
                    fingerprintKey: row.fpKey,
                    sourceUnitId: row.unitId
                )

                for offsets in allOffsets {
                    let snippet = Self.extractSnippet(
                        from: originalText,
                        matchStart: offsets.start,
                        matchEnd: offsets.end,
                        contextChars: 40
                    )
                    results.append(SearchHit(
                        fingerprintKey: row.fpKey,
                        sourceUnitId: row.unitId,
                        snippet: snippet,
                        matchStartOffsetUTF16: offsets.start,
                        matchEndOffsetUTF16: offsets.end
                    ))
                    if results.count >= safeLimit { break }
                }
                if results.count >= safeLimit { break }
            }
            return results
        }
    }

    /// Retrieves token spans for a specific source unit and optional token filter.
    func tokenSpans(fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil) throws -> [TokenSpan] {
        try core.withLock {
            try tokenSpansUnlocked(
                fingerprintKey: fingerprintKey,
                sourceUnitId: sourceUnitId,
                normalizedToken: normalizedToken
            )
        }
    }

    // MARK: - Snippet Extraction (Static)

    /// Extracts a context snippet around match offsets in the original text.
    /// Returns `...prefix<b>match</b>suffix...` with ~contextChars on each side.
    static func extractSnippet(from text: String?, matchStart: Int, matchEnd: Int, contextChars: Int) -> String {
        guard let text, !text.isEmpty else { return "" }
        let utf16 = text.utf16
        let totalLen = utf16.count
        guard matchStart >= 0, matchStart < totalLen, matchEnd >= matchStart else { return "" }
        let safeEnd = max(matchStart, min(matchEnd, totalLen))

        let windowStart = max(0, matchStart - contextChars)
        let windowEnd = min(totalLen, safeEnd + contextChars)

        let startIdx = String.Index(utf16Offset: windowStart, in: text)
        let matchStartIdx = String.Index(utf16Offset: matchStart, in: text)
        let matchEndIdx = String.Index(utf16Offset: safeEnd, in: text)
        let endIdx = String.Index(utf16Offset: windowEnd, in: text)

        let prefix = windowStart > 0 ? "..." : ""
        let suffix = windowEnd < totalLen ? "..." : ""
        let before = String(text[startIdx..<matchStartIdx])
        let match = String(text[matchStartIdx..<matchEndIdx])
        let after = String(text[matchEndIdx..<endIdx])

        return "\(prefix)\(before)<b>\(match)</b>\(after)\(suffix)"
    }

    // MARK: - Private (Unlocked — must be called within core.withLock)

    private func tokenSpansUnlocked(
        fingerprintKey: String, sourceUnitId: String, normalizedToken: String? = nil
    ) throws -> [TokenSpan] {
        var sql = """
            SELECT fingerprint_key, source_unit_id, normalized_token,
                   start_offset_utf16, end_offset_utf16
            FROM token_spans WHERE fingerprint_key = ? AND source_unit_id = ?
        """
        var params = [fingerprintKey, sourceUnitId]
        if let token = normalizedToken {
            sql += " AND normalized_token = ?"
            params.append(token)
        }
        sql += " ORDER BY start_offset_utf16 ASC"

        return try core.query(sql, params: params) { row in
            TokenSpan(
                bookFingerprintKey: row.text(0),
                normalizedToken: row.text(2),
                startOffsetUTF16: Int(row.int64(3)),
                endOffsetUTF16: Int(row.int64(4)),
                sourceUnitId: row.text(1)
            )
        }
    }

    private func findAllMatchOffsetsUnlocked(
        fingerprintKey: String, sourceUnitId: String, normalizedQuery: String
    ) throws -> [(start: Int, end: Int)] {
        let queryTokens = normalizedQuery.split(separator: " ").map(String.init)
        guard let firstTokenStr = queryTokens.first else { return [] }

        let firstSpans = try tokenSpansUnlocked(
            fingerprintKey: fingerprintKey,
            sourceUnitId: sourceUnitId,
            normalizedToken: firstTokenStr
        )
        guard !firstSpans.isEmpty else { return [] }

        if queryTokens.count == 1 {
            return firstSpans.map { ($0.startOffsetUTF16, $0.endOffsetUTF16) }
        }

        var spansByToken: [String: [TokenSpan]] = [firstTokenStr: firstSpans]
        for token in queryTokens.dropFirst() where spansByToken[token] == nil {
            spansByToken[token] = try tokenSpansUnlocked(
                fingerprintKey: fingerprintKey,
                sourceUnitId: sourceUnitId,
                normalizedToken: token
            )
        }

        let maxTokenGap = 50
        var results: [(start: Int, end: Int)] = []
        for firstSpan in firstSpans {
            var currentEnd = firstSpan.endOffsetUTF16
            var valid = true
            for token in queryTokens.dropFirst() {
                guard let spans = spansByToken[token],
                      let nextSpan = spans.first(where: { $0.startOffsetUTF16 >= currentEnd }),
                      nextSpan.startOffsetUTF16 - currentEnd <= maxTokenGap else {
                    valid = false
                    break
                }
                currentEnd = nextSpan.endOffsetUTF16
            }
            if valid {
                results.append((firstSpan.startOffsetUTF16, currentEnd))
            }
        }
        return results
    }

    private func fetchSourceTextUnlocked(fingerprintKey: String, sourceUnitId: String) throws -> String? {
        let sql = "SELECT original_text FROM source_texts WHERE fingerprint_key = ? AND source_unit_id = ?"
        let rows = try core.query(sql, params: [fingerprintKey, sourceUnitId]) { row in
            row.text(0)
        }
        return rows.first
    }
}
