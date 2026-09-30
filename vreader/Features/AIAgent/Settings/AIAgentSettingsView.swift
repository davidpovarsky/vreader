// Purpose: Master advanced AI settings view containing tools, permissions, semantic model, Apple AI, and MCP options.

#if canImport(UIKit)
import SwiftUI

struct AIAgentSettingsView: View {
    @State private var viewModel = AIAgentSettingsViewModel()
    private let theme: ReaderThemeV2 = .paper

    var body: some View {
        Form {
            Section("Tools & Capabilities") {
                Toggle("Use AI Agentic Tools", isOn: Binding(
                    get: { viewModel.isAgenticToolsEnabled },
                    set: { viewModel.setAgenticToolsEnabled($0) }
                ))
                .accessibilityIdentifier("agenticToolsToggle")

                Toggle("OCR for Scanned PDFs", isOn: Binding(
                    get: { viewModel.capabilities.isOCREnabled },
                    set: { val in Task { await viewModel.setOCREnabled(val) } }
                ))
                .accessibilityIdentifier("ocrToggle")

                NavigationLink {
                    MCPServerListView(viewModel: viewModel)
                } label: {
                    HStack {
                        Text("MCP External Servers")
                        Spacer()
                        Text("\(viewModel.mcpProfiles.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("mcpServersNavLink")
            }

            AIPermissionSettingsSection(viewModel: viewModel, theme: theme)

            AISemanticModelSettingsSection(viewModel: viewModel, theme: theme)

            AIFoundationModelsSettingsSection(viewModel: viewModel, theme: theme)
        }
        .navigationTitle("AI Assistant Settings")
        .task {
            await viewModel.load()
        }
    }
}
#endif
