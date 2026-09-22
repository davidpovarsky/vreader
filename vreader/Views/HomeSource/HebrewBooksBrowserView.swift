// Purpose: HebrewBooks browsing inside the exact Library visual language.
//
// The view deliberately mirrors HomeCatalogBrowserView + the original Library:
// warm-paper background, Source Serif titles, 3-column grid, list-card spacing,
// generative physical-book covers, existing LibraryCardTokens, and the existing
// ReaderContainerView transient-save flow.
//
// Tapping a result is one action: download PDF -> import -> open reader.
// A long-press/context menu offers "Save to Library" without opening.

import SwiftUI

private struct HebrewBooksOpenRoute: Identifiable {
    let book: LibraryBookItem
    let isTransient: Bool

    var id: String { book.fingerprintKey }
}

private struct HebrewBooksSearchTaskKey: Hashable {
    let query: String
    let catalogReady: Bool
}

struct HebrewBooksBrowserView: View {
    let viewMode: LibraryViewMode
    let searchQuery: String

    @Environment(\.bookImporter) private var bookImporter
    @Environment(\.persistenceActor) private var persistenceActor

    @State private var books: [HebrewBooksCatalogBook] = []
    @State private var isPreparingCatalog = true
    @State private var isLoadingPage = false
    @State private var isRefreshingCatalog = false
    @State private var errorMessage: String?
    @State private var openingBookID: Int?
    @State private var openedRoute: HebrewBooksOpenRoute?
    @State private var hasMore = true
    @State private var catalogReady = false
    @State private var bookCount: Int?

    private let pageSize = 120
    private let service = HebrewBooksCatalogService.shared

    var body: some View {
        ZStack {
            LibraryCardTokens.shellBackground
                .ignoresSafeArea()

            Group {
                if isPreparingCatalog && !catalogReady {
                    preparingState
                } else if let errorMessage, books.isEmpty {
                    errorState(errorMessage)
                } else if books.isEmpty,
                          !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptySearchState
                } else {
                    booksContent
                }
            }
        }
        .task {
            await bootstrapCatalog()
        }
        .task(
            id: HebrewBooksSearchTaskKey(
                query: searchQuery,
                catalogReady: catalogReady
            )
        ) {
            guard catalogReady else { return }

            // Small debounce so typing in the existing LibrarySearchBar does not
            // issue a SQLite query for every keystroke. Including catalogReady
            // in the task identity also covers the edge case where the user
            // begins typing while the first catalog download is still running.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await reloadBooks()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { openedRoute != nil },
                set: { if !$0 { openedRoute = nil } }
            )
        ) {
            if let route = openedRoute {
                CatalogTransientReaderView(
                    book: route.book,
                    isTransient: route.isTransient
                )
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var booksContent: some View {
        switch viewMode {
        case .grid:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceHeader

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 14),
                            count: 3
                        ),
                        spacing: 22
                    ) {
                        ForEach(books) { book in
                            gridButton(book)
                        }
                    }

                    loadMoreButton
                }
                .padding(.horizontal, LibraryCardTokens.shellContentPadding)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refreshCatalog()
            }

        case .list:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sourceHeader

                    VStack(spacing: 0) {
                        ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                            listButton(book)

                            if index < books.count - 1 {
                                Divider()
                                    .overlay(LibraryCardTokens.listRowDivider)
                                    .padding(.leading, LibraryCardTokens.rowCoverWidth + 12)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(LibraryCardTokens.listCardBackground)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: LibraryCardTokens.listCardCornerRadius,
                            style: .continuous
                        )
                    )

                    loadMoreButton
                }
                .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refreshCatalog()
            }
        }
    }

    private var sourceHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Books"
                 : "Results")
                .font(
                    LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.sectionHeaderFontSize
                    )
                )
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Spacer()

            if let bookCount,
               searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bookCount.formatted())
                    .font(.system(size: LibraryCardTokens.subtitleFontSize))
                    .foregroundStyle(LibraryCardTokens.subText)
            }

            if isRefreshingCatalog {
                ProgressView()
                    .controlSize(.small)
                    .tint(LibraryCardTokens.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func gridButton(_ book: HebrewBooksCatalogBook) -> some View {
        Button {
            guard openingBookID == nil else { return }
            Task { await open(book) }
        } label: {
            HebrewBooksBookCard(
                book: book,
                isOpening: openingBookID == book.id
            )
        }
        .buttonStyle(.plain)
        .disabled(openingBookID != nil)
        .contextMenu {
            Button {
                Task { await saveWithoutOpening(book) }
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }
        }
        .accessibilityLabel("Open \(book.title)")
    }

    private func listButton(_ book: HebrewBooksCatalogBook) -> some View {
        Button {
            guard openingBookID == nil else { return }
            Task { await open(book) }
        } label: {
            HebrewBooksBookRow(
                book: book,
                isOpening: openingBookID == book.id
            )
        }
        .buttonStyle(.plain)
        .disabled(openingBookID != nil)
        .contextMenu {
            Button {
                Task { await saveWithoutOpening(book) }
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }
        }
        .accessibilityLabel("Open \(book.title)")
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        if hasMore {
            Button {
                Task { await loadNextPage() }
            } label: {
                HStack(spacing: 8) {
                    if isLoadingPage {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isLoadingPage ? "Loading…" : "Load More")
                        .font(
                            .system(
                                size: LibraryCardTokens.subtitleFontSize,
                                weight: .medium
                            )
                        )
                }
                .foregroundStyle(LibraryCardTokens.seeAllAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPage)
        }
    }

    // MARK: - States

    private var preparingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(LibraryCardTokens.accent)

            Text("Preparing HebrewBooks…")
                .font(
                    .system(size: LibraryCardTokens.subtitleFontSize)
                )
                .foregroundStyle(LibraryCardTokens.subText)

            Text("The catalog is downloaded once and then kept on this device.")
                .font(.caption)
                .foregroundStyle(LibraryCardTokens.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(LibraryCardTokens.subText)

            Text("HebrewBooks Unavailable")
                .font(LibraryCardTokens.serifTitleFont(size: 22))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Text(message)
                .font(.body)
                .foregroundStyle(LibraryCardTokens.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task { await bootstrapCatalog(forceRefresh: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(LibraryCardTokens.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchState: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(LibraryCardTokens.subText)

            Text("No Matching Books")
                .font(LibraryCardTokens.serifTitleFont(size: 22))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Text("Try a different title, author, place, year, or topic.")
                .foregroundStyle(LibraryCardTokens.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Catalog lifecycle

    @MainActor
    private func bootstrapCatalog(forceRefresh: Bool = false) async {
        errorMessage = nil

        let alreadyInstalled = await service.databaseExists()

        if alreadyInstalled {
            catalogReady = true
            isPreparingCatalog = false
            await reloadBooks()
            await refreshBookCount()

            // Check for a newer catalog after cached results are already on
            // screen. Awaiting here still leaves the UI responsive, and keeps
            // the work attached to SwiftUI's cancellable .task lifecycle.
            await checkForCatalogUpdate(force: forceRefresh)
            return
        }

        isPreparingCatalog = true

        do {
            try await service.installCatalogIfMissing()
            catalogReady = true
            isPreparingCatalog = false
            await reloadBooks()
            await refreshBookCount()
        } catch {
            isPreparingCatalog = false
            catalogReady = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func checkForCatalogUpdate(force: Bool) async {
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }

        do {
            let updated = try await service.refreshCatalog(force: force)
            if updated {
                await reloadBooks()
                await refreshBookCount()
            }
        } catch {
            // A network/version-check failure must not hide a working cached
            // catalog. Surface it only when there is no usable data.
            if books.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func refreshCatalog() async {
        guard catalogReady else {
            await bootstrapCatalog(forceRefresh: true)
            return
        }
        await checkForCatalogUpdate(force: true)
    }

    @MainActor
    private func refreshBookCount() async {
        do {
            bookCount = try await service.countBooks()
        } catch {
            bookCount = nil
        }
    }

    @MainActor
    private func reloadBooks() async {
        guard catalogReady else { return }

        isLoadingPage = true
        errorMessage = nil
        defer { isLoadingPage = false }

        do {
            let firstPage = try await service.books(
                matching: searchQuery,
                limit: pageSize,
                offset: 0
            )
            books = firstPage
            hasMore = firstPage.count == pageSize
        } catch {
            books = []
            hasMore = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard catalogReady, hasMore, !isLoadingPage else { return }

        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let next = try await service.books(
                matching: searchQuery,
                limit: pageSize,
                offset: books.count
            )
            books.append(contentsOf: next)
            hasMore = next.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Open / save

    @MainActor
    private func open(_ book: HebrewBooksCatalogBook) async {
        await acquire(book, openAfterImport: true)
    }

    @MainActor
    private func saveWithoutOpening(_ book: HebrewBooksCatalogBook) async {
        await acquire(book, openAfterImport: false)
    }

    @MainActor
    private func acquire(
        _ catalogBook: HebrewBooksCatalogBook,
        openAfterImport: Bool
    ) async {
        guard let bookImporter, let persistenceActor else {
            errorMessage = "The book importer is unavailable."
            return
        }

        openingBookID = catalogBook.id
        defer { openingBookID = nil }

        var downloadedURL: URL?

        do {
            let url = try await service.downloadPDF(bookID: catalogBook.id)
            downloadedURL = url

            let result = try await bookImporter.importFile(
                at: url,
                source: .localCopy,
                titleOverride: catalogBook.title
            )

            let libraryBooks = try await persistenceActor.fetchAllLibraryBooks()
            guard let book = libraryBooks.first(where: {
                $0.fingerprintKey == result.fingerprintKey
            }) else {
                throw HebrewBooksOpenError.importedBookNotFound
            }

            if openAfterImport {
                let isTransient = !result.isDuplicate

                if isTransient {
                    CatalogTransientStore.mark(book.fingerprintKey)
                }

                openedRoute = HebrewBooksOpenRoute(
                    book: book,
                    isTransient: isTransient
                )
            } else {
                CatalogTransientStore.unmark(book.fingerprintKey)
                NotificationCenter.default.post(
                    name: .bookDidImport,
                    object: nil,
                    userInfo: ["fingerprintKey": book.fingerprintKey]
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if let downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
    }
}

// MARK: - Exact Library-card presentation

private struct HebrewBooksBookCard: View {
    let book: HebrewBooksCatalogBook
    let isOpening: Bool

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: LibraryCardTokens.cardStackSpacing
        ) {
            HebrewBooksGeneratedCover(
                book: book,
                cornerRadius: LibraryCardTokens.cardCoverCornerRadius
            )
            .overlay {
                if isOpening {
                    ZStack {
                        Color.black.opacity(0.16)
                        ProgressView()
                            .tint(.white)
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: LibraryCardTokens.cardCoverCornerRadius
                        )
                    )
                }
            }

            Text(book.title)
                .font(
                    LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.cardTitleFontSize
                    )
                )
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(LibraryCardTokens.ink)

            if let author = book.author {
                Text(author)
                    .font(
                        .system(
                            size: LibraryCardTokens.cardAuthorFontSize
                        )
                    )
                    .foregroundStyle(LibraryCardTokens.subText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HebrewBooksBookRow: View {
    let book: HebrewBooksCatalogBook
    let isOpening: Bool

    var body: some View {
        HStack(spacing: LibraryCardTokens.rowContentSpacing) {
            HebrewBooksGeneratedCover(
                book: book,
                cornerRadius: LibraryCardTokens.rowCoverCornerRadius
            )
            .frame(
                width: LibraryCardTokens.rowCoverWidth,
                height: LibraryCardTokens.rowCoverHeight
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(
                        LibraryCardTokens.serifTitleFont(
                            size: LibraryCardTokens.rowTitleFontSize
                        )
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(LibraryCardTokens.ink)
                    .lineLimit(1)

                if let author = book.author {
                    Text(author)
                        .font(
                            .system(
                                size: LibraryCardTokens.rowAuthorFontSize
                            )
                        )
                        .foregroundStyle(LibraryCardTokens.subText)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("PDF")
                        .font(
                            .system(
                                size: LibraryCardTokens.rowChipFontSize,
                                weight: .semibold
                            )
                        )
                        .tracking(0.5)
                        .foregroundStyle(LibraryCardTokens.subText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(LibraryCardTokens.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let detail = book.metadataLine {
                        Text(detail)
                            .font(
                                .system(
                                    size: LibraryCardTokens.rowAuthorFontSize
                                )
                            )
                            .foregroundStyle(LibraryCardTokens.subText)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            if isOpening {
                ProgressView()
                    .tint(LibraryCardTokens.accent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LibraryCardTokens.subText)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct HebrewBooksGeneratedCover: View {
    let book: HebrewBooksCatalogBook
    let cornerRadius: CGFloat

    var body: some View {
        Color(white: 0.92)
            .aspectRatio(
                LibraryCardTokens.coverAspectRatio,
                contentMode: .fit
            )
            .overlay {
                GenerativeCoverView(
                    title: book.title,
                    author: book.author,
                    style: GenerativeCoverStyle.style(
                        forFingerprintKey: book.stableCoverKey
                    ),
                    palette: GenerativeCoverPalette.palette(
                        forFingerprintKey: book.stableCoverKey
                    )
                )
            }
            .overlay { spineShadow }
            .overlay { pageEdge }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LibraryCardTokens.coverBorder,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: 3,
                y: 2
            )
    }

    private var spineShadow: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.25), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 6)

            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var pageEdge: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            LinearGradient(
                colors: [
                    .black.opacity(0.12),
                    .white.opacity(0.18),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 2)
        }
        .allowsHitTesting(false)
    }
}

private enum HebrewBooksOpenError: LocalizedError {
    case importedBookNotFound

    var errorDescription: String? {
        switch self {
        case .importedBookNotFound:
            return "The book downloaded successfully but could not be opened."
        }
    }
}
