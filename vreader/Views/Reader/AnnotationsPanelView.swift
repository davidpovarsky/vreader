// Purpose: Tabbed panel for bookmarks, TOC, highlights, and annotations.
// Extracted from ReaderContainerView (WI-004) to reduce its size.
//
// Key decisions:
// - Owns @State selectedTab (parent does not need to track tab selection).
// - Uses closure-based interface: onNavigate + onDismiss.
// - Creates list ViewModels internally from modelContainer + bookFingerprintKey.
// - Does NOT own sheet presentation — parent controls .sheet(isPresented:).
//
// @coordinates-with ReaderContainerView.swift, BookmarkListView.swift,
//   HighlightListView.swift, AnnotationListView.swift, TOCListView.swift

import SwiftUI
import SwiftData

// MARK: - Tab Enum

/// Tabs for the annotations panel.
enum AnnotationsPanelTab: String, CaseIterable, Identifiable {
    case bookmarks = "Bookmarks"
    case toc = "Contents"
    case highlights = "Highlights"
    case annotations = "Notes"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bookmarks: return "bookmark"
        case .toc: return "list.bullet"
        case .highlights: return "highlighter"
        case .annotations: return "note.text"
        }
    }
}

// MARK: - Panel View

/// Sheet content for the tabbed reader annotations panel.
/// Parent wires this into a `.sheet` modifier and provides navigation/dismiss closures.
struct AnnotationsPanelView: View {
    let bookFingerprintKey: String
    let modelContainer: ModelContainer
    let tocEntries: [TOCEntry]
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    @State private var selectedTab: AnnotationsPanelTab = .bookmarks
    @State private var bookmarkVM: BookmarkListViewModel?
    @State private var highlightVM: HighlightListViewModel?
    @State private var annotationVM: AnnotationListViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(AnnotationsPanelTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()
                    .padding(.top, 8)

                Group {
                    switch selectedTab {
                    case .bookmarks:
                        if let vm = bookmarkVM {
                            BookmarkListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    case .toc:
                        TOCListView(entries: tocEntries, onNavigate: handleNavigate)
                    case .highlights:
                        if let vm = highlightVM {
                            HighlightListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    case .annotations:
                        if let vm = annotationVM {
                            AnnotationListView(viewModel: vm, onNavigate: handleNavigate)
                        } else {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Reader Panels")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            guard bookmarkVM == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let bVM = BookmarkListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            let hVM = HighlightListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence,
                totalTextLengthUTF16: nil
            )
            let aVM = AnnotationListViewModel(
                bookFingerprintKey: bookFingerprintKey,
                store: persistence
            )
            // Assign all at once to avoid partial init on task cancellation
            bookmarkVM = bVM
            highlightVM = hVM
            annotationVM = aVM
        }
        .accessibilityIdentifier("annotationsPanelSheet")
    }

    private func handleNavigate(_ locator: Locator) {
        onNavigate(locator)
        onDismiss()
    }
}
