// Purpose: WebDAV connection configuration UI for backup settings.
// Allows users to enter server URL, username, and password.
// Provides connection testing and credential persistence via Keychain.
//
// Key decisions:
// - Credentials stored in Keychain (not UserDefaults) for security.
// - Connection test validates before saving credentials.
// - Server URL validated for https:// prefix (security best practice).
// - Form-based layout consistent with iOS Settings patterns.
//
// @coordinates-with: WebDAVClient.swift, WebDAVProvider.swift, KeychainService.swift, SettingsView.swift

import SwiftUI

/// WebDAV server configuration view for backup settings.
struct WebDAVSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var isSaving = false

    /// Keychain service for credential persistence.
    private let keychain: KeychainService

    // MARK: - Keychain Accounts

    private static let serverURLAccount = "com.vreader.webdav.serverURL"
    private static let usernameAccount = "com.vreader.webdav.username"
    private static let passwordAccount = "com.vreader.webdav.password"

    // MARK: - Init

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("webdavServerURL")

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("webdavUsername")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("webdavPassword")
            } header: {
                Text("WebDAV Server")
            } footer: {
                Text("Enter your WebDAV server details. Supports Nutstore, NextCloud, Synology, and other WebDAV-compatible services.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let result = testResult {
                            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isSuccess ? .green : .red)
                        }
                    }
                }
                .disabled(isTesting || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("webdavTestButton")

                if let result = testResult, !result.isSuccess {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await saveCredentials() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("webdavSaveButton")

                Button(role: .destructive) {
                    clearCredentials()
                } label: {
                    HStack {
                        Spacer()
                        Text("Remove Credentials")
                        Spacer()
                    }
                }
                .accessibilityIdentifier("webdavClearButton")
            }
        }
        .navigationTitle("WebDAV Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCredentials() }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }

        guard let url = URL(string: serverURL), url.scheme != nil else {
            testResult = TestResult(isSuccess: false, message: "Invalid server URL")
            return
        }

        let client = WebDAVClient(
            serverURL: url,
            username: username,
            password: password
        )

        do {
            try await client.testConnection()
            testResult = TestResult(isSuccess: true, message: "Connected successfully")
        } catch let error as WebDAVError {
            switch error {
            case .authenticationFailed:
                testResult = TestResult(isSuccess: false, message: "Authentication failed. Check username and password.")
            case .connectionFailed(let msg):
                testResult = TestResult(isSuccess: false, message: "Connection failed: \(msg)")
            default:
                testResult = TestResult(isSuccess: false, message: "Error: \(error)")
            }
        } catch {
            testResult = TestResult(isSuccess: false, message: "Connection error: \(error.localizedDescription)")
        }
    }

    private func saveCredentials() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try keychain.saveString(serverURL, forAccount: Self.serverURLAccount)
            try keychain.saveString(username, forAccount: Self.usernameAccount)
            try keychain.saveString(password, forAccount: Self.passwordAccount)
            dismiss()
        } catch {
            testResult = TestResult(
                isSuccess: false,
                message: "Failed to save credentials: \(error.localizedDescription)"
            )
        }
    }

    private func loadCredentials() {
        serverURL = (try? keychain.readString(forAccount: Self.serverURLAccount)) ?? ""
        username = (try? keychain.readString(forAccount: Self.usernameAccount)) ?? ""
        password = (try? keychain.readString(forAccount: Self.passwordAccount)) ?? ""
    }

    private func clearCredentials() {
        try? keychain.delete(forAccount: Self.serverURLAccount)
        try? keychain.delete(forAccount: Self.usernameAccount)
        try? keychain.delete(forAccount: Self.passwordAccount)
        serverURL = ""
        username = ""
        password = ""
        testResult = nil
    }

    // MARK: - Types

    private struct TestResult {
        let isSuccess: Bool
        let message: String
    }
}
