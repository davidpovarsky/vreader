// Purpose: Simple text reader for BookSource chapter content.
// Displays extracted chapter text in a scrollable view.
//
// Key decisions:
// - Minimal reader — plain text display with proper typography.
// - Handles loading, error, and content states.
// - No complex pagination or formatting (MVP).
//
// @coordinates-with: BookSourcePipeline.swift

import SwiftUI

/// Simple chapter reader view for BookSource content.
struct BookSourceReaderView: View {
    let source: BookSourceSnapshot
    let chapterUrl: String
    let chapterName: String

    @State private var content: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chapter...")
            } else if let error = errorMessage {
                VStack {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { loadContent() }
                }
            } else if let text = content {
                ScrollView {
                    Text(text)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(chapterName)
        .task { loadContent() }
    }

    private func loadContent() {
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

                let text = try await pipeline.chapterContent(
                    source: source, chapterUrl: chapterUrl
                )

                await MainActor.run {
                    content = text
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
