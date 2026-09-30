// Purpose: List view managing configured Model Context Protocol (MCP) server profiles.

#if canImport(UIKit)
import SwiftUI

struct MCPServerListView: View {
    @Bindable var viewModel: AIAgentSettingsViewModel
    @State private var profileToEdit: MCPServerProfile?
    @State private var isAddingServer: Bool = false

    var body: some View {
        List {
            Section {
                if viewModel.mcpProfiles.isEmpty {
                    Text("No MCP servers configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.mcpProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 15, weight: .medium))
                                Text(profile.endpointURL.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { profile.isEnabled },
                                set: { _ in Task { await viewModel.toggleMCPProfile(profile) } }
                            ))
                            .labelsHidden()
                            .accessibilityIdentifier("mcpServerToggle-\(profile.id.uuidString)")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            profileToEdit = profile
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let profile = viewModel.mcpProfiles[idx]
                            Task { await viewModel.deleteMCPProfile(profile) }
                        }
                    }
                }
            } header: {
                Text("Configured Servers")
            } footer: {
                Text("MCP servers provide external tools to the assistant over secure HTTP/SSE connections.")
            }
        }
        .navigationTitle("MCP Servers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addMcpServerButton")
            }
        }
        .sheet(isPresented: $isAddingServer) {
            MCPServerEditView { newProfile in
                Task {
                    await MCPServerProfileStore.shared.saveProfile(newProfile)
                    await viewModel.load()
                }
            }
        }
        .sheet(item: $profileToEdit) { profile in
            MCPServerEditView(profile: profile) { updated in
                Task {
                    await MCPServerProfileStore.shared.saveProfile(updated)
                    await viewModel.load()
                }
            }
        }
    }
}
#endif
