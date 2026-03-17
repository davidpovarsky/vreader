// Purpose: Main settings sheet presented from the library toolbar.
// Grouped into sections: Reading, Content Sources, Backup, AI, and About.
//
// Key decisions:
// - Presented as sheet from gear icon in LibraryView toolbar.
// - NavigationStack with Form for consistent iOS settings-style layout.
// - AISettingsViewModel created once and owned by this view.
// - Dismiss button in toolbar.
// - About section shows app version from Bundle.
// - All feature settings reachable from this single entry point.
//
// @coordinates-with: LibraryView.swift, AISettingsSection.swift, AISettingsViewModel.swift,
//   ReplacementRulesView.swift, BookSourceListView.swift, WebDAVSettingsView.swift,
//   HTTPTTSSettingsView.swift

import SwiftUI

/// App settings screen presented as a sheet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AISettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Reading

                Section("Reading") {
                    NavigationLink {
                        ReplacementRulesView()
                    } label: {
                        Label("Replacement Rules", systemImage: "character.textbox")
                    }
                    .accessibilityIdentifier("settingsReplacementRules")

                    NavigationLink {
                        HTTPTTSSettingsView()
                    } label: {
                        Label("HTTP TTS", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("settingsHTTPTTS")
                }

                // MARK: - Content Sources

                Section("Content Sources") {
                    NavigationLink {
                        BookSourceListView()
                    } label: {
                        Label("Book Sources", systemImage: "globe")
                    }
                    .accessibilityIdentifier("settingsBookSources")
                }

                // MARK: - Backup

                Section("Backup") {
                    NavigationLink {
                        WebDAVSettingsView()
                    } label: {
                        Label("WebDAV Backup", systemImage: "externaldrive.badge.icloud")
                    }
                    .accessibilityIdentifier("settingsWebDAV")
                }

                // MARK: - AI

                AISettingsSection(viewModel: viewModel)

                // MARK: - About

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
