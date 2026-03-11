// Purpose: ViewModel for the PDF reader. Manages page tracking, position
// persistence (via ReaderPositionService), session tracking, and pages-per-hour.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Position persistence delegated to ReaderPositionService (WI-008a).
// - Periodic session flush (60s).
// - Page-based position using Locator.page (zero-based index).
// - Tracks distinct pages visited via Set<Int> for pagesRead.
// - Password flow: needsPassword drives UI, bridge callbacks confirm.
// - Empty PDF (0 pages): totalProgression = nil.
//
// @coordinates-with: ReaderPositionService.swift, ReadingPositionPersisting.swift,
//   ReadingSessionTracker.swift, LocatorFactory.swift, PDFViewBridge.swift

import Foundation

/// ViewModel for the PDF reader screen.
@Observable
@MainActor
final class PDFReaderViewModel {

    // MARK: - Constants

    /// Periodic flush interval for session duration (seconds).
    static let sessionFlushInterval: TimeInterval = 60.0

    // MARK: - Published State

    /// Current page index (zero-based).
    private(set) var currentPageIndex: Int = 0

    /// Total number of pages in the PDF.
    private(set) var totalPages: Int = 0

    /// Whether the PDF document has been loaded.
    private(set) var isDocumentLoaded: Bool = false

    /// Whether the document requires a password to open.
    private(set) var needsPassword: Bool = false

    /// Whether the file is currently loading.
    private(set) var isLoading: Bool = false

    /// Error message from the last failed operation.
    private(set) var errorMessage: String?

    /// Formatted session reading time (e.g., "5m").
    private(set) var sessionTimeDisplay: String?

    /// Number of distinct pages visited in the current session.
    private(set) var distinctPagesVisited: Int = 0

    // MARK: - Computed State

    /// Total progression through the document (0.0 to 1.0). Nil for empty PDFs.
    var totalProgression: Double? {
        guard totalPages > 0 else { return nil }
        return Double(currentPageIndex) / Double(max(totalPages - 1, 1))
    }

    /// Display string for current page (1-based) / total.
    var pageIndicator: String {
        if totalPages == 0 {
            return "0 / 0"
        }
        return "\(currentPageIndex + 1) / \(totalPages)"
    }

    /// Current pages per hour based on session data. Nil if insufficient data.
    var pagesPerHour: Double? {
        guard distinctPagesVisited > 0 else { return nil }
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        return calculatePagesPerHour(
            pagesRead: distinctPagesVisited,
            durationSeconds: Int(total)
        )
    }

    // MARK: - Dependencies

    private let bookFingerprint: DocumentFingerprint
    let bookFingerprintKey: String
    private let positionStore: any ReadingPositionPersisting
    private let sessionTracker: ReadingSessionTracker
    private let positionService: ReaderPositionService

    // MARK: - Private State

    private var flushTask: Task<Void, Never>?
    /// Date when the current active segment started (reset on resume).
    private var segmentStartDate: Date?
    /// Accumulated active reading seconds (excluding paused time).
    private var accumulatedActiveSeconds: TimeInterval = 0
    /// Set of distinct page indices visited in the current session.
    private var visitedPages: Set<Int> = []

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        positionStore: any ReadingPositionPersisting,
        sessionTracker: ReadingSessionTracker,
        deviceId: String,
        positionSaveDebounceNs: UInt64 = 2_000_000_000
    ) {
        self.bookFingerprint = bookFingerprint
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.positionStore = positionStore
        self.sessionTracker = sessionTracker
        self.positionService = ReaderPositionService(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            deviceId: deviceId,
            persistence: positionStore,
            debounceNanoseconds: positionSaveDebounceNs
        )
    }

    // MARK: - Document Lifecycle (called by bridge)

    /// Called when the PDFView successfully loads the document.
    func documentDidLoad(totalPages: Int) {
        self.totalPages = max(0, totalPages)
        self.isDocumentLoaded = true
        self.isLoading = false
        self.needsPassword = false
    }

    /// Called when the document requires a password.
    func documentNeedsPassword() {
        needsPassword = true
        isLoading = false
    }

    /// Called when the user submits a correct password.
    func passwordAccepted(totalPages: Int) {
        needsPassword = false
        errorMessage = nil
        documentDidLoad(totalPages: totalPages)
    }

    /// Called when the submitted password is rejected.
    func passwordRejected() {
        errorMessage = "Incorrect password. Please try again."
    }

    /// Marks the document as loading (called before bridge starts).
    func beginLoading() {
        isLoading = true
        errorMessage = nil
    }

    /// Called when the document fails to load from the bridge.
    func documentDidFailToLoad(error: String) {
        isLoading = false
        errorMessage = error
    }

    /// Starts the reading session. Call after documentDidLoad.
    func startSession() throws {
        try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        segmentStartDate = Date()
        accumulatedActiveSeconds = 0
        visitedPages = []
        distinctPagesVisited = 0
        startPeriodicFlush()
    }

    /// Restores saved position. Returns the page index to navigate to, or nil.
    func restorePosition() async -> Int? {
        do {
            let savedLocator = try await positionStore.loadPosition(
                bookFingerprintKey: bookFingerprintKey
            )
            if let savedLocator, let savedPage = savedLocator.page {
                let clamped = clampPage(savedPage)
                currentPageIndex = clamped
                return clamped
            }
        } catch {
            // Position restore failed — start from page 0
        }
        return nil
    }

    /// Updates the lastOpenedAt timestamp for this book.
    func updateLastOpened() async {
        try? await positionStore.updateLastOpened(
            bookFingerprintKey: bookFingerprintKey,
            date: Date()
        )
    }

    /// Closes the reader, ending the session and flushing state.
    /// Order is load-bearing (bugs #34, #45): saveNow → recordProgress → end → stats → notify.
    func close() async {
        flushTask?.cancel()
        flushTask = nil

        if isDocumentLoaded {
            let locator = makeCurrentLocator()
            await positionService.saveNow(locator: locator)
            sessionTracker.recordProgress(locator: locator)
        }

        sessionTracker.endSessionIfNeeded()

        if let persistence = positionStore as? PersistenceActor {
            try? await persistence.recomputeStats(
                bookFingerprintKey: bookFingerprintKey,
                bookFingerprint: bookFingerprint
            )
        }

        NotificationCenter.default.post(name: .readerDidClose, object: bookFingerprintKey)
    }

    /// Called when the app moves to background while reader is open.
    /// Awaits the position save to guarantee it completes before iOS suspends.
    func onBackground() async {
        if isDocumentLoaded {
            let locator = makeCurrentLocator()
            await positionService.saveNow(locator: locator)
        }

        if let start = segmentStartDate {
            accumulatedActiveSeconds += Date().timeIntervalSince(start)
            segmentStartDate = nil
        }

        sessionTracker.pause()
        flushTask?.cancel()
        flushTask = nil
    }

    /// Called when the app returns to foreground with reader open.
    func onForeground() {
        guard isDocumentLoaded else { return }
        do {
            try sessionTracker.startSessionIfNeeded(bookFingerprint: bookFingerprint)
        } catch {
            errorMessage = "Failed to resume reading session."
            return
        }
        segmentStartDate = Date()
        startPeriodicFlush()
    }

    // MARK: - Page Changes (called by bridge)

    /// Called when the visible page changes in PDFView.
    func pageDidChange(to pageIndex: Int) {
        guard isDocumentLoaded, totalPages > 0 else { return }
        let clamped = clampPage(pageIndex)
        currentPageIndex = clamped
        visitedPages.insert(clamped)
        distinctPagesVisited = visitedPages.count
        let locator = makeCurrentLocator()
        sessionTracker.recordProgress(locator: locator)
        updateTimeDisplays()
        positionService.scheduleSave(locator: locator)
    }

    // MARK: - Locator Construction (internal for testing)

    /// Constructs a Locator for the current page position.
    func makeCurrentLocator() -> Locator {
        let progression = totalProgression

        return LocatorFactory.pdf(
            fingerprint: bookFingerprint,
            page: currentPageIndex,
            totalProgression: progression
        ) ?? Locator(
            bookFingerprint: bookFingerprint,
            href: nil, progression: nil, totalProgression: progression,
            cfi: nil, page: currentPageIndex,
            charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    // MARK: - Pages Per Hour Calculation (internal for testing)

    /// Calculates pages per hour from raw values.
    /// Returns nil if duration < 60 seconds.
    func calculatePagesPerHour(pagesRead: Int, durationSeconds: Int) -> Double? {
        guard durationSeconds >= 60, pagesRead > 0 else { return nil }
        let hours = Double(durationSeconds) / 3600.0
        return Double(pagesRead) / hours
    }

    // MARK: - Private: Session Time Tracking

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.sessionFlushInterval))
                    guard let self else { break }
                    try sessionTracker.periodicFlush()
                    updateTimeDisplays()
                } catch is CancellationError {
                    break
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    private func updateTimeDisplays() {
        var total = accumulatedActiveSeconds
        if let start = segmentStartDate {
            total += Date().timeIntervalSince(start)
        }
        let sessionSeconds = Int(total)
        sessionTimeDisplay = ReadingTimeFormatter.formatReadingTime(totalSeconds: sessionSeconds)
    }

    // MARK: - Private: Page Clamping

    private func clampPage(_ page: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        return min(max(page, 0), totalPages - 1)
    }
}
