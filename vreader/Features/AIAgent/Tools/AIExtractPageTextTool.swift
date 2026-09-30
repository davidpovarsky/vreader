// Purpose: Model-facing tool for extracting text from a PDF page using native text or Vision OCR.
// Fully gated by AIAgentToolExecutionGate and spoiler-safe against the active reader boundary.

import Foundation

struct ExtractPageTextTool: AITool {
    static let toolName = "extract_page_text"
    let ocrService: any PDFOCRServicing
    let facade: any AIPDFDocumentFacading
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        ocrService: any PDFOCRServicing = PDFOCRService(),
        facade: any AIPDFDocumentFacading,
        context: any AIReaderToolContextProviding,
        authorizationGate: AIAgentToolExecutionGate,
        maxContentBytes: Int = 8_000
    ) {
        self.ocrService = ocrService
        self.facade = facade
        self.context = context
        self.authorizationGate = authorizationGate
        self.maxContentBytes = max(256, maxContentBytes)
    }

    var definition: ToolDefinition {
        ToolDefinition(
            name: Self.toolName,
            description: "Extract text from a specific PDF page, using OCR if the page is scanned or image-only.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "page": .object([
                        "type": .string("integer"),
                        "description": .string("The 1-based page number to read.")
                    ])
                ]),
                "required": .array([.string("page")])
            ])
        )
    }

    func run(_ input: JSONValue) async -> ToolResult {
        guard case .object(let dict) = input,
              case .number(let pageNum) = dict["page"],
              pageNum >= 1 else {
            return AIReaderToolOutput.boundedResult(
                "A positive 1-based page integer is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let pageIndex = Int(pageNum) - 1
        let totalPages = await facade.pageCount
        guard pageIndex < totalPages else {
            return AIReaderToolOutput.boundedResult(
                "Page \(Int(pageNum)) is out of range. Document has \(totalPages) pages.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        if let denied = await AICurrentReaderToolSupport.authorize(
            toolName: Self.toolName,
            action: "Extract text from page \(Int(pageNum))",
            context: context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await context.resolveDocument(), !Task.isCancelled else {
            return AIReaderToolOutput.boundedResult(
                "The exact active reader session is unavailable.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let snapshot = document.snapshot
        let boundaryPage = snapshot.readSoFarBoundary.sourceUnitIndex ?? 0

        // Check spoiler boundary
        if pageIndex > boundaryPage {
            let readAheadOutcome = await authorizationGate.authorize(AIAgentToolAuthorization.context(
                toolName: Self.toolName,
                action: "Read ahead to future page \(Int(pageNum))",
                category: .readAhead,
                bookFingerprintKey: snapshot.bookFingerprint.canonicalKey
            ))
            guard readAheadOutcome == .allowed else {
                return AIAgentToolAuthorization.errorResult(readAheadOutcome, maxBytes: maxContentBytes)
            }
        }

        do {
            let result = try await ocrService.extractPageText(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                pageIndex: pageIndex,
                facade: facade
            )

            let sourceTag = (result.source == .visionOCR) ? "Vision OCR" : "Native PDF Text"
            let header = "[Page \(Int(pageNum)) | \(sourceTag)]\n"
            let text = result.text.isEmpty ? "(No text detected on page \(Int(pageNum)))" : result.text
            return AIReaderToolOutput.boundedResult(
                header + text,
                maxBytes: maxContentBytes
            )
        } catch {
            return AIReaderToolOutput.boundedResult(
                "Page text extraction failed: \(error.localizedDescription)",
                maxBytes: maxContentBytes,
                isError: true
            )
        }
    }
}
