// Purpose: Search UI for BookSource — allows users to search for books
// using a configured BookSource and view results.
//
// Key decisions:
// - Uses BookSourcePipeline for search operations.
// - Displays results in a list with book name, author, and cover.
// - Navigation to BookSourceChapterListView on book selection.
//
// @coordinates-with: BookSourcePipeline.swift, BookSourceChapterListView.swift

import SwiftUI

/// Search view for discovering books from a BookSource.
struct BookSourceSearchView: View {
    let source: BookSourceSnapshot

    @State private var keyword = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var currentStage: PipelineStage?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if isSearching {
                ProgressView("Searching...")
                    .padding()
                Spacer()
            } else if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else if results.isEmpty && !keyword.isEmpty {
                Text("No results found")
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
    }

    private var searchBar: some View {
        HStack {
            TextField("Search books...", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { performSearch() }
            Button("Search") { performSearch() }
                .disabled(keyword.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || isSearching)
        }
        .padding()
    }

    private var resultsList: some View {
        List(results.indices, id: \.self) { index in
            let result = results[index]
            NavigationLink {
                if let bookUrl = result.bookUrl {
                    BookSourceChapterListView(
                        source: source,
                        bookUrl: bookUrl,
                        bookName: result.name ?? "Unknown"
                    )
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name ?? "Unknown Title")
                        .font(.headline)
                    if let author = result.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func performSearch() {
        let trimmed = keyword.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        results = []

        Task {
            do {
                let httpClient = BookSourceHTTPClient()
                let pipeline = BookSourcePipeline(
                    fetchHTML: { url, headers in
                        try await httpClient.fetchPage(
                            url: url, headers: headers
                        )
                    }
                )
                let searchResults = try await pipeline.search(
                    source: source,
                    keyword: trimmed
                ) { stage in
                    Task { @MainActor in currentStage = stage }
                }
                await MainActor.run {
                    results = searchResults
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
}
