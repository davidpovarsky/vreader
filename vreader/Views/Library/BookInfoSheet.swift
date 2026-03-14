// Purpose: Sheet view displaying detailed book metadata.
// Presented from the library context menu "Info" action.
//
// Key decisions:
// - Uses Form for consistent iOS settings-style layout.
// - ViewModel is a simple struct for testability (no @Observable needed).
// - Missing fields (author, lastRead) show fallback or are omitted.
// - File size formatted via FileSizeFormatter.
// - Date formatting uses .medium style for readability.
//
// @coordinates-with: LibraryView.swift, LibraryBookItem.swift, FileSizeFormatter.swift

import SwiftUI

// MARK: - ViewModel

/// Lightweight view model for BookInfoSheet, enabling unit-testable
/// formatting logic without SwiftUI rendering.
struct BookInfoViewModel {
    let title: String
    let author: String
    let formatDisplay: String
    let fileSize: String
    let dateAdded: String
    let lastRead: String?
    let readingTime: String?
    let formatIcon: String

    init(book: LibraryBookItem) {
        self.title = book.title
        self.author = book.author ?? "Unknown Author"
        self.formatDisplay = Self.displayFormat(book.format)
        self.fileSize = book.fileByteCount > 0
            ? FileSizeFormatter.format(byteCount: book.fileByteCount)
            : "Unknown"
        self.dateAdded = Self.formatDate(book.addedAt)
        self.lastRead = book.lastReadAt.map { Self.formatDate($0) }
        self.readingTime = book.formattedReadingTime
        self.formatIcon = book.formatIcon
    }

    // MARK: - Private

    private static func displayFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "md": return "Markdown"
        default: return format.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - View

/// Sheet displaying detailed metadata for a book.
struct BookInfoSheet: View {
    let book: LibraryBookItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let vm = BookInfoViewModel(book: book)
            Form {
                Section("Book") {
                    infoRow("Title", value: vm.title)
                    infoRow("Author", value: vm.author)
                    infoRow("Format", value: vm.formatDisplay, icon: vm.formatIcon)
                    infoRow("File Size", value: vm.fileSize)
                }

                Section("Activity") {
                    infoRow("Date Added", value: vm.dateAdded)
                    if let lastRead = vm.lastRead {
                        infoRow("Last Read", value: lastRead)
                    }
                    if let readingTime = vm.readingTime {
                        infoRow("Reading Time", value: readingTime)
                    }
                }
            }
            .navigationTitle("Book Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Private

    private func infoRow(_ label: String, value: String, icon: String? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }
}
