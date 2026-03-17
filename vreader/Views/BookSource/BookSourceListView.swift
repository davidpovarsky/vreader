// Purpose: List view for managing BookSource entries.
// Users can enable/disable sources, swipe to delete, and navigate to the editor.
//
// Key decisions:
// - Uses SwiftData @Query for automatic updates on model changes.
// - Enable/disable via toggle (most common operation — needs zero taps beyond toggle).
// - Source type shown as badge for visual grouping.
// - Empty state guides users to add sources or import from Legado JSON.
//
// @coordinates-with: BookSource.swift, BookSourceEditorView.swift

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Manages the user's list of book sources with enable/disable toggles.
struct BookSourceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookSource.customOrder) private var sources: [BookSource]

    @State private var isShowingEditor = false
    @State private var isShowingSearch = false
    @State private var isShowingLegadoImporter = false
    @State private var isShowingShareSheet = false
    @State private var shareFileURL: URL?
    @State private var legadoImportMessage: String?
    @State private var editingSource: BookSource?

    var body: some View {
        Group {
            if sources.isEmpty {
                emptyState
            } else {
                sourceList
            }
        }
        .navigationTitle("Book Sources")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search books")
                .accessibilityIdentifier("bookSourceSearch")
                .disabled(sources.filter(\.enabled).isEmpty)

                Button {
                    isShowingLegadoImporter = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .accessibilityLabel("Import Legado sources")
                .accessibilityIdentifier("bookSourceLegadoImport")

                Button {
                    editingSource = nil
                    isShowingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add source")
                .accessibilityIdentifier("bookSourceAdd")
            }
        }
        .navigationDestination(isPresented: $isShowingSearch) {
            if let firstEnabled = sources.first(where: \.enabled) {
                BookSourceSearchView(source: BookSourceSnapshot(from: firstEnabled))
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                BookSourceEditorView(
                    source: editingSource,
                    onSave: { saved in
                        if editingSource == nil {
                            modelContext.insert(saved)
                        }
                        isShowingEditor = false
                    },
                    onCancel: {
                        isShowingEditor = false
                    }
                )
            }
        }
        .fileImporter(
            isPresented: $isShowingLegadoImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importLegadoSources(from: url)
            case .failure:
                break
            }
        }
        .alert("Import Result", isPresented: .init(
            get: { legadoImportMessage != nil },
            set: { if !$0 { legadoImportMessage = nil } }
        )) {
            Button("OK") { legadoImportMessage = nil }
        } message: {
            Text(legadoImportMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.desk")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Book Sources")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Add a book source to search and read web novels. Sources define how to extract content from websites.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                editingSource = nil
                isShowingEditor = true
            } label: {
                Label("Add Source", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("bookSourceAddEmpty")
        }
        .accessibilityIdentifier("bookSourceEmptyState")
    }

    private var sourceList: some View {
        List {
            ForEach(sources) { source in
                sourceRow(source)
                    .contextMenu {
                        Button {
                            shareSource(source)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
            }
            .onDelete(perform: deleteSources)
        }
        .listStyle(.plain)
        .accessibilityIdentifier("bookSourceList")
        .sheet(isPresented: $isShowingShareSheet) {
            if let url = shareFileURL {
                ShareActivityView(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.sourceName)
                        .font(.body)
                        .lineLimit(1)

                    sourceTypeBadge(source.sourceType)
                }

                Text(source.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let group = source.sourceGroup {
                    Text(group)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { source.enabled = $0 }
            ))
            .labelsHidden()
            .accessibilityLabel("Enable \(source.sourceName)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            editingSource = source
            isShowingEditor = true
        }
        .accessibilityIdentifier("bookSource_\(source.sourceURL)")
    }

    private func sourceTypeBadge(_ type: Int) -> some View {
        let (label, color): (String, Color) = switch type {
        case 1: ("Audio", .purple)
        case 2: ("Image", .orange)
        case 3: ("File", .gray)
        default: ("Text", .blue)
        }

        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Source Sharing (D07b)

    private func shareSource(_ source: BookSource) {
        guard let data = try? SourceSharingService.exportSource(source) else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(source.sourceName).json")
        try? data.write(to: tempURL, options: .atomic)
        shareFileURL = tempURL
        isShowingShareSheet = true
    }

    // MARK: - Legado Import (D05)

    private func importLegadoSources(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            legadoImportMessage = "Could not read file."
            return
        }

        do {
            let imported = try LegadoImporter.importSources(from: data)
            for source in imported {
                modelContext.insert(source)
            }
            legadoImportMessage = "Imported \(imported.count) source(s)."
        } catch {
            legadoImportMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Actions

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
    }
}
