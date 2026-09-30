// Purpose: Persistable product policy for AI-agent permissions and spoiler access.
// Decoding is deliberately tolerant: missing/unknown keys retain conservative,
// deterministic defaults so an older app never fails an entire preference load.

import Foundation

struct AIAgentPreferences: Codable, Equatable, Sendable {
    private(set) var permissionDecisions: [AIToolPermissionCategory: AIToolPermissionDecision]
    private(set) var readAheadMode: AIReadAheadMode

    private static let defaultPermissionDecisions: [
        AIToolPermissionCategory: AIToolPermissionDecision
    ] = [
        .readCurrentBook: .allow,
        .readOtherBooks: .ask,
        .navigateReader: .ask,
        .writeAnnotations: .ask,
        .modifyAnnotations: .ask,
        .removeData: .ask,
        .externalNetwork: .ask,
        // The mode is the spoiler gate. Keeping this category allowed lets an
        // explicit wholeBookAllowed mode work while never/ask still override it.
        .readAhead: .allow,
    ]

    static let `default` = AIAgentPreferences(
        permissionDecisions: defaultPermissionDecisions,
        readAheadMode: .neverReadAhead
    )

    init(
        permissionDecisions: [AIToolPermissionCategory: AIToolPermissionDecision] =
            AIAgentPreferences.default.permissionDecisions,
        readAheadMode: AIReadAheadMode = .neverReadAhead
    ) {
        var complete = Self.defaultPermissionDecisions
        complete.merge(permissionDecisions) { _, supplied in supplied }
        self.permissionDecisions = complete
        self.readAheadMode = readAheadMode
    }

    func decision(for category: AIToolPermissionCategory) -> AIToolPermissionDecision {
        permissionDecisions[category]
            ?? AIAgentPreferences.default.permissionDecisions[category]
            ?? .ask
    }

    mutating func setDecision(
        _ decision: AIToolPermissionDecision,
        for category: AIToolPermissionCategory
    ) {
        permissionDecisions[category] = decision
    }

    mutating func setReadAheadMode(_ mode: AIReadAheadMode) {
        readAheadMode = mode
    }

    var permissions: [AIToolPermissionCategory: AIToolPermissionDecision] {
        get { permissionDecisions }
        set { permissionDecisions = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case permissions
        case readAheadMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPermissions =
            (try? container.decode([String: String].self, forKey: .permissions)) ?? [:]
        var decisions = Self.defaultPermissionDecisions
        for (rawCategory, rawDecision) in rawPermissions {
            guard let category = AIToolPermissionCategory(rawValue: rawCategory),
                  let decision = AIToolPermissionDecision(rawValue: rawDecision) else {
                continue
            }
            decisions[category] = decision
        }

        let rawReadAhead = try? container.decode(String.self, forKey: .readAheadMode)
        permissionDecisions = decisions
        readAheadMode = rawReadAhead.flatMap(AIReadAheadMode.init(rawValue:))
            ?? .neverReadAhead
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawPermissions = Dictionary(uniqueKeysWithValues: permissionDecisions.map {
            ($0.key.rawValue, $0.value.rawValue)
        })
        try container.encode(rawPermissions, forKey: .permissions)
        try container.encode(readAheadMode.rawValue, forKey: .readAheadMode)
    }
}
