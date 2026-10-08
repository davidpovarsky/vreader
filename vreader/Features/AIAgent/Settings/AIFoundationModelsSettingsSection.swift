// Purpose: Settings section for AI backend selection, Apple Foundation Models mode, and privacy disclosures.

#if canImport(UIKit)
import SwiftUI

struct AIFoundationModelsSettingsSection: View {
    @Bindable var viewModel: AIAgentSettingsViewModel
    let theme: ReaderThemeV2

    var body: some View {
        Section {
            Picker("AI Backend", selection: Binding(
                get: { viewModel.capabilities.backendChoice },
                set: { newChoice in Task { await viewModel.setBackendChoice(newChoice) } }
            )) {
                ForEach(AIAgentBackendChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .accessibilityIdentifier("aiBackendChoicePicker")

            if viewModel.capabilities.backendChoice == .appleFoundationModels {
                Picker("Apple AI Mode", selection: Binding(
                    get: { viewModel.capabilities.foundationModelMode },
                    set: { newMode in
                        let safeMode = (newMode == .privateCloudCompute) ? .onDevice : newMode
                        Task { await viewModel.setFoundationModelMode(safeMode) }
                    }
                )) {
                    ForEach(AppleFoundationModelMode.allCases, id: \.self) { mode in
                        if mode == .privateCloudCompute {
                            Text("\(mode.localizedTitle) (Unsupported in 3rd-party SDK)").tag(mode)
                        } else {
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                }
                .accessibilityIdentifier("appleAIModePicker")

                if viewModel.capabilities.foundationModelMode == .automatic {
                    Toggle("Allow Private Cloud Compute", isOn: Binding(
                        get: { viewModel.capabilities.isPCCConsentGranted },
                        set: { val in Task { await viewModel.setPCCConsent(val) } }
                    ))
                    .accessibilityIdentifier("pccConsentToggle")
                }
            }
        } header: {
            Text("AI Backend & Foundation Models")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("• Configured Provider uses your selected cloud provider (OpenAI, Anthropic, etc.).")
                Text("• On-Device Apple AI processes text entirely on your device with no external data transmission.")
                Text("• Private Cloud Compute is managed system-side by iOS and is not available via public 3rd-party developer APIs.")
            }
            .font(.caption2)
        }
    }
}
#endif
