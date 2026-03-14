// Purpose: Main settings sheet presented from the library toolbar.
// Contains AI settings section and app info (About section).
//
// Key decisions:
// - Presented as sheet from gear icon in LibraryView toolbar.
// - NavigationStack with Form for consistent iOS settings-style layout.
// - AISettingsViewModel created once and owned by this view.
// - Dismiss button in toolbar.
// - About section shows app version from Bundle.
//
// @coordinates-with: LibraryView.swift, AISettingsSection.swift, AISettingsViewModel.swift

import SwiftUI

/// App settings screen presented as a sheet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AISettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                AISettingsSection(viewModel: viewModel)

                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.appVersion)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settingsDoneButton")
                }
            }
        }
        .accessibilityIdentifier("settingsView")
    }

    // MARK: - Private

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}
