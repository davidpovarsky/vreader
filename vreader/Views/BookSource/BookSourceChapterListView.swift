// Purpose: Chapter list UI for BookSource — shows the table of contents
// for a selected book with navigation to individual chapters.
//
// Key decisions:
// - Fetches book info first, then uses tocUrl to load chapters.
// - Handles pagination via pipeline's nextTocUrl support.
// - Navigation to BookSourceReaderView on chapter selection.
//
// @coordinates-with: BookSourcePipeline.swift, BookSourceReaderView.swift

import SwiftUI

/// Chapter list view for a book from a BookSource.
struct BookSourceChapterListView: View {
    let source: BookSourceSnapshot
    let bookUrl: String
    let bookName: String

    @State private var bookDetail: BookDetail?
    @State private var chapters: [ChapterInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chapters...")
            } else if let error = errorMessage {
                VStack {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadChapters() }
                }
            } else {
                List(chapters.indices, id: \.self) { index in
                    let chapter = chapters[index]
                    NavigationLink {
                        BookSourceReaderView(
                            source: source,
                            chapterUrl: chapter.url,
                            chapterName: chapter.name
                        )
                    } label: {
                        Text(chapter.name)
                    }
                }
            }
        }
        .navigationTitle(bookName)
        .task { loadChapters() }
    }

    private func loadChapters() {
        isLoading = true
        errorMessage = nil

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

                // Get book info to find the TOC URL
                let detail = try await pipeline.bookInfo(
                    source: source, bookUrl: bookUrl
                )

                let tocUrl = detail.tocUrl ?? bookUrl
                let chapterList = try await pipeline.chapters(
                    source: source, tocUrl: tocUrl
                )

                await MainActor.run {
                    bookDetail = detail
                    chapters = chapterList
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
