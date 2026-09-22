// Purpose: OPDS browsing inside the Library visual system.
//
// This feature reuses the original Library shell instead of inventing a second
// interface: warm-paper background, Source Serif titles, the same 3-column grid,
// the same list-card proportions, the same spacing/tokens, and the same accent.
// Tapping a book downloads and opens it immediately. EPUB is preferred when an
// entry exposes both EPUB and PDF.

import SwiftUI

private struct CatalogOpenRoute: Identifiable {
    let book: LibraryBookItem
    let isTransient: Bool

    var id: String { book.fingerprintKey }
}

private struct CatalogLocation {
    let url: URL
    let name: String
}

struct HomeCatalogBrowserView: View {
    let catalogURL: URL
    let catalogName: String
    let credentials: OPDSCredentials?
    let viewMode: LibraryViewMode
    let searchQuery: String

    @Environment(\.bookImporter) private var bookImporter
    @Environment(\.persistenceActor) private var persistenceActor

    @State private var feed: OPDSFeed?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openingEntryID: String?
    @State private var openedRoute: CatalogOpenRoute?
    @State private var hasStartedInitialLoad = false
    @State private var currentURL: URL
    @State private var currentName: String
    @State private var history: [CatalogLocation] = []

    private let client = OPDSClient()

    init(
        catalogURL: URL,
        catalogName: String,
        credentials: OPDSCredentials?,
        viewMode: LibraryViewMode,
        searchQuery: String
    ) {
        self.catalogURL = catalogURL
        self.catalogName = catalogName
        self.credentials = credentials
        self.viewMode = viewMode
        self.searchQuery = searchQuery
        _currentURL = State(initialValue: catalogURL)
        _currentName = State(initialValue: catalogName)
    }

    var body: some View {
        ZStack {
            LibraryCardTokens.shellBackground
                .ignoresSafeArea()

            Group {
                if isLoading && feed == nil {
                    loadingState
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if let feed {
                    feedContent(feed)
                }
            }
        }
        .onAppear {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            Task { await loadFeed(url: currentURL) }
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

    // MARK: - Feed content

    @ViewBuilder
    private func feedContent(_ feed: OPDSFeed) -> some View {
        let entries = filteredEntries(feed.entries)

        if entries.isEmpty && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptySearchState
        } else if feed.kind == .navigation {
            navigationFeed(entries: entries, feed: feed)
        } else {
            acquisitionFeed(entries: entries, feed: feed)
        }
    }

    private func navigationFeed(
        entries: [OPDSEntry],
        feed: OPDSFeed
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pathHeaderIfNeeded
                sectionTitle("Browse")

                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if let navURL = entry.navigationURL(against: feed.baseURL) {
                            Button {
                                navigate(to: navURL, title: entry.title)
                            } label: {
                                catalogNavigationRow(entry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            catalogNavigationRow(entry)
                                .opacity(0.55)
                        }

                        if index < entries.count - 1 {
                            Divider()
                                .overlay(LibraryCardTokens.listRowDivider)
                                .padding(.leading, LibraryCardTokens.rowCoverWidth + 12)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(LibraryCardTokens.listCardBackground)
                .clipShape(RoundedRectangle(
                    cornerRadius: LibraryCardTokens.listCardCornerRadius,
                    style: .continuous
                ))

                loadMoreIfNeeded(feed)
            }
            .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
            .padding(.bottom, 24)
        }
        .refreshable {
            await loadFeed(url: currentURL)
        }
    }

    @ViewBuilder
    private func acquisitionFeed(
        entries: [OPDSEntry],
        feed: OPDSFeed
    ) -> some View {
        switch viewMode {
        case .grid:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pathHeaderIfNeeded
                    sectionTitle("Books")

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 14),
                            count: 3
                        ),
                        spacing: 22
                    ) {
                        ForEach(entries, id: \.id) { entry in
                            catalogGridButton(entry: entry, feed: feed)
                        }
                    }

                    loadMoreIfNeeded(feed)
                }
                .padding(.horizontal, LibraryCardTokens.shellContentPadding)
                .padding(.bottom, 24)
            }
            .refreshable {
                await loadFeed(url: currentURL)
            }

        case .list:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pathHeaderIfNeeded
                    sectionTitle("Books")

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            catalogListButton(entry: entry, feed: feed)

                            if index < entries.count - 1 {
                                Divider()
                                    .overlay(LibraryCardTokens.listRowDivider)
                                    .padding(.leading, LibraryCardTokens.rowCoverWidth + 12)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(LibraryCardTokens.listCardBackground)
                    .clipShape(RoundedRectangle(
                        cornerRadius: LibraryCardTokens.listCardCornerRadius,
                        style: .continuous
                    ))

                    loadMoreIfNeeded(feed)
                }
                .padding(.horizontal, LibraryCardTokens.shellEdgePadding)
                .padding(.bottom, 24)
            }
            .refreshable {
                await loadFeed(url: currentURL)
            }
        }
    }

    private func catalogGridButton(
        entry: OPDSEntry,
        feed: OPDSFeed
    ) -> some View {
        Button {
            guard openingEntryID == nil else { return }
            Task { await open(entry: entry, baseURL: feed.baseURL) }
        } label: {
            CatalogBookCard(
                entry: entry,
                baseURL: feed.baseURL,
                isOpening: openingEntryID == entry.id
            )
        }
        .buttonStyle(.plain)
        .disabled(openingEntryID != nil)
        .contextMenu {
            Button {
                Task { await saveWithoutOpening(entry: entry, baseURL: feed.baseURL) }
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }
        }
        .accessibilityLabel("Open \(entry.title)")
    }

    private func catalogListButton(
        entry: OPDSEntry,
        feed: OPDSFeed
    ) -> some View {
        Button {
            guard openingEntryID == nil else { return }
            Task { await open(entry: entry, baseURL: feed.baseURL) }
        } label: {
            CatalogBookRow(
                entry: entry,
                baseURL: feed.baseURL,
                isOpening: openingEntryID == entry.id
            )
        }
        .buttonStyle(.plain)
        .disabled(openingEntryID != nil)
        .contextMenu {
            Button {
                Task { await saveWithoutOpening(entry: entry, baseURL: feed.baseURL) }
            } label: {
                Label("Save to Library", systemImage: "square.and.arrow.down")
            }
        }
        .accessibilityLabel("Open \(entry.title)")
    }

    // MARK: - Shared Library-language chrome

    @ViewBuilder
    private var pathHeaderIfNeeded: some View {
        if !history.isEmpty {
            HStack(spacing: 10) {
                LibraryPillButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Back",
                    accessibilityIdentifier: "catalogBackButton",
                    action: goBack
                )

                Text(currentName)
                    .font(LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.sectionHeaderFontSize
                    ))
                    .fontWeight(.semibold)
                    .foregroundStyle(LibraryCardTokens.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(LibraryCardTokens.serifTitleFont(
                size: LibraryCardTokens.sectionHeaderFontSize
            ))
            .fontWeight(.semibold)
            .foregroundStyle(LibraryCardTokens.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func catalogNavigationRow(_ entry: OPDSEntry) -> some View {
        HStack(spacing: LibraryCardTokens.rowContentSpacing) {
            Image(systemName: "books.vertical")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LibraryCardTokens.navIconTint)
                .frame(
                    width: LibraryCardTokens.rowCoverWidth,
                    height: LibraryCardTokens.rowCoverHeight
                )
                .background(
                    RoundedRectangle(cornerRadius: LibraryCardTokens.rowCoverCornerRadius)
                        .fill(LibraryCardTokens.navPillBackground)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.rowTitleFontSize
                    ))
                    .fontWeight(.semibold)
                    .foregroundStyle(LibraryCardTokens.ink)
                    .lineLimit(2)

                if let summary = entry.summary {
                    Text(summary)
                        .font(.system(size: LibraryCardTokens.rowAuthorFontSize))
                        .foregroundStyle(LibraryCardTokens.subText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LibraryCardTokens.subText)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func loadMoreIfNeeded(_ feed: OPDSFeed) -> some View {
        if let nextURL = feed.nextPageURL {
            Button {
                Task { await loadFeed(url: nextURL, append: true) }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isLoading ? "Loading…" : "Load More")
                        .font(.system(size: LibraryCardTokens.subtitleFontSize, weight: .medium))
                }
                .foregroundStyle(LibraryCardTokens.seeAllAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(LibraryCardTokens.accent)

            Text("Loading catalog…")
                .font(.system(size: LibraryCardTokens.subtitleFontSize))
                .foregroundStyle(LibraryCardTokens.subText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(LibraryCardTokens.subText)

            Text("Catalog Error")
                .font(LibraryCardTokens.serifTitleFont(size: 22))
                .fontWeight(.semibold)
                .foregroundStyle(LibraryCardTokens.ink)

            Text(message)
                .font(.body)
                .foregroundStyle(LibraryCardTokens.subText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task { await loadFeed(url: currentURL) }
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

            Text("Try a different title or author.")
                .foregroundStyle(LibraryCardTokens.subText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func navigate(to url: URL, title: String) {
        history.append(CatalogLocation(url: currentURL, name: currentName))
        currentURL = url
        currentName = title
        feed = nil
        errorMessage = nil
        Task { await loadFeed(url: url) }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        currentURL = previous.url
        currentName = previous.name
        feed = nil
        errorMessage = nil
        Task { await loadFeed(url: previous.url) }
    }

    // MARK: - Loading

    private func loadFeed(url: URL, append: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await client.fetchFeed(
                url: url,
                credentials: credentials
            )

            if append, let existing = feed {
                let merged = OPDSFeed.deduplicated(existing.entries + loaded.entries)
                feed = OPDSFeed(
                    title: existing.title,
                    id: existing.id,
                    links: loaded.links,
                    entries: merged,
                    baseURL: loaded.baseURL
                )
            } else {
                feed = loaded
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func filteredEntries(_ entries: [OPDSEntry]) -> [OPDSEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query)
                || (entry.author?.localizedCaseInsensitiveContains(query) == true)
                || (entry.summary?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    // MARK: - Open / save

    private func open(entry: OPDSEntry, baseURL: URL?) async {
        await acquire(entry: entry, baseURL: baseURL, openAfterImport: true)
    }

    private func saveWithoutOpening(entry: OPDSEntry, baseURL: URL?) async {
        await acquire(entry: entry, baseURL: baseURL, openAfterImport: false)
    }

    private func acquire(
        entry: OPDSEntry,
        baseURL: URL?,
        openAfterImport: Bool
    ) async {
        guard let link = Self.preferredAcquisitionLink(for: entry) else {
            errorMessage = "This entry has no supported EPUB or PDF download."
            return
        }
        guard let downloadURL = link.resolvedHref(against: baseURL) else {
            errorMessage = "The catalog returned an invalid download URL."
            return
        }
        guard let bookImporter, let persistenceActor else {
            errorMessage = "The book importer is unavailable."
            return
        }

        openingEntryID = entry.id
        defer { openingEntryID = nil }

        var namedTempURL: URL?

        do {
            let downloadedURL = try await client.downloadBook(
                url: downloadURL,
                credentials: credentials
            )

            let ext = Self.fileExtension(for: link)
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("vreader-catalog-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            namedTempURL = target

            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: downloadedURL, to: target)

            let result = try await bookImporter.importFile(
                at: target,
                source: .localCopy,
                titleOverride: entry.title
            )

            let books = try await persistenceActor.fetchAllLibraryBooks()
            guard let book = books.first(where: { $0.fingerprintKey == result.fingerprintKey }) else {
                throw CatalogOpenError.importedBookNotFound
            }

            if openAfterImport {
                let isTransient = !result.isDuplicate
                if isTransient {
                    CatalogTransientStore.mark(book.fingerprintKey)
                }
                openedRoute = CatalogOpenRoute(
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

        if let namedTempURL {
            try? FileManager.default.removeItem(at: namedTempURL)
        }
    }

    /// EPUB wins when a catalog happens to advertise more than one supported
    /// acquisition. Most catalogs are single-format, so this is usually a no-op.
    static func preferredAcquisitionLink(for entry: OPDSEntry) -> OPDSLink? {
        let links = entry.acquisitionLinks

        if let epub = links.first(where: { link in
            link.type?.localizedCaseInsensitiveContains("epub") == true
                || URL(string: link.href)?.pathExtension.lowercased() == "epub"
        }) {
            return epub
        }

        if let pdf = links.first(where: { link in
            link.type?.localizedCaseInsensitiveContains("pdf") == true
                || URL(string: link.href)?.pathExtension.lowercased() == "pdf"
        }) {
            return pdf
        }

        return links.first
    }

    static func fileExtension(for link: OPDSLink) -> String {
        if let type = link.type {
            if type.localizedCaseInsensitiveContains("epub") { return "epub" }
            if type.localizedCaseInsensitiveContains("pdf") { return "pdf" }
            if type.localizedCaseInsensitiveContains("mobi") { return "mobi" }
        }

        let ext = URL(string: link.href)?.pathExtension.lowercased() ?? ""
        return ext.isEmpty ? "epub" : ext
    }
}

// MARK: - Catalog presentation components

private struct CatalogBookCard: View {
    let entry: OPDSEntry
    let baseURL: URL?
    let isOpening: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryCardTokens.cardStackSpacing) {
            CatalogRemoteCover(
                entry: entry,
                baseURL: baseURL,
                cornerRadius: LibraryCardTokens.cardCoverCornerRadius
            )
            .overlay {
                if isOpening {
                    ZStack {
                        Color.black.opacity(0.16)
                        ProgressView()
                            .tint(.white)
                    }
                    .clipShape(RoundedRectangle(
                        cornerRadius: LibraryCardTokens.cardCoverCornerRadius
                    ))
                }
            }

            Text(entry.title)
                .font(LibraryCardTokens.serifTitleFont(
                    size: LibraryCardTokens.cardTitleFontSize
                ))
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(LibraryCardTokens.ink)

            if let author = entry.author {
                Text(author)
                    .font(.system(size: LibraryCardTokens.cardAuthorFontSize))
                    .foregroundStyle(LibraryCardTokens.subText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CatalogBookRow: View {
    let entry: OPDSEntry
    let baseURL: URL?
    let isOpening: Bool

    var body: some View {
        HStack(spacing: LibraryCardTokens.rowContentSpacing) {
            CatalogRemoteCover(
                entry: entry,
                baseURL: baseURL,
                cornerRadius: LibraryCardTokens.rowCoverCornerRadius
            )
            .frame(
                width: LibraryCardTokens.rowCoverWidth,
                height: LibraryCardTokens.rowCoverHeight
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(LibraryCardTokens.serifTitleFont(
                        size: LibraryCardTokens.rowTitleFontSize
                    ))
                    .fontWeight(.semibold)
                    .foregroundStyle(LibraryCardTokens.ink)
                    .lineLimit(1)

                if let author = entry.author {
                    Text(author)
                        .font(.system(size: LibraryCardTokens.rowAuthorFontSize))
                        .foregroundStyle(LibraryCardTokens.subText)
                        .lineLimit(1)
                }

                if let link = HomeCatalogBrowserView.preferredAcquisitionLink(for: entry),
                   let format = link.formatLabel {
                    Text(format)
                        .font(.system(size: LibraryCardTokens.rowChipFontSize))
                        .fontWeight(.semibold)
                        .tracking(0.5)
                        .foregroundStyle(LibraryCardTokens.subText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(LibraryCardTokens.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 3)
                }
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

private struct CatalogRemoteCover: View {
    let entry: OPDSEntry
    let baseURL: URL?
    let cornerRadius: CGFloat

    var body: some View {
        Color(white: 0.92)
            .aspectRatio(LibraryCardTokens.coverAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let coverURL = entry.coverURL(against: baseURL) {
                        AsyncImage(url: coverURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            default:
                                generativeCover
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                    } else {
                        generativeCover
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .overlay { spineShadow }
            .overlay { pageEdge }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LibraryCardTokens.coverBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }

    private var generativeCover: some View {
        GenerativeCoverView(
            title: entry.title,
            author: entry.author,
            style: GenerativeCoverStyle.style(forFingerprintKey: entry.id),
            palette: GenerativeCoverPalette.palette(forFingerprintKey: entry.id)
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
                colors: [.black.opacity(0.12), .white.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 2)
        }
        .allowsHitTesting(false)
    }
}

private enum CatalogOpenError: LocalizedError {
    case importedBookNotFound

    var errorDescription: String? {
        switch self {
        case .importedBookNotFound:
            return "The book downloaded successfully but could not be opened."
        }
    }
}
