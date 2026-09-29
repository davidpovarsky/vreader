// Purpose: Authorized reader navigation tools for Feature #177 WI-6.

import Foundation

struct OpenLocationTool: AITool {
    static let toolName = "open_location"
    let context: any AIReaderToolContextProviding
    let router: any AIReaderNavigationRouting
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        context: any AIReaderToolContextProviding,
        router: any AIReaderNavigationRouting,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 2_000
    ) {
        self.context = context
        self.router = router
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Navigate the exact active reader to a structured locator from another tool.",
            inputSchema: locatorSchema(titleRequired: false)
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard let locator = AIReaderToolOutput.decodeLocator(input) else {
            return error("Missing or invalid locator_json.")
        }
        let fingerprint = await context.fingerprint
        guard locator.bookFingerprint == fingerprint else {
            return error("That locator belongs to another book; use open_book instead.")
        }
        let outcome = await authorizationGate.authorize(
            AIAgentToolAuthorization.context(
                toolName: Self.toolName,
                actionDescription: "Navigate the current reader",
                category: .navigateReader,
                bookFingerprintKey: fingerprint.canonicalKey,
                sourceLocator: locator
            )
        )
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(
                outcome, maxBytes: maxContentBytes
            )
        }
        let session = await context.sessionID
        guard !Task.isCancelled,
              await router.navigate(to: locator, session: session),
              !Task.isCancelled else {
            return error("Navigation was cancelled or unavailable.")
        }
        return AIReaderToolOutput.boundedResult(
            "Navigated the current reader to the requested location.",
            maxBytes: maxContentBytes
        )
    }

    private func error(_ message: String) -> ToolResult {
        AIReaderToolOutput.boundedResult(
            message, maxBytes: maxContentBytes, isError: true
        )
    }
}

struct OpenBookTool: AITool {
    static let toolName = "open_book"
    let bookResolver: any BookContentProvider
    let router: any AIReaderNavigationRouting
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        bookResolver: any BookContentProvider,
        router: any AIReaderNavigationRouting,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 2_000
    ) {
        self.bookResolver = bookResolver
        self.router = router
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Open an existing local library book, optionally at a structured locator.",
            inputSchema: locatorSchema(titleRequired: true)
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard let title = input["title"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return error("Missing required title.")
        }
        let contexts = [
            AIAgentToolAuthorization.context(
                toolName: Self.toolName,
                actionDescription: "Read another library book identity",
                category: .readOtherBooks,
                metadata: ["title": ToolResultText.oneLine(title, maxChars: 120)]
            ),
            AIAgentToolAuthorization.context(
                toolName: Self.toolName,
                actionDescription: "Open another book in the reader",
                category: .navigateReader,
                metadata: ["title": ToolResultText.oneLine(title, maxChars: 120)]
            ),
        ]
        let outcome = await authorizationGate.authorize(contexts)
        guard outcome == .allowed else {
            return AIAgentToolAuthorization.errorResult(
                outcome, maxBytes: maxContentBytes
            )
        }
        guard !Task.isCancelled else { return error("Opening the book was cancelled.") }

        let info: BookContentInfo
        switch await bookResolver.findBook(title: title) {
        case .notFound:
            return error("No book with that title is in the library.")
        case .ambiguous:
            return error("Several books match that title; provide an unambiguous title.")
        case .found(let resolved):
            info = resolved
        }
        guard info.isReadable else {
            return error("That book is not downloaded to this device.")
        }
        let locator: Locator?
        if input["locator_json"] != nil {
            guard let decoded = AIReaderToolOutput.decodeLocator(input),
                  decoded.bookFingerprint.canonicalKey == info.fingerprintKey else {
                return error("The optional locator is invalid or belongs to another book.")
            }
            locator = decoded
        } else {
            locator = nil
        }
        guard !Task.isCancelled,
              await router.openBook(
                  fingerprintKey: info.fingerprintKey,
                  locator: locator
              ),
              !Task.isCancelled else {
            return error("Opening the book was cancelled or unavailable.")
        }
        return AIReaderToolOutput.boundedResult(
            "Opened \"\(ToolResultText.oneLine(info.title, maxChars: 120))\".",
            maxBytes: maxContentBytes
        )
    }

    private func error(_ message: String) -> ToolResult {
        AIReaderToolOutput.boundedResult(
            message, maxBytes: maxContentBytes, isError: true
        )
    }
}

private func locatorSchema(titleRequired: Bool) -> JSONValue {
    var properties: [String: JSONValue] = [
        "locator_json": .object([
            "type": .string("string"),
            "description": .string("A JSON-encoded VReader Locator returned by another tool."),
        ]),
    ]
    if titleRequired {
        properties["title"] = .object([
            "type": .string("string"),
            "description": .string("The exact library book title to open."),
        ])
    }
    return .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array(titleRequired
            ? [.string("title")]
            : [.string("locator_json")]),
    ])
}
