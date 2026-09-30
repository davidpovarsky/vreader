// Purpose: Settings section for Apple Foundation Models backend mode selection and privacy disclosures.

#if canImport(UIKit)
import SwiftUI

struct AIFoundationModelsSettingsSection: View {
    @Bindable var viewModel: AIAgentSettingsViewModel
    let theme: ReaderThemeV2

    var body: some View {
        Section {
            Picker("Apple AI Mode", selection: Binding(
                get: { viewModel.capabilities.foundationModelMode },
                set: { newMode in Task { await viewModel.setFoundationModelMode(newMode) } }
            )) {
                ForEach(AppleFoundationModelMode.allCases, id: \.self) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }
            .accessibilityIdentifier("appleAIModePicker")

            if viewModel.capabilities.foundationModelMode == .privateCloudCompute ||
               viewModel.capabilities.foundationModelMode == .automatic {
                Toggle("Allow Private Cloud Compute", isOn: Binding(
                    get: { viewModel.capabilities.isPCCConsentGranted },
                    set: { val in Task { await viewModel.setPCCConsent(val) } }
                ))
                .accessibilityIdentifier("pccConsentToggle")
            }
        } header: {
            Text("Apple Foundation Models")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("• On-Device Apple AI processes text entirely on your device with no external data transmission.")
                Text("• Private Cloud Compute sends encrypted requests to Apple silicon servers when complex reasoning is required.")
                Text("• Third-party cloud providers (OpenAI, Anthropic) process data according to their separate privacy terms.")
            }
            .font(.caption2)
        }
    }
}
#endif
