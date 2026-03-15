// Purpose: Share sheet wrapper for sharing book files via UIActivityViewController.
// Presented from the library context menu "Share" action.
//
// Key decisions:
// - Uses UIViewControllerRepresentable to wrap UIActivityViewController.
// - Shares the book's sandbox file URL so recipients get the actual file.
// - Static `activityItems(for:)` method exposed for testability.
//
// @coordinates-with: LibraryView.swift, LibraryBookItem.swift

import SwiftUI

/// Share sheet for sharing a book file.
struct ShareSheet: View {
    let book: LibraryBookItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShareActivityView(activityItems: Self.activityItems(for: book))
            .ignoresSafeArea()
    }

    /// Returns the activity items for sharing. Exposed as a static method for testability.
    nonisolated static func activityItems(for book: LibraryBookItem) -> [Any] {
        [book.resolvedFileURL]
    }
}

/// UIViewControllerRepresentable wrapper for UIActivityViewController.
struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
