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

/// Manages the user's list of book sources with enable/disable toggles.
struct BookSourceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookSource.customOrder) private var sources: [BookSource]

    @State private var isShowingEditor = false
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
            ToolbarItem(placement: .topBarTrailing) {
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
            }
            .onDelete(perform: deleteSources)
        }
        .listStyle(.plain)
        .accessibilityIdentifier("bookSourceList")
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

    // MARK: - Actions

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
    }
}
