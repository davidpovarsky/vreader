// Purpose: UI-neutral confirmation request/response values. Requests carry only
// bounded action metadata and navigation identity, never provider secrets/payloads.

import Foundation

struct AIToolAuthorizationContext: Equatable, Sendable {
    let toolName: String
    let actionDescription: String
    let permissionCategory: AIToolPermissionCategory
    let metadata: [String: String]
    let isDestructive: Bool
    let rememberAllowEligible: Bool
    let turnID: String?
    let toolCallID: String?
    let bookFingerprintKey: String?
    let sourceLocator: Locator?
    let externalServerIdentifier: String?

    init(
        toolName: String,
        actionDescription: String,
        permissionCategory: AIToolPermissionCategory,
        metadata: [String: String] = [:],
        isDestructive: Bool = false,
        rememberAllowEligible: Bool = true,
        turnID: String? = nil,
        toolCallID: String? = nil,
        bookFingerprintKey: String? = nil,
        sourceLocator: Locator? = nil,
        externalServerIdentifier: String? = nil
    ) {
        self.toolName = toolName
        self.actionDescription = actionDescription
        self.permissionCategory = permissionCategory
        self.metadata = metadata
        self.isDestructive = isDestructive || permissionCategory == .removeData
        self.rememberAllowEligible = rememberAllowEligible
            && !self.isDestructive
            && permissionCategory != .removeData
        self.turnID = turnID
        self.toolCallID = toolCallID
        self.bookFingerprintKey = bookFingerprintKey
        self.sourceLocator = sourceLocator
        self.externalServerIdentifier = externalServerIdentifier
    }

    func confirmationRequest(
        id: UUID = UUID(),
        sourceLocator overrideLocator: Locator? = nil
    ) -> AIActionConfirmationRequest {
        AIActionConfirmationRequest(
            id: id,
            toolName: toolName,
            actionDescription: actionDescription,
            permissionCategory: permissionCategory,
            metadata: metadata,
            isDestructive: isDestructive,
            rememberAllowEligible: rememberAllowEligible,
            turnID: turnID,
            toolCallID: toolCallID,
            bookFingerprintKey: bookFingerprintKey,
            sourceLocator: sourceLocator ?? overrideLocator,
            externalServerIdentifier: externalServerIdentifier
        )
    }
}

struct AIActionConfirmationRequest: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let actionDescription: String
    let permissionCategory: AIToolPermissionCategory
    let metadata: [String: String]
    let isDestructive: Bool
    let rememberAllowEligible: Bool
    let turnID: String?
    let toolCallID: String?
    let bookFingerprintKey: String?
    let sourceLocator: Locator?
    let externalServerIdentifier: String?

    init(
        id: UUID = UUID(),
        toolName: String,
        actionDescription: String,
        permissionCategory: AIToolPermissionCategory,
        metadata: [String: String] = [:],
        isDestructive: Bool = false,
        rememberAllowEligible: Bool = true,
        turnID: String? = nil,
        toolCallID: String? = nil,
        bookFingerprintKey: String? = nil,
        sourceLocator: Locator? = nil,
        externalServerIdentifier: String? = nil
    ) {
        let destructive = isDestructive || permissionCategory == .removeData
        self.id = id
        self.toolName = toolName
        self.actionDescription = actionDescription
        self.permissionCategory = permissionCategory
        self.metadata = metadata
        self.isDestructive = destructive
        self.rememberAllowEligible = rememberAllowEligible
            && !destructive
            && permissionCategory != .removeData
        self.turnID = turnID
        self.toolCallID = toolCallID
        self.bookFingerprintKey = bookFingerprintKey
        self.sourceLocator = sourceLocator
        self.externalServerIdentifier = externalServerIdentifier
    }
}

enum AIActionConfirmationResponse: Equatable, Sendable {
    case allowOnce
    case deny
    case alwaysAllow
}

enum AIActionConfirmationOutcome: Equatable, Sendable {
    case allowed
    case denied
    case cancelled
}
