// Purpose: Model-facing tool for extracting text from a PDF page using native text or Vision OCR.
// Fully gated by AIAgentToolExecutionGate, emits structured provenance, and spoiler-safe against active reader boundary.

import Foundation

struct ExtractPageTextTool: AIContextualTool {
    static let toolName = "extract_page_text"
    let ocrService: any PDFOCRServicing
    let facade: (any AIPDFDocumentFacading)?
    let context: any AIReaderToolContextProviding
    let authorizationGate: AIAgentToolExecutionGate
    let maxContentBytes: Int

    init(
        ocrService: any PDFOCRServicing = PDFOCRService(),
        facade: (any AIPDFDocumentFacading)? = nil,
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
        await run(input, context: AIToolExecutionContext())
    }

    func run(_ input: JSONValue, context: AIToolExecutionContext) async -> ToolResult {
        guard case .object(let dict) = input,
              case .number(let pageNum) = dict["page"],
              pageNum >= 1 else {
            return AIReaderToolOutput.boundedResult(
                "A positive integer (1-based page number) is required.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        guard let pdfFacade = self.facade else {
            return AIReaderToolOutput.boundedResult(
                "PDF page source is unavailable for OCR extraction.",
                maxBytes: maxContentBytes,
                isError: true
            )
        }

        let pageIndex = Int(pageNum) - 1
        let totalPages = await pdfFacade.pageCount
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
            context: self.context,
            gate: authorizationGate,
            maxBytes: maxContentBytes
        ) { return denied }

        guard let document = await self.context.resolveDocument(), !Task.isCancelled else {
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
                actionDescription: "Read ahead to future page \(Int(pageNum))",
                category: .readAhead,
                bookFingerprintKey: snapshot.bookFingerprint.canonicalKey,
                readerSessionID: context.readerSessionID
            ))
            guard readAheadOutcome == .allowed else {
                return AIAgentToolAuthorization.errorResult(readAheadOutcome, maxBytes: maxContentBytes)
            }
        }

        do {
            let result = try await ocrService.extractPageText(
                bookKey: snapshot.bookFingerprint.canonicalKey,
                pageIndex: pageIndex,
                facade: pdfFacade
            )

            let bookTitle = await self.context.bookTitle
            let provenance = AISourceProvenance(
                bookFingerprintKey: snapshot.bookFingerprint.canonicalKey,
                bookTitle: bookTitle,
                locator: result.locator,
                sourceLabel: "Page \(Int(pageNum))",
                pageIndex: pageIndex,
                snippet: String(result.text.prefix(250)),
                retrievalMethod: .ocr,
                aheadOfReader: pageIndex > boundaryPage,
                toolCallID: context.toolCallID,
                isOCRDerived: result.isOCRDerived
            )
            await context.recordSources([provenance])

            let sourceTag = (result.source == PDFTextSource.visionOCR) ? "Vision OCR" : "Native PDF Text"
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
