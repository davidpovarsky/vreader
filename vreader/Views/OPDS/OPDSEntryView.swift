// Purpose: Detail view for a single OPDS entry (book).
// Shows cover, metadata, and download buttons for each available format.
//
// Key decisions:
// - Download buttons for each acquisition link.
// - Shows format label (EPUB, PDF) on each button.
// - Downloads via OPDSClient, imports via BookImporter notification.
// - Progress indicator during download.
//
// @coordinates-with: OPDSModels.swift, OPDSClient.swift, BookImporter.swift

import SwiftUI

/// Detail view for a single OPDS catalog entry.
struct OPDSEntryView: View {
    let entry: OPDSEntry
    let baseURL: URL?
    let credentials: OPDSCredentials?

    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var downloadSuccess = false

    private let client = OPDSClient()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if let coverURL = entry.coverURL(against: baseURL) {
                    HStack {
                        Spacer()
                        AsyncImage(url: coverURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                                .aspectRatio(0.67, contentMode: .fit)
                        }
                        .frame(maxWidth: 200, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                        Spacer()
                    }
                }

                // Title and author
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let author = entry.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Summary
                if let summary = entry.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Download buttons
                VStack(spacing: 12) {
                    ForEach(
                        Array(entry.acquisitionLinks.enumerated()),
                        id: \.offset
                    ) { _, link in
                        downloadButton(for: link)
                    }
                }

                if let error = downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }

                if downloadSuccess {
                    Label("Downloaded! Book added to library.", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                        .accessibilityIdentifier("opdsDownloadSuccess")
                }
            }
            .padding()
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("opdsEntryDetail")
    }

    // MARK: - Download

    private func downloadButton(for link: OPDSLink) -> some View {
        Button {
            Task { await download(link: link) }
        } label: {
            HStack {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text("Download \(link.formatLabel ?? "Book")")
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDownloading)
        .accessibilityIdentifier("opdsDownload_\(link.formatLabel ?? "unknown")")
    }

    private func download(link: OPDSLink) async {
        guard let downloadURL = link.resolvedHref(against: baseURL) else {
            downloadError = "Invalid download URL."
            return
        }

        isDownloading = true
        downloadError = nil
        downloadSuccess = false

        do {
            let tempURL = try await client.downloadBook(
                url: downloadURL,
                credentials: credentials
            )

            // Determine file extension from MIME type or URL
            let ext = fileExtension(for: link)
            let namedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(entry.title).\(ext)")

            // Move to named temp file for BookImporter
            try? FileManager.default.removeItem(at: namedURL)
            try FileManager.default.moveItem(at: tempURL, to: namedURL)

            // Notify for import (the library view handles the actual import)
            NotificationCenter.default.post(
                name: .opdsBookDownloaded,
                object: nil,
                userInfo: ["url": namedURL, "title": entry.title]
            )

            downloadSuccess = true
        } catch {
            downloadError = error.localizedDescription
        }

        isDownloading = false
    }

    private func fileExtension(for link: OPDSLink) -> String {
        if let type = link.type {
            if type.contains("epub") { return "epub" }
            if type.contains("pdf") { return "pdf" }
        }
        // Fall back to URL extension
        let pathExt = URL(string: link.href)?.pathExtension
        return pathExt?.isEmpty == false ? pathExt! : "epub"
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when a book is downloaded from an OPDS catalog.
    /// userInfo: ["url": URL, "title": String]
    static let opdsBookDownloaded = Notification.Name("opdsBookDownloaded")
}
