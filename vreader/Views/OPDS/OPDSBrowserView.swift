// Purpose: SwiftUI view for browsing OPDS catalog feeds.
// Supports navigation feeds (category browsing), acquisition feeds (book listings),
// search, pagination, and book download.
//
// Key decisions:
// - Uses NavigationStack for drill-down into subcategories.
// - Async loading with ProgressView during fetch.
// - Error state with retry button.
// - Download triggers import through BookImporter.
//
// @coordinates-with: OPDSClient.swift, OPDSModels.swift, OPDSEntryView.swift,
//   BookImporter.swift

import SwiftUI

/// Browsable OPDS catalog feed view.
struct OPDSBrowserView: View {
    let catalogURL: URL
    let catalogName: String
    let credentials: OPDSCredentials?

    @State private var feed: OPDSFeed?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let client = OPDSClient()

    init(
        catalogURL: URL,
        catalogName: String,
        credentials: OPDSCredentials? = nil
    ) {
        self.catalogURL = catalogURL
        self.catalogName = catalogName
        self.credentials = credentials
    }

    var body: some View {
        Group {
            if isLoading && feed == nil {
                ProgressView("Loading catalog...")
                    .accessibilityIdentifier("opdsCatalogLoading")
            } else if let error = errorMessage {
                errorState(error)
            } else if let feed = feed {
                feedContent(feed)
            }
        }
        .navigationTitle(feed?.title ?? catalogName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFeed(url: catalogURL)
        }
    }

    // MARK: - Feed Content

    @ViewBuilder
    private func feedContent(_ feed: OPDSFeed) -> some View {
        List {
            ForEach(Array(feed.entries.enumerated()), id: \.element.id) { _, entry in
                if feed.kind == .navigation {
                    navigationRow(entry: entry, feed: feed)
                } else {
                    acquisitionRow(entry: entry, feed: feed)
                }
            }

            if feed.nextPageURL != nil {
                loadMoreRow(feed: feed)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("opdsFeedList")
    }

    private func navigationRow(entry: OPDSEntry, feed: OPDSFeed) -> some View {
        Group {
            if let navURL = entry.navigationURL(against: feed.baseURL) {
                NavigationLink {
                    OPDSBrowserView(
                        catalogURL: navURL,
                        catalogName: entry.title,
                        credentials: credentials
                    )
                } label: {
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
                .accessibilityIdentifier("opdsNavEntry_\(entry.id)")
            } else {
                Text(entry.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func acquisitionRow(entry: OPDSEntry, feed: OPDSFeed) -> some View {
        NavigationLink {
            OPDSEntryView(
                entry: entry,
                baseURL: feed.baseURL,
                credentials: credentials
            )
        } label: {
            HStack(spacing: 12) {
                // Cover thumbnail
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
                        .lineLimit(2)
                    if let author = entry.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.acquisitionLinks.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(
                                Array(entry.acquisitionLinks.enumerated()),
                                id: \.offset
                            ) { _, link in
                                if let label = link.formatLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.fill.tertiary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("opdsAcqEntry_\(entry.id)")
    }

    private func loadMoreRow(feed: OPDSFeed) -> some View {
        Button {
            if let nextURL = feed.nextPageURL {
                Task { await loadFeed(url: nextURL, append: true) }
            }
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
        .accessibilityIdentifier("opdsLoadMore")
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Failed to Load Catalog")
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                Task { await loadFeed(url: catalogURL) }
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("opdsErrorState")
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
                // Merge entries for pagination
                let merged = existing.entries + loaded.entries
                let deduped = OPDSFeed.deduplicated(merged)
                feed = OPDSFeed(
                    title: existing.title,
                    id: existing.id,
                    links: loaded.links,
                    entries: deduped,
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
}
