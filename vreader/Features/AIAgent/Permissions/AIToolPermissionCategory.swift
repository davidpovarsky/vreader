// Purpose: Semantic permission vocabulary for every AI-agent tool/action.
// Individual tools map to these categories; they do not invent local policy.

import Foundation

enum AIToolPermissionDecision: String, Codable, CaseIterable, Sendable {
    case allow
    case ask
    case deny
}

enum AIToolPermissionCategory: String, Codable, CaseIterable, Sendable {
    case readCurrentBook
    case readOtherBooks
    case navigateReader
    case writeAnnotations
    case modifyAnnotations
    case removeData
    case externalNetwork
    case readAhead
}
