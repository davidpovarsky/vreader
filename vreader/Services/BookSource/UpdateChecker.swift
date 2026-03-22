// Purpose: Detects new chapters by comparing remote TOC chapter count
// against a stored/last-known count.
//
// Key decisions:
// - Actor-isolated for thread safety.
// - Uses BookSourcePipeline.chapters() to fetch remote TOC.
// - Rate limiting per source URL to prevent excessive checks.
// - Graceful degradation on network errors (returns nil, not throws).
//
// @coordinates-with: BookSourcePipeline.swift, PipelineTypes.swift,
//   BookSourceSnapshot, HTMLFetchProvider

import Foundation

/// Result of an update check for a single book.
struct UpdateResult: Sendable, Equatable {
    /// The source URL that was checked.
    let sourceURL: String
    /// The book URL being tracked.
    let bookURL: String
    /// The number of new chapters detected.
    let newChapterCount: Int
}

/// Checks for new chapters by comparing remote TOC against stored chapter count.
actor UpdateChecker {

    /// Minimum seconds between checks for the same source URL.
    private let minimumCheckInterval: TimeInterval

    /// Tracks when each source was last checked.
    private var lastCheckTimes: [String: Date] = [:]

    /// Creates an UpdateChecker.
    ///
    /// - Parameter minimumCheckInterval: Min seconds between checks per source (default 0).
    init(minimumCheckInterval: TimeInterval = 0) {
        self.minimumCheckInterval = minimumCheckInterval
    }

    /// Checks for new chapters on a book.
    ///
    /// Fetches the remote TOC and compares chapter count against last known.
    /// Returns nil (not throws) on network errors for graceful degradation.
    ///
    /// - Parameters:
    ///   - source: The BookSource snapshot with TOC rules.
    ///   - bookURL: The book's URL (for result identification).
    ///   - tocURL: The TOC page URL to fetch.
    ///   - lastKnownChapterCount: The previously stored chapter count.
    ///   - fetcher: The HTML fetch provider.
    ///   - sourceEnabled: Whether the source is enabled (default true).
    /// - Returns: UpdateResult if new chapters found, nil otherwise.
    func checkForUpdates(
        source: BookSourceSnapshot,
        bookURL: String,
        tocURL: String,
        lastKnownChapterCount: Int,
        fetcher: @escaping HTMLFetchProvider,
        sourceEnabled: Bool = true
    ) async throws -> UpdateResult? {
        // Skip disabled sources
        guard sourceEnabled else { return nil }

        // Skip empty TOC URL
        guard !tocURL.isEmpty else { return nil }

        // Rate limiting: skip if checked too recently
        let sourceKey = "\(source.sourceURL)|\(bookURL)"
        if let lastCheck = lastCheckTimes[sourceKey],
           minimumCheckInterval > 0 {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < minimumCheckInterval {
                return nil
            }
        }

        // Fetch TOC via pipeline
        let pipeline = BookSourcePipeline(fetchHTML: fetcher)
        let chapters: [ChapterInfo]
        do {
            chapters = try await pipeline.chapters(
                source: source, tocUrl: tocURL
            )
        } catch {
            // Graceful degradation: network/parse errors return nil
            return nil
        }

        // Record check time after successful fetch
        lastCheckTimes[sourceKey] = Date()

        let remoteCount = chapters.count

        // No new chapters if count is unchanged or decreased
        guard remoteCount > lastKnownChapterCount else { return nil }

        return UpdateResult(
            sourceURL: source.sourceURL,
            bookURL: bookURL,
            newChapterCount: remoteCount - lastKnownChapterCount
        )
    }
}
