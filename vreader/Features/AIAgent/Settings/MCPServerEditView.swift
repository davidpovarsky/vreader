// Purpose: Form sheet for adding or editing an MCP server profile.
// Validates endpoint URLs (HTTPS required unless loopback) and saves secrets into Keychain.

#if canImport(UIKit)
import SwiftUI

struct MCPServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    let profileToEdit: MCPServerProfile?
    let onSave: (MCPServerProfile) -> Void

    @State private var name: String = ""
    @State private var endpointString: String = ""
    @State private var authType: MCPAuthType = .none
    @State private var token: String = ""
    @State private var testStatus: String?
    @State private var isTesting: Bool = false
    @State private var errorMessage: String?

    init(profile: MCPServerProfile? = nil, onSave: @escaping (MCPServerProfile) -> Void) {
        self.profileToEdit = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _endpointString = State(initialValue: profile?.endpointURL.absoluteString ?? "")
        _authType = State(initialValue: profile?.authType ?? .none)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Details") {
                    TextField("Server Name", text: $name)
                        .accessibilityIdentifier("mcpServerNameInput")
                    TextField("Endpoint URL (https://...)", text: $endpointString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("mcpEndpointInput")
                }

                Section("Authentication") {
                    Picker("Auth Type", selection: $authType) {
                        Text("None").tag(MCPAuthType.none)
                        Text("Bearer Token").tag(MCPAuthType.bearerToken)
                        Text("OAuth 2.0").tag(MCPAuthType.oauth)
                    }

                    if authType == .bearerToken {
                        SecureField("Access Token", text: $token)
                            .accessibilityIdentifier("mcpTokenInput")
                    }
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(endpointURL == nil || isTesting)
                    .accessibilityIdentifier("testMcpConnectionButton")

                    if let testStatus {
                        Text(testStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(profileToEdit == nil ? "Add MCP Server" : "Edit MCP Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endpointURL == nil)
                        .accessibilityIdentifier("saveMcpServerButton")
                }
            }
        }
    }

    private var endpointURL: URL? {
        guard let url = URL(string: endpointString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    private func testConnection() {
        guard let url = endpointURL else { return }
        isTesting = true
        errorMessage = nil
        testStatus = nil

        let testProfile = MCPServerProfile(
            id: profileToEdit?.id ?? UUID(),
            name: name,
            endpointURL: url,
            authType: authType
        )

        guard testProfile.isSecureEndpoint else {
            isTesting = false
            errorMessage = "HTTPS is required for remote endpoints (HTTP allowed only on localhost)."
            return
        }

        Task {
            do {
                let tools = try await MCPClientManager.shared.testConnection(for: testProfile)
                testStatus = "Connected! Found \(tools.count) tool(s)."
            } catch {
                testStatus = "Connection failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func save() {
        guard let url = endpointURL else { return }
        let profile = MCPServerProfile(
            id: profileToEdit?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            endpointURL: url,
            isEnabled: profileToEdit?.isEnabled ?? true,
            authType: authType,
            dateAdded: profileToEdit?.dateAdded ?? Date(),
            lastConnected: profileToEdit?.lastConnected
        )

        guard profile.isSecureEndpoint else {
            errorMessage = "HTTPS is required for remote endpoints (HTTP allowed only on localhost)."
            return
        }

        if !token.isEmpty {
            try? MCPSecretStore().saveToken(token, forProfileID: profile.id)
        }

        onSave(profile)
        dismiss()
    }
}
#endif
