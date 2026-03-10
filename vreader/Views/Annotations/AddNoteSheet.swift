// Purpose: Sheet for adding a new annotation note with multi-line text input.
// Shows the selected text as context and provides a TextEditor for the note.
//
// @coordinates-with: TXTReaderContainerView.swift, MDReaderContainerView.swift

import SwiftUI

/// Sheet for creating an annotation with a multi-line text editor (bug #49).
struct AddNoteSheet: View {
    let selectedText: String
    @Binding var noteText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if !selectedText.isEmpty {
                    Text("\"\(selectedText.prefix(200))\"")
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                TextEditor(text: $noteText)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("addNoteTextEditor")
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("addNoteCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addNoteSave")
                }
            }
        }
    }
}
