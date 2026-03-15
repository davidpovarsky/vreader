// Purpose: SwiftUI Form section for AI assistant configuration.
// Provides toggles, text fields, and sliders for all AI settings.
//
// Key decisions:
// - Observes AISettingsViewModel for all state.
// - SecureField for API key input (masked entry).
// - Slider for temperature with 0.1 step granularity.
// - Stepper for maxTokens with 256-step increments.
// - Save button triggers explicit configuration persistence.
// - Validation errors displayed inline below fields.
//
// @coordinates-with: AISettingsViewModel.swift, SettingsView.swift

import SwiftUI

/// Form section containing all AI assistant settings.
struct AISettingsSection: View {
    @Bindable var viewModel: AISettingsViewModel

    var body: some View {
        Section("AI Assistant") {
            aiToggle
        }

        if viewModel.isAIEnabled {
            Section("API Key") {
                apiKeyField
            }

            Section("Provider Configuration") {
                providerFields
            }

            Section("Data & Privacy") {
                consentToggle
            }
        }
    }

    // MARK: - Subviews

    private var aiToggle: some View {
        Toggle("Enable AI Assistant", isOn: $viewModel.isAIEnabled)
            .accessibilityIdentifier("aiToggle")
    }

    @ViewBuilder
    private var apiKeyField: some View {
        HStack {
            SecureField("Enter API Key", text: $viewModel.apiKeyInput)
                .textContentType(.password)
                .autocorrectionDisabled()
                .accessibilityIdentifier("apiKeyField")

            if viewModel.isAPIKeySaved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("API key saved")
            }
        }

        if let error = viewModel.apiKeyError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("apiKeyError")
        }

        HStack {
            Button("Save Key") {
                viewModel.saveAPIKey()
            }
            .disabled(viewModel.apiKeyInput.isEmpty)
            .accessibilityIdentifier("saveApiKeyButton")

            if viewModel.isAPIKeySaved {
                Button("Delete Key", role: .destructive) {
                    viewModel.deleteAPIKey()
                }
                .accessibilityIdentifier("deleteApiKeyButton")
            }
        }
    }

    @ViewBuilder
    private var providerFields: some View {
        HStack {
            Text("Model")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("Model name", text: $viewModel.model)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .accessibilityIdentifier("modelField")
        }

        HStack {
            Text("Base URL")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .accessibilityIdentifier("baseURLField")
        }

        if let error = viewModel.baseURLError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("baseURLError")
        }

        VStack(alignment: .leading) {
            HStack {
                Text("Temperature")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", viewModel.temperature))
                    .monospacedDigit()
            }
            Slider(
                value: $viewModel.temperature,
                in: 0.0...2.0,
                step: 0.1
            )
            .accessibilityIdentifier("temperatureSlider")
        }

        Stepper(
            "Max Tokens: \(viewModel.maxTokens)",
            value: $viewModel.maxTokens,
            in: 1...128_000,
            step: 256
        )
        .accessibilityIdentifier("maxTokensStepper")

        Button("Save Configuration") {
            viewModel.saveConfiguration()
        }
        .accessibilityIdentifier("saveConfigButton")
    }

    private var consentToggle: some View {
        Toggle("Allow AI data sharing", isOn: $viewModel.hasConsent)
            .accessibilityIdentifier("consentToggle")
    }
}
