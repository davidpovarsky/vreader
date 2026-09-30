// Purpose: Settings section managing the multilingual-e5-small on-device embedding model and semantic search.

#if canImport(UIKit)
import SwiftUI

struct AISemanticModelSettingsSection: View {
    @Bindable var viewModel: AIAgentSettingsViewModel
    let theme: ReaderThemeV2

    var body: some View {
        Section {
            Toggle("Enable Semantic Search", isOn: Binding(
                get: { viewModel.capabilities.isSemanticSearchEnabled },
                set: { val in Task { await viewModel.setSemanticSearchEnabled(val) } }
            ))
            .disabled(!viewModel.modelState.isInstalled)
            .accessibilityIdentifier("semanticSearchToggle")

            HStack {
                Text("Embedding Model")
                Spacer()
                Text("multilingual-e5-small")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Model Status")
                Spacer()
                statusLabel
            }

            if case .downloading(let progress) = viewModel.modelState {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            if viewModel.modelDiskUsage > 0 {
                HStack {
                    Text("Disk Usage")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.modelDiskUsage, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.modelState.isInstalled {
                Button {
                    Task { await viewModel.downloadSemanticModel() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Download Model (~470 MB)")
                    }
                }
                .accessibilityIdentifier("downloadModelButton")
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.removeSemanticModel() }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Downloaded Model")
                    }
                }
                .accessibilityIdentifier("removeModelButton")
            }
        } header: {
            Text("Semantic Search & Embeddings")
        } footer: {
            Text("Semantic search finds concepts and meaning even when exact words differ. Runs entirely on-device.")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch viewModel.modelState {
        case .notInstalled:
            Text("Not Installed").font(.caption).foregroundStyle(.secondary)
        case .downloading(let p):
            Text("Downloading (\(Int(p * 100))%)").font(.caption).foregroundStyle(.blue)
        case .installed:
            Text("Installed").font(.caption).foregroundStyle(.green)
        case .loading:
            Text("Loading...").font(.caption).foregroundStyle(.orange)
        case .ready:
            Text("Ready").font(.caption).foregroundStyle(.green)
        case .failed(let err):
            Text("Failed: \(err)").font(.caption).foregroundStyle(.red)
        }
    }
}
#endif
