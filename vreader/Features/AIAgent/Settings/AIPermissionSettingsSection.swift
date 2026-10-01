// Purpose: Settings sections for AI permissions, spoiler boundaries, and capability toggles.

#if canImport(UIKit)
import SwiftUI

struct AIPermissionSettingsSection: View {
    @Bindable var viewModel: AIAgentSettingsViewModel
    let theme: ReaderThemeV2

    var body: some View {
        Section {
            Picker("Read Ahead & Spoilers", selection: Binding(
                get: { viewModel.preferences.readAheadMode },
                set: { newMode in viewModel.setReadAheadMode(newMode) }
            )) {
                Text("Never read ahead").tag(AIReadAheadMode.neverReadAhead)
                Text("Ask before reading ahead").tag(AIReadAheadMode.askBeforeReadingAhead)
                Text("Whole book allowed").tag(AIReadAheadMode.wholeBookAllowed)
            }
            .accessibilityIdentifier("readAheadPicker")

            permissionRow(title: "Read current book", category: .readCurrentBook)
            permissionRow(title: "Read other books", category: .readOtherBooks)
            permissionRow(title: "Navigate reader", category: .navigateReader)
            permissionRow(title: "Write annotations", category: .writeAnnotations)
            permissionRow(title: "Modify annotations", category: .modifyAnnotations)
            permissionRow(title: "External network (MCP)", category: .externalNetwork)

            // Deletion/removal: Strictly always ask
            HStack {
                Text("Delete notes & bookmarks")
                    .foregroundStyle(Color(theme.inkColor))
                Spacer()
                Text("Always ask")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("deletePermissionRow")
        } header: {
            Text("Permissions & Spoilers")
        }
    }

    private func permissionRow(title: String, category: AIToolPermissionCategory) -> some View {
        Picker(title, selection: Binding(
            get: { viewModel.permission(for: category) },
            set: { newDecision in viewModel.setPermission(category, policy: newDecision) }
        )) {
            Text("Allow").tag(AIToolPermissionDecision.allow)
            Text("Ask").tag(AIToolPermissionDecision.ask)
            Text("Deny").tag(AIToolPermissionDecision.deny)
        }
    }
}
#endif
