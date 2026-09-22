// Purpose: First-class OPDS browsing for the home-source layer.
//
// Unlike the upstream OPDS detail flow, tapping a book here immediately
// downloads the preferred acquisition, imports it through the existing importer
// and opens the existing ReaderContainerView. EPUB is preferred whenever it is
// available; PDF is the fallback. The imported record is marked transient until
// the user explicitly chooses "Save to Library" in CatalogTransientReaderView.

import SwiftUI

private struct CatalogOpenRoute: Identifiable {
    let book: LibraryBookItem
    let isTransient: Bool

    var id: String { book.fingerprintKey }
}

struct HomeCatalogBrowserView: View {
    let catalogURL: URL
    let catalogName: String
    let credentials: OPDSCredentials?

    @Environment(\.bookImporter) private var bookImporter
    @Environment(\.persistenceActor) private var persistenceActor

    @State private var feed: OPDSFeed?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openingEntryID: String?
    @State private var openedRoute: CatalogOpenRoute?
    @State private var hasStartedInitialLoad = false

    private let client = OPDSClient()

    var body: some View {
        Group {
            if isLoading && feed == nil {
                ProgressView("Loading catalog…")
            } else if let errorMessage {
                errorState(errorMessage)
            } else if let feed {
                feedContent(feed)
            }
        }
        .navigationTitle(feed?.title ?? catalogName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasStartedInitialLoad else { return }
            hasStartedInitialLoad = true
            Task { await loadFeed(url: catalogURL) }
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

    @ViewBuilder
    private func feedContent(_ feed: OPDSFeed) -> some View {
        List {
            ForEach(feed.entries, id: \.id) { entry in
                if !entry.acquisitionLinks.isEmpty {
                    acquisitionRow(entry: entry, feed: feed)
                } else if let navURL = entry.navigationURL(against: feed.baseURL) {
                    NavigationLink {
                        HomeCatalogBrowserView(
                            catalogURL: navURL,
                            catalogName: entry.title,
                            credentials: credentials
                        )
                    } label: {
                        navigationLabel(entry)
                    }
                } else {
                    navigationLabel(entry)
                        .foregroundStyle(.secondary)
                }
            }

            if let nextURL = feed.nextPageURL {
                Button {
                    Task { await loadFeed(url: nextURL, append: true) }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Load More")
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadFeed(url: catalogURL)
        }
    }

    private func navigationLabel(_ entry: OPDSEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.body)
            if let summary = entry.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func acquisitionRow(entry: OPDSEntry, feed: OPDSFeed) -> some View {
        Button {
            guard openingEntryID == nil else { return }
            Task {
                await open(entry: entry, baseURL: feed.baseURL)
            }
        } label: {
            HStack(spacing: 12) {
                if let coverURL = entry.coverURL(against: feed.baseURL) {
                    AsyncImage(url: coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                    }
                    .frame(width: 48, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let author = entry.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let preferred = Self.preferredAcquisitionLink(for: entry),
                       let label = preferred.formatLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if openingEntryID == entry.id {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openingEntryID != nil)
        .accessibilityLabel("Open \(entry.title)")
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Catalog Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadFeed(url: catalogURL) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

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

    private func open(entry: OPDSEntry, baseURL: URL?) async {
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

            let isTransient = !result.isDuplicate
            if isTransient {
                CatalogTransientStore.mark(book.fingerprintKey)
            }

            openedRoute = CatalogOpenRoute(
                book: book,
                isTransient: isTransient
            )
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

private enum CatalogOpenError: LocalizedError {
    case importedBookNotFound

    var errorDescription: String? {
        switch self {
        case .importedBookNotFound:
            return "The book downloaded successfully but could not be opened."
        }
    }
}
