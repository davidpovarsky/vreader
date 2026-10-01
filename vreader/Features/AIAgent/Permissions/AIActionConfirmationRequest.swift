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
    let readerSessionID: AIDocumentSessionID?

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
        externalServerIdentifier: String? = nil,
        readerSessionID: AIDocumentSessionID? = nil
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
        self.readerSessionID = readerSessionID
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
            sourceLocator: overrideLocator ?? sourceLocator,
            externalServerIdentifier: externalServerIdentifier,
            readerSessionID: readerSessionID
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
    let readerSessionID: AIDocumentSessionID?

    var externalServerName: String? {
        externalServerIdentifier ?? metadata["serverName"] ?? metadata["externalServerName"]
    }

    var requestedReadAhead: Bool {
        permissionCategory == .readAhead || metadata["requestedReadAhead"] == "true"
    }

    init(
        id: UUID = UUID(),
        toolName: String = "",
        actionDescription: String,
        permissionCategory: AIToolPermissionCategory,
        metadata: [String: String] = [:],
        isDestructive: Bool = false,
        rememberAllowEligible: Bool = true,
        turnID: String? = nil,
        toolCallID: String? = nil,
        bookFingerprintKey: String? = nil,
        sourceLocator: Locator? = nil,
        externalServerIdentifier: String? = nil,
        externalServerName: String? = nil,
        readerSessionID: AIDocumentSessionID? = nil
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
        self.externalServerIdentifier = externalServerIdentifier ?? externalServerName
        self.readerSessionID = readerSessionID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case actionDescription
        case permissionCategory
        case metadata
        case isDestructive
        case rememberAllowEligible
        case turnID
        case toolCallID
        case bookFingerprintKey
        case sourceLocator
        case externalServerIdentifier
        case readerSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            toolName: try container.decode(String.self, forKey: .toolName),
            actionDescription: try container.decode(String.self, forKey: .actionDescription),
            permissionCategory: try container.decode(
                AIToolPermissionCategory.self,
                forKey: .permissionCategory
            ),
            metadata: try container.decodeIfPresent(
                [String: String].self,
                forKey: .metadata
            ) ?? [:],
            isDestructive: try container.decodeIfPresent(
                Bool.self,
                forKey: .isDestructive
            ) ?? false,
            rememberAllowEligible: try container.decodeIfPresent(
                Bool.self,
                forKey: .rememberAllowEligible
            ) ?? false,
            turnID: try container.decodeIfPresent(String.self, forKey: .turnID),
            toolCallID: try container.decodeIfPresent(String.self, forKey: .toolCallID),
            bookFingerprintKey: try container.decodeIfPresent(
                String.self,
                forKey: .bookFingerprintKey
            ),
            sourceLocator: try container.decodeIfPresent(Locator.self, forKey: .sourceLocator),
            externalServerIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .externalServerIdentifier
            ),
            readerSessionID: try container.decodeIfPresent(
                AIDocumentSessionID.self,
                forKey: .readerSessionID
            )
        )
    }
}

enum AIActionConfirmationResponse: Equatable, Sendable {
    case allowOnce
    case deny
    case alwaysAllow
}

enum AIActionConfirmationOutcome: Equatable, Sendable {
    case allowed
    case allowedOnce
    case denied
    case cancelled

    public static func == (lhs: AIActionConfirmationOutcome, rhs: AIActionConfirmationOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.allowed, .allowed), (.allowedOnce, .allowedOnce), (.denied, .denied), (.cancelled, .cancelled):
            return true
        case (.allowed, .allowedOnce), (.allowedOnce, .allowed):
            return true
        default:
            return false
        }
    }
}
