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

import SwiftUI

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
            .overlay(alignment: .bottomTrailing) {
                if isTransient && !keepBook {
                    Button {
                        keepBook = true
                        CatalogTransientStore.unmark(book.fingerprintKey)
                    } label: {
                        Label("Save to Library", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.trailing, 18)
                    .padding(.bottom, 108)
                    .accessibilityIdentifier("catalogSaveToLibrary")
                }
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
    private static let defaultsKey = "catalog.transientFingerprintKeys"
    private static let lock = NSLock()

    static func mark(_ fingerprintKey: String) {
        lock.lock()
        defer { lock.unlock() }

        var keys = storedKeys()
        keys.insert(fingerprintKey)
        write(keys)
    }

    static func unmark(_ fingerprintKey: String) {
        lock.lock()
        defer { lock.unlock() }

        var keys = storedKeys()
        keys.remove(fingerprintKey)
        write(keys)
    }

    static func cleanupStale(using persistenceActor: PersistenceActor?) async {
        guard let persistenceActor else { return }

        let keys: Set<String> = {
            lock.lock()
            defer { lock.unlock() }
            return storedKeys()
        }()

        guard !keys.isEmpty else { return }

        guard let books = try? await persistenceActor.fetchAllLibraryBooks() else {
            return
        }

        for book in books where keys.contains(book.fingerprintKey) {
            await removeTransientBook(book, using: persistenceActor)
        }

        // Remove markers for records that no longer exist too.
        lock.lock()
        var remaining = storedKeys()
        remaining.subtract(keys)
        write(remaining)
        lock.unlock()
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

        try? await persistenceActor.deleteBook(fingerprintKey: book.fingerprintKey)
        try? FileManager.default.removeItem(at: fileURL)

        unmark(book.fingerprintKey)
    }

    private static func storedKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    private static func write(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: defaultsKey)
    }
}
