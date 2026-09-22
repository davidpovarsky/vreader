// Purpose: Temporary catalog-reader lifecycle.
//
// The existing reader expects a normal persisted LibraryBookItem. Rather than
// duplicate every PDF/EPUB reader engine, catalog opens reuse the exact upstream
// importer + reader and mark a newly imported book as transient. If the user
// leaves the reader without choosing "Save to Library", this layer removes the
// database record and sandbox file. Existing library duplicates are never
// transient and are therefore never deleted.
//
// A small UserDefaults registry makes the lifecycle crash-safe: if the process
// is killed while a transient catalog book is open, the next home appearance
// removes the abandoned transient import.

import Foundation
import SwiftUI

extension Notification.Name {
    static let catalogBookSavedToLibrary =
        Notification.Name("vreader.catalog.savedToLibrary")
}

/// Save affordance intentionally mirrors the existing BilingualPill language:
/// accent-tinted capsule, compact type, and the same pressed-state style.
/// It is rendered INSIDE ReaderTopChrome, not as a foreign floating button.
struct CatalogReaderSavePill: View {
    let theme: ReaderThemeV2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Text("Save")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color(theme.accentColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color(theme.accentColor).opacity(0.10))
            )
            .padding(.leading, 6)
        }
        .buttonStyle(BilingualPillButtonStyle(theme: theme))
        .accessibilityLabel("Save to Library")
        .accessibilityIdentifier("catalogSaveToLibrary")
    }
}

struct CatalogTransientReaderView: View {
    let book: LibraryBookItem
    let isTransient: Bool

    @Environment(\.persistenceActor) private var persistenceActor

    @State private var keepBook: Bool
    @State private var cleanupStarted = false

    init(book: LibraryBookItem, isTransient: Bool) {
        self.book = book
        self.isTransient = isTransient
        _keepBook = State(initialValue: !isTransient)
    }

    var body: some View {
        ReaderContainerView(book: book)
            .onReceive(NotificationCenter.default.publisher(
                for: .catalogBookSavedToLibrary
            )) { notification in
                guard let key = notification.userInfo?["fingerprintKey"] as? String,
                      key == book.fingerprintKey else { return }
                keepBook = true
            }
            .onDisappear {
                guard isTransient, !keepBook, !cleanupStarted else { return }
                cleanupStarted = true

                Task {
                    await CatalogTransientStore.removeTransientBook(
                        book,
                        using: persistenceActor
                    )
                }
            }
    }
}

enum CatalogTransientStore {
    private static let defaultsKey = "catalog.transientFingerprintSessions"

    /// Stable for the lifetime of this process. A SwiftUI view rebuild while
    /// backgrounding keeps the same id, so currently-open transient books are
    /// never mistaken for stale leftovers. A real process relaunch gets a new
    /// id, making abandoned prior-session imports eligible for cleanup.
    private static let currentSessionID = UUID().uuidString

    static func isMarked(_ fingerprintKey: String) -> Bool {
        storedSessions()[fingerprintKey] != nil
    }

    static func mark(_ fingerprintKey: String) {
        var sessions = storedSessions()
        sessions[fingerprintKey] = currentSessionID
        write(sessions)
    }

    static func unmark(_ fingerprintKey: String) {
        var sessions = storedSessions()
        sessions.removeValue(forKey: fingerprintKey)
        write(sessions)
    }

    static func cleanupStale(using persistenceActor: PersistenceActor?) async {
        guard let persistenceActor else { return }

        let sessions = storedSessions()
        let staleKeys = Set(
            sessions.compactMap { key, sessionID in
                sessionID == currentSessionID ? nil : key
            }
        )
        guard !staleKeys.isEmpty else { return }

        guard let books = try? await persistenceActor.fetchAllLibraryBooks() else {
            return
        }

        for book in books where staleKeys.contains(book.fingerprintKey) {
            await removeTransientBook(book, using: persistenceActor)
        }

        // Also clear markers whose database rows are already gone.
        var remaining = storedSessions()
        for key in staleKeys {
            remaining.removeValue(forKey: key)
        }
        write(remaining)
    }

    static func removeTransientBook(
        _ book: LibraryBookItem,
        using persistenceActor: PersistenceActor?
    ) async {
        guard let persistenceActor else { return }

        let fileURL = ImportedBookFileURL.resolveExisting(
            fingerprintKey: book.fingerprintKey,
            format: book.format
        )

        // EPUB imports may already have a persistent extraction cache. Resolve
        // it before deleting the file, because the cache key reads file attrs.
        let epubCacheURL: URL? = {
            guard book.format.lowercased() == "epub" else { return nil }
            return try? EPUBPreExtractor.cacheDirectory(for: fileURL)
        }()

        try? await persistenceActor.deleteBook(fingerprintKey: book.fingerprintKey)
        try? FileManager.default.removeItem(at: fileURL)
        if let epubCacheURL {
            try? FileManager.default.removeItem(at: epubCacheURL)
        }

        unmark(book.fingerprintKey)

        // LibraryView's existing observer treats bookDidImport as a generic
        // "reload books" signal; reuse it rather than adding another upstream
        // notification seam solely for transient cleanup.
        NotificationCenter.default.post(
            name: .bookDidImport,
            object: nil,
            userInfo: ["fingerprintKey": book.fingerprintKey]
        )
    }

    private static func storedSessions() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    private static func write(_ sessions: [String: String]) {
        UserDefaults.standard.set(sessions, forKey: defaultsKey)
    }
}
